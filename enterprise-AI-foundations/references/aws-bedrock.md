# AWS Bedrock Reference (Enterprise Path A2)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Your App (ECS / Lambda / EC2)                       │
│  ┌────────────────┐  ┌──────────────────────────┐   │
│  │ Bedrock Runtime│  │ Bedrock Knowledge Bases   │   │
│  │ (Claude/Titan) │  │ (managed RAG)             │   │
│  └───────┬────────┘  └───────────┬───────────────┘   │
│          │ IAM Role              │ IAM Role           │
│  ┌───────▼────────┐  ┌──────────▼───────────────┐   │
│  │ Bedrock        │  │ Amazon OpenSearch          │   │
│  │ Guardrails     │  │ Serverless (vector store)  │   │
│  └────────────────┘  └──────────────────────────┘   │
│  All within VPC + VPC Endpoints                      │
└─────────────────────────────────────────────────────┘
```

---

## Setup & Model Access

```bash
# Enable model access (must be done in console or via API for each model)
aws bedrock put-model-invocation-logging-configuration \
  --logging-config '{"textDataDeliveryEnabled": true, "s3Config": {"bucketName": "myapp-bedrock-logs", "keyPrefix": "invocations/"}}'

# List available models
aws bedrock list-foundation-models --query 'modelSummaries[].{id:modelId, name:modelName, provider:providerName}' --output table
```

### Available Models on Bedrock

| Model | Model ID | Best For |
|---|---|---|
| Claude Sonnet 4 | `anthropic.claude-sonnet-4-20250514-v1:0` | Balanced reasoning + cost |
| Claude Haiku 4.5 | `anthropic.claude-haiku-4-5-20251001-v1:0` | Fast, cheap, routing |
| Claude Opus 4.5 | `anthropic.claude-opus-4-5-20250917-v1:0` | Maximum reasoning |
| Titan Text | `amazon.titan-text-express-v1` | Basic text, AWS-native |
| Titan Embeddings | `amazon.titan-embed-text-v2:0` | Embeddings (1024 dims) |
| Llama 3.1 | `meta.llama3-1-70b-instruct-v1:0` | Open-source alternative |

---

## Provider Implementation

```typescript
// src/ai/clients/providers/bedrock.ts
import { BedrockRuntimeClient, InvokeModelCommand, InvokeModelWithResponseStreamCommand } from '@aws-sdk/client-bedrock-runtime'
import type { LLMProvider, LLMRequest, LLMResponse, LLMStreamChunk } from '../llm-client'

export function createBedrockProvider(region: string): LLMProvider {
  const client = new BedrockRuntimeClient({ region })
  // IAM role provides credentials automatically (no keys needed)

  return {
    name: 'bedrock',

    async complete(request: LLMRequest): Promise<LLMResponse> {
      const modelId = request.model || 'anthropic.claude-sonnet-4-20250514-v1:0'
      const start = Date.now()

      // Bedrock uses Anthropic's message format for Claude models
      const body = JSON.stringify({
        anthropic_version: 'bedrock-2023-05-31',
        max_tokens: request.maxTokens || 4096,
        temperature: request.temperature ?? 0.7,
        system: request.systemPrompt,
        messages: request.messages.map(m => ({
          role: m.role === 'tool' ? 'user' : m.role,
          content: typeof m.content === 'string' ? m.content : m.content.map(b => ({ type: 'text', text: b.text })),
        })),
        tools: request.tools?.map(t => ({
          name: t.name, description: t.description, input_schema: t.parameters,
        })),
      })

      const command = new InvokeModelCommand({
        modelId,
        contentType: 'application/json',
        accept: 'application/json',
        body: Buffer.from(body),
      })

      const response = await client.send(command)
      const result = JSON.parse(new TextDecoder().decode(response.body))

      return {
        content: result.content?.filter((b: any) => b.type === 'text').map((b: any) => b.text).join('') || '',
        toolCalls: result.content?.filter((b: any) => b.type === 'tool_use').map((b: any) => ({
          id: b.id, name: b.name, arguments: b.input,
        })),
        stopReason: result.stop_reason === 'tool_use' ? 'tool_use' : result.stop_reason === 'max_tokens' ? 'max_tokens' : 'end',
        usage: {
          inputTokens: result.usage?.input_tokens || 0,
          outputTokens: result.usage?.output_tokens || 0,
          totalTokens: (result.usage?.input_tokens || 0) + (result.usage?.output_tokens || 0),
          estimatedCost: 0,  // Bedrock pricing varies
        },
        model: modelId, provider: 'bedrock', latencyMs: Date.now() - start,
      }
    },

    async *stream(request: LLMRequest): AsyncIterable<LLMStreamChunk> {
      const modelId = request.model || 'anthropic.claude-sonnet-4-20250514-v1:0'

      const body = JSON.stringify({
        anthropic_version: 'bedrock-2023-05-31',
        max_tokens: request.maxTokens || 4096,
        temperature: request.temperature ?? 0.7,
        system: request.systemPrompt,
        messages: request.messages.map(m => ({
          role: m.role === 'tool' ? 'user' : m.role,
          content: typeof m.content === 'string' ? m.content : JSON.stringify(m.content),
        })),
      })

      const command = new InvokeModelWithResponseStreamCommand({
        modelId,
        contentType: 'application/json',
        accept: 'application/json',
        body: Buffer.from(body),
      })

      const response = await client.send(command)

      if (response.body) {
        for await (const event of response.body) {
          if (event.chunk?.bytes) {
            const data = JSON.parse(new TextDecoder().decode(event.chunk.bytes))
            if (data.type === 'content_block_delta' && data.delta?.text) {
              yield { type: 'text', text: data.delta.text }
            }
            if (data.type === 'message_delta') {
              yield { type: 'done', usage: {
                inputTokens: data.usage?.input_tokens || 0,
                outputTokens: data.usage?.output_tokens || 0,
                totalTokens: 0, estimatedCost: 0,
              }}
            }
          }
        }
      }
    },
  }
}
```

---

## Bedrock Knowledge Bases (Managed RAG)

For teams that want fully managed RAG without building their own pipeline:

```bash
# Create knowledge base (via console or SDK — complex CLI)
# 1. Create S3 bucket with documents
# 2. Create OpenSearch Serverless collection (vector store)
# 3. Create Knowledge Base linking S3 → OpenSearch
# 4. Sync documents (chunking + embedding done by Bedrock)

# Query knowledge base
aws bedrock-agent-runtime retrieve-and-generate \
  --input '{"text": "What is our refund policy?"}' \
  --retrieve-and-generate-configuration '{
    "type": "KNOWLEDGE_BASE",
    "knowledgeBaseConfiguration": {
      "knowledgeBaseId": "KBXXXXXX",
      "modelArn": "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
    }
  }'
```

```typescript
// Programmatic Knowledge Base query
import { BedrockAgentRuntimeClient, RetrieveAndGenerateCommand } from '@aws-sdk/client-bedrock-agent-runtime'

const agentClient = new BedrockAgentRuntimeClient({ region: env.AWS_REGION })

export async function queryKnowledgeBase(query: string, knowledgeBaseId: string) {
  const command = new RetrieveAndGenerateCommand({
    input: { text: query },
    retrieveAndGenerateConfiguration: {
      type: 'KNOWLEDGE_BASE',
      knowledgeBaseConfiguration: {
        knowledgeBaseId,
        modelArn: `arn:aws:bedrock:${env.AWS_REGION}::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0`,
        retrievalConfiguration: {
          vectorSearchConfiguration: { numberOfResults: 10 },
        },
      },
    },
  })

  const response = await agentClient.send(command)

  return {
    answer: response.output?.text || '',
    citations: response.citations?.map(c => ({
      text: c.generatedResponsePart?.textResponsePart?.text,
      sources: c.retrievedReferences?.map(r => ({
        content: r.content?.text,
        location: r.location?.s3Location?.uri,
      })),
    })),
  }
}
```

---

## Bedrock Guardrails (Managed Content Filtering)

```bash
# Create guardrail
aws bedrock create-guardrail \
  --name "myapp-guardrail" \
  --description "Content filtering for production" \
  --content-policy-config '{
    "filtersConfig": [
      {"type": "SEXUAL", "inputStrength": "HIGH", "outputStrength": "HIGH"},
      {"type": "VIOLENCE", "inputStrength": "HIGH", "outputStrength": "HIGH"},
      {"type": "HATE", "inputStrength": "HIGH", "outputStrength": "HIGH"},
      {"type": "INSULTS", "inputStrength": "MEDIUM", "outputStrength": "MEDIUM"},
      {"type": "MISCONDUCT", "inputStrength": "HIGH", "outputStrength": "HIGH"},
      {"type": "PROMPT_ATTACK", "inputStrength": "HIGH", "outputStrength": "NONE"}
    ]
  }' \
  --sensitive-information-policy-config '{
    "piiEntitiesConfig": [
      {"type": "EMAIL", "action": "ANONYMIZE"},
      {"type": "PHONE", "action": "ANONYMIZE"},
      {"type": "US_SOCIAL_SECURITY_NUMBER", "action": "BLOCK"},
      {"type": "CREDIT_DEBIT_CARD_NUMBER", "action": "BLOCK"}
    ]
  }' \
  --blocked-input-messaging "I cannot process this request." \
  --blocked-output-messaging "I cannot provide this response."
```

```typescript
// Apply guardrail to model invocations
const command = new InvokeModelCommand({
  modelId: 'anthropic.claude-sonnet-4-20250514-v1:0',
  guardrailIdentifier: 'myapp-guardrail',
  guardrailVersion: 'DRAFT',     // Or specific version number
  contentType: 'application/json',
  body: Buffer.from(JSON.stringify({ /* ... */ })),
})
```

---

## Bedrock Embeddings (Titan)

```typescript
export function createBedrockEmbeddings(region: string): EmbeddingProvider {
  const client = new BedrockRuntimeClient({ region })

  return {
    name: 'bedrock-titan',
    dimensions: 1024,
    async embed(texts: string[]) {
      const results: number[][] = []
      for (const text of texts) {
        const command = new InvokeModelCommand({
          modelId: 'amazon.titan-embed-text-v2:0',
          contentType: 'application/json',
          body: Buffer.from(JSON.stringify({ inputText: text, dimensions: 1024, normalize: true })),
        })
        const response = await client.send(command)
        const result = JSON.parse(new TextDecoder().decode(response.body))
        results.push(result.embedding)
      }
      return results
    },
  }
}
```

---

## VPC Endpoints (Private Access)

```bash
# Bedrock Runtime VPC Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxx \
  --service-name com.amazonaws.us-east-1.bedrock-runtime \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-xxx \
  --security-group-ids sg-xxx \
  --private-dns-enabled

# Bedrock Agent Runtime (for Knowledge Bases)
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxx \
  --service-name com.amazonaws.us-east-1.bedrock-agent-runtime \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-xxx \
  --security-group-ids sg-xxx
```

---

## IAM Policies

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": [
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-*",
        "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:Retrieve",
        "bedrock:RetrieveAndGenerate"
      ],
      "Resource": "arn:aws:bedrock:us-east-1:ACCOUNT_ID:knowledge-base/*"
    },
    {
      "Effect": "Allow",
      "Action": "bedrock:ApplyGuardrail",
      "Resource": "arn:aws:bedrock:us-east-1:ACCOUNT_ID:guardrail/*"
    }
  ]
}
```

---

## Checklist (AWS Bedrock)

- [ ] Model access enabled for required models in Bedrock console
- [ ] IAM role with least-privilege Bedrock permissions
- [ ] VPC Endpoints created for private access (no internet traffic)
- [ ] Guardrails configured for content filtering + PII protection
- [ ] Knowledge Base synced with S3 documents (if using managed RAG)
- [ ] Model invocation logging enabled to S3 for audit
- [ ] Cost alerts set in AWS Budgets for Bedrock usage
- [ ] Cross-region inference disabled unless needed (data residency)

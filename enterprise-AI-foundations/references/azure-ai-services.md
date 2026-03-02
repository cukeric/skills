# Azure AI Services Reference (Enterprise Path A)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Your App (App Service / Container Apps)             │
│  ┌────────────────┐  ┌──────────────────────────┐   │
│  │ Azure OpenAI   │  │ Azure AI Search           │   │
│  │ (LLM + embed)  │  │ (vector + keyword search) │   │
│  └───────┬────────┘  └────────────┬──────────────┘   │
│          │ Managed Identity       │ Managed Identity  │
│  ┌───────▼────────┐  ┌───────────▼──────────────┐   │
│  │ Key Vault      │  │ Azure Document Intelligence│  │
│  │ (API keys if   │  │ (PDF/image parsing)        │  │
│  │  needed)       │  └──────────────────────────┘   │
│  └────────────────┘                                  │
│  All within VNet + Private Endpoints                 │
└─────────────────────────────────────────────────────┘
```

---

## Azure OpenAI

### Setup

```bash
# Create Azure OpenAI resource
az cognitiveservices account create \
  --name myapp-openai \
  --resource-group $RG \
  --kind OpenAI \
  --sku S0 \
  --location eastus2 \
  --custom-domain myapp-openai

# Deploy a model
az cognitiveservices account deployment create \
  --name myapp-openai \
  --resource-group $RG \
  --deployment-name gpt-4o \
  --model-name gpt-4o \
  --model-version "2024-11-20" \
  --model-format OpenAI \
  --sku-capacity 80 \
  --sku-name Standard

# Deploy embedding model
az cognitiveservices account deployment create \
  --name myapp-openai \
  --resource-group $RG \
  --deployment-name text-embedding-3-small \
  --model-name text-embedding-3-small \
  --model-version "1" \
  --model-format OpenAI \
  --sku-capacity 120 \
  --sku-name Standard

# Get endpoint
az cognitiveservices account show --name myapp-openai --resource-group $RG --query properties.endpoint -o tsv
```

### Provider Implementation (Managed Identity)

```typescript
// src/ai/clients/providers/azure-openai.ts
import { AzureOpenAI } from 'openai'
import { DefaultAzureCredential } from '@azure/identity'
import type { LLMProvider, LLMRequest, LLMResponse } from '../llm-client'

export function createAzureOpenAIProvider(endpoint: string, apiKey?: string): LLMProvider {
  // Prefer Managed Identity (no API key needed)
  const client = apiKey
    ? new AzureOpenAI({ endpoint, apiKey, apiVersion: '2024-10-21' })
    : new AzureOpenAI({
        endpoint,
        azureADTokenProvider: async () => {
          const credential = new DefaultAzureCredential()
          const token = await credential.getToken('https://cognitiveservices.azure.com/.default')
          return token.token
        },
        apiVersion: '2024-10-21',
      })

  return {
    name: 'azure-openai',

    async complete(request: LLMRequest): Promise<LLMResponse> {
      const deploymentName = request.model || 'gpt-4o'  // Must match deployment name
      const start = Date.now()

      const response = await client.chat.completions.create({
        model: deploymentName,
        messages: [
          ...(request.systemPrompt ? [{ role: 'system' as const, content: request.systemPrompt }] : []),
          ...request.messages.map(m => ({ role: m.role as any, content: typeof m.content === 'string' ? m.content : '' })),
        ],
        max_tokens: request.maxTokens || 4096,
        temperature: request.temperature ?? 0.7,
        tools: request.tools?.map(t => ({
          type: 'function' as const,
          function: { name: t.name, description: t.description, parameters: t.parameters },
        })),
      })

      const choice = response.choices[0]
      return {
        content: choice.message.content || '',
        toolCalls: choice.message.tool_calls?.map(tc => ({
          id: tc.id, name: tc.function.name, arguments: JSON.parse(tc.function.arguments),
        })),
        stopReason: choice.finish_reason === 'tool_calls' ? 'tool_use' : 'end',
        usage: {
          inputTokens: response.usage?.prompt_tokens || 0,
          outputTokens: response.usage?.completion_tokens || 0,
          totalTokens: response.usage?.total_tokens || 0,
          estimatedCost: 0,  // Azure pricing varies by PTU vs pay-per-token
        },
        model: deploymentName, provider: 'azure-openai', latencyMs: Date.now() - start,
      }
    },

    async *stream(request: LLMRequest) {
      const deploymentName = request.model || 'gpt-4o'
      const stream = await client.chat.completions.create({
        model: deploymentName,
        messages: [
          ...(request.systemPrompt ? [{ role: 'system' as const, content: request.systemPrompt }] : []),
          ...request.messages.map(m => ({ role: m.role as any, content: typeof m.content === 'string' ? m.content : '' })),
        ],
        max_tokens: request.maxTokens || 4096,
        stream: true,
        stream_options: { include_usage: true },
      })

      for await (const chunk of stream) {
        if (chunk.choices[0]?.delta?.content) yield { type: 'text' as const, text: chunk.choices[0].delta.content }
        if (chunk.usage) yield { type: 'done' as const, usage: { inputTokens: chunk.usage.prompt_tokens, outputTokens: chunk.usage.completion_tokens, totalTokens: chunk.usage.total_tokens, estimatedCost: 0 } }
      }
    },
  }
}
```

### Azure OpenAI Embeddings

```typescript
export function createAzureOpenAIEmbeddings(endpoint: string): EmbeddingProvider {
  const client = new AzureOpenAI({
    endpoint,
    azureADTokenProvider: async () => {
      const credential = new DefaultAzureCredential()
      return (await credential.getToken('https://cognitiveservices.azure.com/.default')).token
    },
    apiVersion: '2024-10-21',
  })

  return {
    name: 'azure-openai',
    dimensions: 1536,
    async embed(texts: string[]) {
      const response = await client.embeddings.create({
        model: 'text-embedding-3-small',  // Deployment name
        input: texts,
      })
      return response.data.map(d => d.embedding)
    },
  }
}
```

---

## Azure AI Search (Vector + Keyword Hybrid Search)

### Setup

```bash
az search service create \
  --name myapp-search \
  --resource-group $RG \
  --sku Standard \
  --location $LOCATION \
  --partition-count 1 \
  --replica-count 1
```

### Index Creation

```typescript
import { SearchIndexClient, AzureKeyCredential } from '@azure/search-documents'

const indexClient = new SearchIndexClient(env.AZURE_SEARCH_ENDPOINT, new AzureKeyCredential(env.AZURE_SEARCH_KEY))

await indexClient.createOrUpdateIndex({
  name: 'documents',
  fields: [
    { name: 'id', type: 'Edm.String', key: true, filterable: true },
    { name: 'content', type: 'Edm.String', searchable: true, analyzerName: 'en.microsoft' },
    { name: 'contentVector', type: 'Collection(Edm.Single)', searchable: true, vectorSearchDimensions: 1536, vectorSearchProfileName: 'vector-profile' },
    { name: 'title', type: 'Edm.String', searchable: true, filterable: true, sortable: true },
    { name: 'source', type: 'Edm.String', filterable: true, facetable: true },
    { name: 'chunkIndex', type: 'Edm.Int32', filterable: true, sortable: true },
    { name: 'metadata', type: 'Edm.String', filterable: false },
    { name: 'tenantId', type: 'Edm.String', filterable: true },  // Multi-tenant isolation
    { name: 'createdAt', type: 'Edm.DateTimeOffset', filterable: true, sortable: true },
  ],
  vectorSearch: {
    profiles: [{ name: 'vector-profile', algorithmConfigurationName: 'hnsw-config', vectorizerName: undefined }],
    algorithms: [{ name: 'hnsw-config', kind: 'hnsw', parameters: { metric: 'cosine', m: 4, efConstruction: 400, efSearch: 500 } }],
  },
  semanticSearch: {
    configurations: [{
      name: 'semantic-config',
      prioritizedFields: { contentFields: [{ name: 'content' }], titleField: { name: 'title' } },
    }],
  },
})
```

### Hybrid Search (Vector + Keyword + Semantic Reranking)

```typescript
import { SearchClient } from '@azure/search-documents'

const searchClient = new SearchClient(env.AZURE_SEARCH_ENDPOINT, 'documents', new AzureKeyCredential(env.AZURE_SEARCH_KEY))

export async function hybridSearch(query: string, queryVector: number[], options: { tenantId?: string; topK?: number; filter?: string }) {
  const results = await searchClient.search(query, {
    vectorSearchOptions: {
      queries: [{ kind: 'vector', vector: queryVector, kNearestNeighborsCount: options.topK || 10, fields: ['contentVector'] }],
    },
    queryType: 'semantic',
    semanticSearchOptions: { configurationName: 'semantic-config' },
    filter: options.tenantId ? `tenantId eq '${options.tenantId}'` : options.filter,
    top: options.topK || 10,
    select: ['id', 'content', 'title', 'source', 'chunkIndex', 'metadata'],
  })

  const docs = []
  for await (const result of results.results) {
    docs.push({
      id: result.document.id,
      content: result.document.content,
      title: result.document.title,
      source: result.document.source,
      score: result.score,
      rerankerScore: result.rerankerScore,
    })
  }
  return docs
}
```

---

## Azure Document Intelligence (PDF/Image Parsing)

```bash
az cognitiveservices account create \
  --name myapp-docintel \
  --resource-group $RG \
  --kind FormRecognizer \
  --sku S0 \
  --location $LOCATION
```

```typescript
import { DocumentIntelligenceClient } from '@azure-rest/ai-document-intelligence'
import { DefaultAzureCredential } from '@azure/identity'

const docClient = DocumentIntelligenceClient(env.AZURE_DOCINTEL_ENDPOINT, new DefaultAzureCredential())

export async function extractFromDocument(fileBuffer: Buffer, contentType: string) {
  const poller = await docClient.path('/documentModels/prebuilt-layout:analyze').post({
    contentType: contentType as any,
    body: fileBuffer,
    queryParameters: { outputContentFormat: 'markdown' },
  })

  const result = await poller.pollUntilDone()
  // Returns structured markdown with tables, headers, paragraphs preserved
  return result.body.analyzeResult?.content || ''
}
```

---

## Networking: Private Endpoints for AI Services

```bash
# Private Endpoint for Azure OpenAI
az network private-endpoint create \
  --name myapp-openai-pe \
  --resource-group $RG \
  --vnet-name myapp-vnet \
  --subnet ai-subnet \
  --private-connection-resource-id $(az cognitiveservices account show --name myapp-openai --resource-group $RG --query id -o tsv) \
  --group-id account \
  --connection-name openai-connection

# Private Endpoint for Azure AI Search
az network private-endpoint create \
  --name myapp-search-pe \
  --resource-group $RG \
  --vnet-name myapp-vnet \
  --subnet ai-subnet \
  --private-connection-resource-id $(az search service show --name myapp-search --resource-group $RG --query id -o tsv) \
  --group-id searchService \
  --connection-name search-connection

# Disable public access
az cognitiveservices account update --name myapp-openai --resource-group $RG --public-network-access Disabled
az search service update --name myapp-search --resource-group $RG --public-network-access Disabled
```

---

## Bicep Module for AI Resources

```bicep
// infra/modules/ai-services.bicep
param prefix string
param location string
param subnetId string
param keyVaultName string

resource openai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: '${prefix}-openai'
  location: location
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny' }
    customSubDomainName: '${prefix}-openai'
  }
  identity: { type: 'SystemAssigned' }
}

resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openai
  name: 'gpt-4o'
  sku: { name: 'Standard', capacity: 80 }
  properties: {
    model: { format: 'OpenAI', name: 'gpt-4o', version: '2024-11-20' }
  }
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openai
  name: 'text-embedding-3-small'
  sku: { name: 'Standard', capacity: 120 }
  properties: {
    model: { format: 'OpenAI', name: 'text-embedding-3-small', version: '1' }
  }
}

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: '${prefix}-search'
  location: location
  sku: { name: 'standard' }
  properties: {
    publicNetworkAccess: 'disabled'
    partitionCount: 1
    replicaCount: 1
  }
  identity: { type: 'SystemAssigned' }
}

// Store keys in Key Vault
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = { name: keyVaultName }

resource openaiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'azure-openai-key'
  properties: { value: openai.listKeys().key1 }
}

output openaiEndpoint string = openai.properties.endpoint
output searchEndpoint string = 'https://${search.name}.search.windows.net'
```

---

## Checklist (Azure AI)

- [ ] Azure OpenAI resource created with model deployments
- [ ] Managed Identity used for authentication (no API keys in code)
- [ ] Private Endpoints enabled, public access disabled
- [ ] Azure AI Search index created with vector + keyword fields
- [ ] Hybrid search (vector + keyword + semantic reranking) tested
- [ ] Document Intelligence configured for PDF/image parsing
- [ ] All AI resources within VNet
- [ ] Keys stored in Key Vault (if Managed Identity not possible)
- [ ] Provisioned throughput (PTU) evaluated for production workloads
- [ ] Content filtering configured in Azure OpenAI (default or custom)

# AI Evaluation & Testing Reference

## Why Evaluate

LLM outputs are non-deterministic. Unlike traditional software where tests are pass/fail, AI evaluation requires probabilistic and qualitative measures. Without evaluation, you don't know if your AI features are improving or regressing.

---

## Evaluation Framework

```
┌─────────────────────────────────────────────────────┐
│                 Evaluation Layers                    │
│                                                      │
│  Layer 1: Unit Tests (deterministic)                 │
│  ├── Tool input/output validation                    │
│  ├── Guardrail pattern matching                      │
│  └── Chunk/embedding pipeline correctness            │
│                                                      │
│  Layer 2: LLM-as-Judge (automated quality)           │
│  ├── RAG faithfulness & relevance                    │
│  ├── Response quality scoring                        │
│  └── Safety compliance checks                        │
│                                                      │
│  Layer 3: Regression Benchmarks (dataset-based)      │
│  ├── Known Q&A pairs                                 │
│  ├── Before/after model changes                      │
│  └── A/B testing live traffic                        │
│                                                      │
│  Layer 4: Human Evaluation (gold standard)           │
│  ├── Expert review of edge cases                     │
│  └── User feedback (thumbs up/down)                  │
└─────────────────────────────────────────────────────┘
```

---

## RAG Evaluation Metrics

| Metric | What It Measures | How to Compute |
|---|---|---|
| **Faithfulness** | Is the answer grounded in retrieved context? | LLM-as-judge: does each claim have a supporting chunk? |
| **Relevance** | Does the answer address the question? | LLM-as-judge: score 1-5 |
| **Context Precision** | Are retrieved chunks actually relevant? | % of top-K chunks relevant to the question |
| **Context Recall** | Did retrieval find all relevant information? | % of ground-truth facts covered by retrieved chunks |
| **Answer Correctness** | Is the answer factually correct? | Compare against ground truth (if available) |
| **Hallucination Rate** | % of claims not grounded in context | Count ungrounded claims / total claims |

### RAG Evaluation Implementation

```typescript
// src/ai/evaluation/rag-eval.ts

export interface RAGEvalResult {
  faithfulness: number       // 0-1: grounded in context
  relevance: number          // 0-1: answers the question
  contextPrecision: number   // 0-1: retrieved chunks are relevant
  hallucinations: string[]   // List of ungrounded claims
  overallScore: number       // Weighted average
}

export async function evaluateRAGResponse(
  llmClient: LLMProvider,
  question: string,
  answer: string,
  retrievedChunks: string[],
  groundTruth?: string,        // Expected answer (if available)
): Promise<RAGEvalResult> {

  // 1. Faithfulness: Is each claim in the answer supported by the context?
  const faithfulnessResponse = await llmClient.complete({
    systemPrompt: `You are an evaluation judge. Given a question, an answer, and source context, determine if each claim in the answer is supported by the context.

Return JSON:
{
  "claims": [
    { "claim": "...", "supported": true/false, "evidence": "quote from context or null" }
  ],
  "faithfulness_score": 0.0 to 1.0
}`,
    messages: [{
      role: 'user',
      content: `Question: ${question}\n\nAnswer: ${answer}\n\nContext:\n${retrievedChunks.join('\n\n---\n\n')}`,
    }],
    temperature: 0,
    model: 'claude-sonnet-4-20250514',
  })

  // 2. Relevance: Does the answer actually address the question?
  const relevanceResponse = await llmClient.complete({
    systemPrompt: `Rate how well this answer addresses the question on a scale of 0 to 1. Return JSON: { "relevance_score": 0.0 to 1.0, "explanation": "..." }`,
    messages: [{
      role: 'user',
      content: `Question: ${question}\n\nAnswer: ${answer}`,
    }],
    temperature: 0,
    model: 'claude-haiku-4-5-20251001',
  })

  // 3. Context Precision: Are the retrieved chunks relevant to the question?
  const precisionResponse = await llmClient.complete({
    systemPrompt: `For each context chunk, determine if it's relevant to answering the question. Return JSON: { "chunks": [{ "index": 0, "relevant": true/false }], "precision_score": 0.0 to 1.0 }`,
    messages: [{
      role: 'user',
      content: `Question: ${question}\n\nChunks:\n${retrievedChunks.map((c, i) => `[${i}] ${c.slice(0, 300)}`).join('\n\n')}`,
    }],
    temperature: 0,
    model: 'claude-haiku-4-5-20251001',
  })

  // Parse results
  const faithfulness = parseJSONSafe(faithfulnessResponse.content)
  const relevance = parseJSONSafe(relevanceResponse.content)
  const precision = parseJSONSafe(precisionResponse.content)

  const faithfulnessScore = faithfulness?.faithfulness_score ?? 0
  const relevanceScore = relevance?.relevance_score ?? 0
  const precisionScore = precision?.precision_score ?? 0
  const hallucinations = (faithfulness?.claims || [])
    .filter((c: any) => !c.supported)
    .map((c: any) => c.claim)

  return {
    faithfulness: faithfulnessScore,
    relevance: relevanceScore,
    contextPrecision: precisionScore,
    hallucinations,
    overallScore: faithfulnessScore * 0.4 + relevanceScore * 0.4 + precisionScore * 0.2,
  }
}

function parseJSONSafe(text: string): any {
  try {
    return JSON.parse(text.replace(/```json\n?|```/g, '').trim())
  } catch { return null }
}
```

---

## Agent Evaluation

```typescript
// src/ai/evaluation/agent-eval.ts

export interface AgentEvalResult {
  taskCompletion: boolean     // Did the agent complete the task?
  correctToolSequence: boolean // Did it use the right tools in the right order?
  efficiency: number           // 0-1: fewer iterations = more efficient
  safetyViolations: string[]   // Any unsafe actions attempted
}

export async function evaluateAgentRun(
  taskDescription: string,
  expectedTools: string[],        // Expected tool call sequence
  actualToolCalls: { tool: string; args: Record<string, unknown>; result: unknown }[],
  finalResponse: string,
  iterations: number,
  maxExpectedIterations: number,
  llmClient: LLMProvider,
): Promise<AgentEvalResult> {

  // 1. Task completion: Did the agent's final response address the task?
  const completionResponse = await llmClient.complete({
    systemPrompt: 'Evaluate if the agent completed the given task. Return JSON: { "completed": true/false, "explanation": "..." }',
    messages: [{
      role: 'user',
      content: `Task: ${taskDescription}\n\nAgent's final response: ${finalResponse}\n\nTools used: ${actualToolCalls.map(tc => tc.tool).join(' → ')}`,
    }],
    temperature: 0,
  })

  const completion = parseJSONSafe(completionResponse.content)

  // 2. Tool sequence correctness
  const actualSequence = actualToolCalls.map(tc => tc.name)
  const correctSequence = expectedTools.length === 0 || expectedTools.every((t, i) => actualSequence[i] === t)

  // 3. Efficiency
  const efficiency = Math.max(0, 1 - (iterations - 1) / maxExpectedIterations)

  // 4. Safety check
  const safetyViolations: string[] = []
  for (const tc of actualToolCalls) {
    if (['delete_record', 'drop_table'].includes(tc.tool) && !tc.args._approved) {
      safetyViolations.push(`Destructive action without approval: ${tc.tool}`)
    }
  }

  return {
    taskCompletion: completion?.completed ?? false,
    correctToolSequence: correctSequence,
    efficiency,
    safetyViolations,
  }
}
```

---

## Evaluation Dataset Management

```typescript
// src/ai/evaluation/dataset.ts

export interface EvalExample {
  id: string
  question: string
  expectedAnswer?: string           // Ground truth (if available)
  expectedSources?: string[]        // Expected source documents
  expectedTools?: string[]           // Expected tool sequence (for agents)
  category: string                   // 'factual' | 'reasoning' | 'multi-hop' | 'edge_case'
  difficulty: 'easy' | 'medium' | 'hard'
}

// Store evaluation datasets in PostgreSQL
// CREATE TABLE eval_datasets (
//   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
//   name TEXT NOT NULL UNIQUE,
//   description TEXT,
//   created_at TIMESTAMPTZ DEFAULT NOW()
// );
// CREATE TABLE eval_examples (
//   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
//   dataset_id UUID REFERENCES eval_datasets(id) ON DELETE CASCADE,
//   question TEXT NOT NULL,
//   expected_answer TEXT,
//   expected_sources TEXT[],
//   expected_tools TEXT[],
//   category TEXT NOT NULL,
//   difficulty TEXT NOT NULL,
//   metadata JSONB DEFAULT '{}'
// );

export function createEvalDatasetManager(pool: Pool) {
  return {
    async createDataset(name: string, description: string): Promise<string> {
      const result = await pool.query('INSERT INTO eval_datasets (name, description) VALUES ($1, $2) RETURNING id', [name, description])
      return result.rows[0].id
    },

    async addExamples(datasetId: string, examples: Omit<EvalExample, 'id'>[]) {
      for (const ex of examples) {
        await pool.query(
          'INSERT INTO eval_examples (dataset_id, question, expected_answer, expected_sources, expected_tools, category, difficulty) VALUES ($1, $2, $3, $4, $5, $6, $7)',
          [datasetId, ex.question, ex.expectedAnswer, ex.expectedSources, ex.expectedTools, ex.category, ex.difficulty]
        )
      }
    },

    async getExamples(datasetId: string): Promise<EvalExample[]> {
      const result = await pool.query('SELECT * FROM eval_examples WHERE dataset_id = $1', [datasetId])
      return result.rows
    },
  }
}
```

---

## Regression Benchmark Runner

```typescript
// src/ai/evaluation/benchmark.ts

export interface BenchmarkResult {
  datasetName: string
  modelUsed: string
  timestamp: Date
  totalExamples: number
  metrics: {
    avgFaithfulness: number
    avgRelevance: number
    avgContextPrecision: number
    hallucinationRate: number
    avgLatencyMs: number
    totalCost: number
  }
  perExample: {
    id: string
    question: string
    answer: string
    scores: RAGEvalResult
    latencyMs: number
  }[]
}

export async function runBenchmark(
  ragPipeline: RAGPipeline,
  llmClient: LLMProvider,
  dataset: EvalExample[],
  options?: { model?: string; concurrency?: number },
): Promise<BenchmarkResult> {
  const results: BenchmarkResult['perExample'] = []
  const concurrency = options?.concurrency || 3

  // Process in batches
  for (let i = 0; i < dataset.length; i += concurrency) {
    const batch = dataset.slice(i, i + concurrency)
    const batchResults = await Promise.all(
      batch.map(async (example) => {
        const start = Date.now()
        const ragResult = await ragPipeline.query(example.question, { topK: 5 })
        const latencyMs = Date.now() - start

        const evalResult = await evaluateRAGResponse(
          llmClient,
          example.question,
          ragResult.answer,
          ragResult.sources.map(s => s.content),
          example.expectedAnswer,
        )

        return { id: example.id, question: example.question, answer: ragResult.answer, scores: evalResult, latencyMs }
      })
    )
    results.push(...batchResults)
  }

  // Aggregate metrics
  const avgFaithfulness = results.reduce((sum, r) => sum + r.scores.faithfulness, 0) / results.length
  const avgRelevance = results.reduce((sum, r) => sum + r.scores.relevance, 0) / results.length
  const avgPrecision = results.reduce((sum, r) => sum + r.scores.contextPrecision, 0) / results.length
  const totalHallucinations = results.reduce((sum, r) => sum + r.scores.hallucinations.length, 0)
  const avgLatency = results.reduce((sum, r) => sum + r.latencyMs, 0) / results.length

  return {
    datasetName: '',
    modelUsed: options?.model || 'default',
    timestamp: new Date(),
    totalExamples: results.length,
    metrics: {
      avgFaithfulness,
      avgRelevance,
      avgContextPrecision: avgPrecision,
      hallucinationRate: totalHallucinations / results.length,
      avgLatencyMs: avgLatency,
      totalCost: 0,
    },
    perExample: results,
  }
}

// Store benchmark results for comparison
// CREATE TABLE eval_benchmark_runs (
//   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
//   dataset_id UUID REFERENCES eval_datasets(id),
//   model_used TEXT NOT NULL,
//   run_at TIMESTAMPTZ DEFAULT NOW(),
//   total_examples INTEGER,
//   avg_faithfulness NUMERIC(4,3),
//   avg_relevance NUMERIC(4,3),
//   avg_context_precision NUMERIC(4,3),
//   hallucination_rate NUMERIC(4,3),
//   avg_latency_ms INTEGER,
//   total_cost NUMERIC(10,4),
//   details JSONB
// );
```

---

## LLM-as-Judge: General Quality Scorer

```typescript
// Generic quality evaluation — use for any LLM output

export async function scoreQuality(
  llmClient: LLMProvider,
  prompt: string,
  response: string,
  criteria: { name: string; description: string; weight: number }[],
): Promise<{ scores: Record<string, number>; overall: number; feedback: string }> {

  const criteriaList = criteria.map(c => `- ${c.name} (weight: ${c.weight}): ${c.description}`).join('\n')

  const evalResponse = await llmClient.complete({
    systemPrompt: `You are an expert evaluator. Score the response on each criterion (0-10). Return JSON:
{
  "scores": { "criterion_name": score, ... },
  "overall": weighted_average,
  "feedback": "brief constructive feedback"
}`,
    messages: [{
      role: 'user',
      content: `Criteria:\n${criteriaList}\n\nPrompt: ${prompt}\n\nResponse: ${response}`,
    }],
    temperature: 0,
    model: 'claude-sonnet-4-20250514',
  })

  const result = parseJSONSafe(evalResponse.content) || { scores: {}, overall: 0, feedback: '' }

  // Normalize to 0-1
  const normalizedScores: Record<string, number> = {}
  for (const [key, value] of Object.entries(result.scores)) {
    normalizedScores[key] = (value as number) / 10
  }

  const weightedScore = criteria.reduce((sum, c) => sum + (normalizedScores[c.name] || 0) * c.weight, 0) / criteria.reduce((sum, c) => sum + c.weight, 0)

  return { scores: normalizedScores, overall: weightedScore, feedback: result.feedback }
}

// Predefined quality criteria
export const QUALITY_CRITERIA = {
  helpfulness: { name: 'helpfulness', description: 'Does the response address the user need?', weight: 3 },
  accuracy: { name: 'accuracy', description: 'Is the information factually correct?', weight: 3 },
  completeness: { name: 'completeness', description: 'Does it cover the full scope of the question?', weight: 2 },
  clarity: { name: 'clarity', description: 'Is it clear, well-organized, and easy to understand?', weight: 1 },
  conciseness: { name: 'conciseness', description: 'Is it appropriately brief without unnecessary padding?', weight: 1 },
}
```

---

## A/B Testing

```typescript
// Compare two models or prompts on live traffic

export function createABTest(config: {
  name: string
  variantA: { model?: string; systemPrompt?: string }
  variantB: { model?: string; systemPrompt?: string }
  trafficSplit: number   // 0-1, percentage to variant B
}) {
  return {
    getVariant(userId: string): 'A' | 'B' {
      // Consistent assignment: same user always gets same variant
      const hash = crypto.createHash('md5').update(`${config.name}:${userId}`).digest('hex')
      const value = parseInt(hash.slice(0, 8), 16) / 0xffffffff
      return value < config.trafficSplit ? 'B' : 'A'
    },

    getConfig(variant: 'A' | 'B') {
      return variant === 'A' ? config.variantA : config.variantB
    },

    async recordOutcome(variant: 'A' | 'B', metrics: { quality: number; latencyMs: number; cost: number; userFeedback?: 'positive' | 'negative' }) {
      await pool.query(
        'INSERT INTO ab_test_results (test_name, variant, quality, latency_ms, cost, user_feedback) VALUES ($1, $2, $3, $4, $5, $6)',
        [config.name, variant, metrics.quality, metrics.latencyMs, metrics.cost, metrics.userFeedback]
      )
    },
  }
}
```

---

## User Feedback Collection

```typescript
// Thumbs up/down on AI responses — simplest, most valuable signal

app.post('/api/ai/feedback', { preHandler: [authGuard] }, async (req) => {
  const { messageId, rating, comment } = z.object({
    messageId: z.string().uuid(),
    rating: z.enum(['positive', 'negative']),
    comment: z.string().max(1000).optional(),
  }).parse(req.body)

  await pool.query(
    'INSERT INTO ai_feedback (message_id, user_id, rating, comment) VALUES ($1, $2, $3, $4)',
    [messageId, req.user.id, rating, comment]
  )

  // Use negative feedback to build regression test cases
  if (rating === 'negative') {
    const message = await pool.query('SELECT question, answer FROM conversation_messages WHERE id = $1', [messageId])
    if (message.rows[0]) {
      logger.info({ messageId, question: message.rows[0].question }, 'Negative feedback — candidate for eval dataset')
    }
  }
})

// Schema:
// CREATE TABLE ai_feedback (
//   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
//   message_id UUID NOT NULL,
//   user_id TEXT NOT NULL,
//   rating TEXT NOT NULL CHECK (rating IN ('positive', 'negative')),
//   comment TEXT,
//   created_at TIMESTAMPTZ DEFAULT NOW()
// );
```

---

## CI/CD Evaluation Pipeline

```yaml
# .github/workflows/ai-eval.yml
name: AI Evaluation
on:
  pull_request:
    paths: ['src/ai/**', 'prompts/**']

jobs:
  evaluate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run unit tests
        run: pnpm test -- --filter=ai

      - name: Run RAG benchmark
        run: |
          pnpm tsx scripts/run-benchmark.ts \
            --dataset=core-qa \
            --model=claude-sonnet-4-20250514
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}

      - name: Compare with baseline
        run: |
          pnpm tsx scripts/compare-benchmarks.ts \
            --current=benchmark-results.json \
            --baseline=benchmarks/baseline.json \
            --threshold=0.05
        # Fails if any metric drops more than 5% from baseline

      - name: Post results to PR
        uses: actions/github-script@v7
        with:
          script: |
            const results = require('./benchmark-results.json')
            const body = `## AI Evaluation Results
            | Metric | Score | Baseline | Delta |
            |---|---|---|---|
            | Faithfulness | ${results.metrics.avgFaithfulness.toFixed(3)} | ... | ... |
            | Relevance | ${results.metrics.avgRelevance.toFixed(3)} | ... | ... |
            `
            github.rest.issues.createComment({ owner: context.repo.owner, repo: context.repo.repo, issue_number: context.issue.number, body })
```

---

## Checklist

- [ ] Evaluation dataset: 50+ examples covering easy/medium/hard, multiple categories
- [ ] RAG evaluation: faithfulness, relevance, context precision measured
- [ ] Agent evaluation: task completion, tool correctness, safety violations
- [ ] LLM-as-judge: automated quality scoring for all AI outputs
- [ ] Regression benchmarks: run on every PR that changes AI code
- [ ] Baseline comparison: alert if quality drops beyond threshold (5%)
- [ ] User feedback: thumbs up/down collected, negative feedback → eval dataset
- [ ] A/B testing: framework for comparing models/prompts on live traffic
- [ ] CI/CD integration: evaluations run automatically in pull request pipeline

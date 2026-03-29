# Local / Offline Embeddings Reference

Covers `@huggingface/transformers` (formerly `Xenova/transformers.js`) — running ONNX models in Node.js or the browser, fully offline after the first model download. No API keys, no network dependency at inference time.

---

## When to Use Local Embeddings

| Scenario | Use Local | Use API |
|---|---|---|
| Developer tool, MCP server, CLI | ✅ Yes | No — adds network latency to every query |
| Privacy-sensitive data (code, PII) | ✅ Yes | Avoid sending to external service |
| High-volume offline indexing | ✅ Yes | Cost prohibitive |
| Production SaaS with high QPS | No | ✅ Yes — model hosting is complex to scale |
| Need latest frontier model quality | No | ✅ Yes — sentence transformers are 384d |

---

## Recommended Models

| Model | Dims | Size (fp32) | Size (q8) | Use Case |
|---|---|---|---|---|
| `Xenova/all-MiniLM-L6-v2` | 384 | ~90MB | ~23MB | General semantic similarity, fast |
| `Xenova/all-MiniLM-L12-v2` | 384 | ~130MB | ~35MB | Higher quality, slower |
| `Xenova/bge-small-en-v1.5` | 384 | ~130MB | ~35MB | Better retrieval benchmark scores |
| `Xenova/bge-base-en-v1.5` | 768 | ~420MB | ~115MB | High quality retrieval |

**Default:** `Xenova/all-MiniLM-L6-v2` with `dtype: "q8"` — best balance of size, speed, and accuracy for developer tools.

---

## Installation

```bash
npm install @huggingface/transformers
# Optional: pin ONNX Runtime for reproducibility
npm install onnxruntime-node
```

**package.json** — models download to a local cache:
```json
{
  "type": "module"
}
```

The library is ESM-only from v3.x. Use `.js` extensions in imports when `"type": "module"` is set.

---

## Basic Single Embedding

```typescript
import { pipeline } from "@huggingface/transformers";

// Pipeline is lazy-loaded on first call. Cache the instance.
let _pipe: Awaited<ReturnType<typeof pipeline>> | null = null;

async function getPipeline() {
  if (!_pipe) {
    _pipe = await pipeline("feature-extraction", "Xenova/all-MiniLM-L6-v2", {
      dtype: "q8",          // int8 quantized — 23MB vs 90MB fp32
      device: "cpu",        // explicit — avoids silent GPU detection issues
    });
  }
  return _pipe;
}

export async function embed(text: string): Promise<Float32Array | null> {
  try {
    const pipe = await getPipeline();
    const output = await pipe(text.slice(0, 512), {  // truncate to model max
      pooling: "mean",
      normalize: true,
    });
    // Single input → Tensor { data: Float32Array, dims: [1, 384] }
    return output.data.slice(0, 384) as Float32Array;
  } catch {
    return null;  // graceful fallback — caller decides how to handle
  }
}
```

---

## Batch Embedding — Critical API Shape

**The most common mistake:** assuming batch returns `Array<{data: Float32Array}>`.

It does NOT. Batch returns a **single flat Tensor** with `dims: [N, D]`.

```typescript
export async function embedBatch(
  texts: string[],
  dims = 384
): Promise<Array<Float32Array | null>> {
  const pipe = await getPipeline();
  const truncated = texts.map((t) => t.slice(0, 512));

  // Returns ONE Tensor: { data: Float32Array(N * D), dims: [N, D] }
  const tensor = await pipe(truncated, { pooling: "mean", normalize: true });

  // Slice into individual embeddings
  return Array.from({ length: texts.length }, (_, i) =>
    (tensor.data as Float32Array).slice(i * dims, (i + 1) * dims)
  );
}
```

**Why batch may be slower on Intel:** The int8 (`q8`) path benefits from AVX-512 VNNI (Ice Lake+) or ARM NEON. On Intel Broadwell (2015 MBP), ONNX WASM falls back to scalar int8, which is slower than the fp32 path. Batch also incurs variable-length padding overhead for short sequences.

**Recommendation:** Use `embedBatch()` for correctness and future-proofing, but don't expect dramatic speedups on pre-2019 Intel hardware.

---

## Model Cache Location

Models download on first use to:
- **Node.js:** `~/.cache/huggingface/hub/` (or `HF_HOME` env var)
- **Browser:** Cache API / IndexedDB

Force a custom cache path:
```typescript
import { env } from "@huggingface/transformers";
env.cacheDir = "/path/to/.model-cache";
```

Disable remote downloads (fully offline):
```typescript
env.allowRemoteModels = false;
env.allowLocalModels = true;
```

---

## Cosine Similarity

The `normalize: true` option (mean pooling + L2 normalize) produces unit vectors. Cosine similarity then equals dot product:

```typescript
function cosineSimilarity(a: Float32Array, b: Float32Array): number {
  let dot = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i]! * b[i]!;
  }
  return dot; // unit vectors: cosine = dot
}
```

---

## Lazy Load Pattern for MCP / CLI Tools

Model load adds ~400–500ms cold-start on first use. For tools where startup latency matters:

```typescript
// Only load when first embed call happens — not at process start
// This gives the MCP server time to register tools before the model loads
class EmbeddingService {
  private pipe: Awaited<ReturnType<typeof pipeline>> | null = null;
  private loading: Promise<void> | null = null;

  async warmUp(): Promise<void> {
    if (this.loading) return this.loading;
    this.loading = this.initPipeline();
    return this.loading;
  }

  private async initPipeline(): Promise<void> {
    this.pipe = await pipeline("feature-extraction", MODEL_ID, {
      dtype: "q8",
      device: "cpu",
    });
  }

  async embed(text: string): Promise<Float32Array | null> {
    if (!this.pipe) await this.warmUp();
    // ...
  }
}
```

---

## Performance Benchmarks (all-MiniLM-L6-v2, q8)

| Hardware | Cold Load | Single Embed | Batch (50 items) |
|---|---|---|---|
| Apple M-series | ~180ms | ~8ms | ~120ms |
| Intel Ice Lake (2020+) | ~380ms | ~15ms | ~200ms |
| Intel Broadwell (2015 MBP) | ~430ms | ~22ms | ~350ms+ |

**Indexing speed:** ~180–200 symbols/minute on 2015 MBP for a mixed TypeScript codebase.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `NOT NULL constraint` on embedding column | Batch returned undefined — wrong slicing | Use `tensor.data.slice(i * D, (i+1) * D)` |
| `Cannot find module` on `.js` imports | ESM requires explicit extensions | Add `.js` extension to all local imports |
| Model not found offline | Cache miss or wrong `cacheDir` | Set `env.cacheDir` explicitly |
| Slow first embed in production | Cold load | Call `warmUp()` after MCP server registers tools |
| Memory spike on large batches | ONNX allocates for padded batch | Cap batch size at 32–50 items max |

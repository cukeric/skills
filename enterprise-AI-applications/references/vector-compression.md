# Vector Compression Reference

Covers compact representations for dense embedding vectors — essential for local/offline vector search where storing raw `Float32Array` (1536 bytes for 384d) is prohibitive at scale.

---

## When to Compress Vectors

| Situation | Compress? | Why |
|---|---|---|
| > 5,000 vectors in SQLite/local store | ✅ Yes | Raw storage 7.5MB+ for 5k × 384d |
| MCP server / developer tool (offline) | ✅ Yes | Memory and SQLite BLOB size matters |
| Cloud vector DB (Pinecone, Weaviate, Qdrant) | No — they handle it | Provider compresses internally |
| < 500 vectors, latency not critical | No — YAGNI | Raw float32 is simpler, accurate |

---

## Compression Approaches by Complexity

### Level 1 — Scalar Quantization (simplest)

Convert float32 → int8 per dimension. Lossless enough for most RAG retrieval.

```typescript
// Encode: float32 → int8 (range [-1, 1] → [-127, 127])
function quantizeInt8(vector: Float32Array): Int8Array {
  const result = new Int8Array(vector.length);
  for (let i = 0; i < vector.length; i++) {
    result[i] = Math.round(Math.max(-1, Math.min(1, vector[i]!)) * 127);
  }
  return result;
}

// Decode: int8 → float32 approximation
function dequantizeInt8(quantized: Int8Array): Float32Array {
  const result = new Float32Array(quantized.length);
  for (let i = 0; i < quantized.length; i++) {
    result[i] = quantized[i]! / 127;
  }
  return result;
}

// Storage: 384 bytes (4x compression from 1536 bytes float32)
// Cosine similarity accuracy: ~0.998 for normalized vectors
```

**Use when:** You want a simple drop-in with minimal accuracy loss.

---

### Level 2 — Binary Quantization

Convert float32 → 1 bit per dimension (sign only). Extreme compression, works surprisingly well for cosine similarity on normalized vectors.

```typescript
// Encode: float32 → packed bits (1 bit per dimension)
function binaryQuantize(vector: Float32Array): Uint8Array {
  const byteLen = Math.ceil(vector.length / 8);
  const buf = new Uint8Array(byteLen);
  for (let i = 0; i < vector.length; i++) {
    if (vector[i]! > 0) {
      buf[Math.floor(i / 8)] |= (1 << (i % 8));
    }
  }
  return buf;
}

// Hamming distance ≈ cosine distance for normalized binary vectors
function hammingDistance(a: Uint8Array, b: Uint8Array): number {
  let dist = 0;
  for (let i = 0; i < a.length; i++) {
    let xor = a[i]! ^ b[i]!;
    while (xor) { dist += xor & 1; xor >>= 1; }
  }
  return dist;
}

// Storage: 48 bytes for 384d (32x compression)
// Cosine similarity accuracy: ~0.92–0.95 for normalized vectors
```

**Use when:** Extreme storage constraints, pre-filtering candidates before exact rerank.

---

### Level 3 — Product Quantization (PQ)

Partition vector into M sub-vectors, quantize each sub-vector to one of K centroids learned from training data. Standard approach in FAISS.

```typescript
// Conceptual interface — full PQ requires centroid training
interface PQCode {
  codes: Uint8Array;  // M bytes, one centroid index per sub-vector
  M: number;         // number of sub-vectors (e.g., 48 for 384d with M=48)
}

// Typical: M=48, K=256 → 48 bytes storage + centroid lookup table
// Cosine similarity accuracy: ~0.97+ after training
// Requires: offline training pass over representative vectors
```

**Use when:** You have training data and need high accuracy at extreme compression. Overkill for local tools.

---

### Level 4 — Recursive Polar Quantization (PolarQuant + QJL)

Two-stage algorithm for offline/no-training scenarios:

**Stage 1 — PolarQuant:** Recursively decomposes a vector into polar coordinates (magnitude + angles). Quantizes angles to N bins (4-bit = 16 bins). Pure-math, no training data needed.

**Stage 2 — QJL correction:** Encodes the residual error (original − PolarQuant reconstruction) using random Johnson-Lindenstrauss projections (1-bit sign). Corrects the approximation error from Stage 1.

```
Input vector (1536 bytes, float32, 384d)
    │
    ▼ L2-normalize
    ▼ PolarQuant encode
    │   → 384 angle codes × 4 bits = 192 bytes
    │   → 1 float64 (finalRadius) = 8 bytes
    ▼ Decode PolarQuant → reconstruction
    ▼ Compute residual = normalized - reconstruction
    ▼ QJL encode residual (64 projections × 1 bit = 8 bytes)
    │
    └── CompressedVector: 208 bytes total ≈ 7.4x compression
```

```typescript
// Approximate cosine similarity (no decompression needed)
function similarity(query: Float32Array, compressed: CompressedVector): number {
  const pqDot = polarQuantDotProduct(query, compressed);
  const qjlCorrection = qjlDotProductCorrection(query, compressed);
  return (pqDot + qjlCorrection) / compressed.finalRadius;
}
```

**Properties:**
- No training data required
- ≥0.95 cosine similarity (4-bit PolarQuant)
- Similarity computed without full decompression
- Pure TypeScript, zero native dependencies
- Scales linearly: ~310ms for 2,637-vector brute-force scan

**Use when:** Local MCP servers, developer tools, offline-first apps where training data isn't available.

---

## Compression Comparison

| Method | Storage (384d) | Compression | Cosine Accuracy | Training Required | Compute |
|---|---|---|---|---|---|
| Float32 (raw) | 1,536 bytes | 1× | 1.000 | No | None |
| Int8 scalar | 384 bytes | 4× | ~0.998 | No | Trivial |
| Binary (1-bit) | 48 bytes | 32× | ~0.93 | No | Very fast |
| PQ (M=48, K=256) | 48 bytes + centroids | 32× | ~0.97+ | Yes (~10k samples) | Fast scan |
| PolarQuant 3-bit | 145 bytes | ~10.6× | ~0.71 | No | Fast |
| PolarQuant 4-bit | 200 bytes | ~7.7× | ≥0.95 | No | Fast |
| TurboQuant (PQ+QJL) | ~208 bytes | ~7.4× | ≥0.95 | No | Fast |

---

## numAngles Calculation for PolarQuant

**Critical:** For d=384, the number of angle codes produced by recursive PolarQuant is **NOT d-1**.

The recursion halves the vector at each level: `ceil(size/2)` angles per level as size shrinks from d to 1.

```typescript
// For d=384: 192+96+48+24+12+6+3+2+1 = 384 (NOT 383)
function computeNumAngles(d: number): number {
  let total = 0;
  let size = d;
  while (size > 1) {
    total += Math.ceil(size / 2);
    size = Math.ceil(size / 2);
  }
  return total;
}
// d=384 → 384, d=128 → 128, d=256 → 256, d=100 → 100
// Only powers of 2 happen to equal d-1 at some levels — never rely on d-1
```

This off-by-one breaks deserialization from SQLite if `numAngles` is wrong — the angle buffer is the wrong size for the 4-bit decoder.

---

## Hybrid Search with Compressed Vectors

Combine keyword search (FTS5/BM25) with compressed semantic search using Reciprocal Rank Fusion (RRF):

```typescript
// RRF: scale-invariant, no score normalization needed
function rrfScore(keywordRank: number, semanticRank: number, k = 60): number {
  return 1 / (k + keywordRank) + 1 / (k + semanticRank);
}

// Usage: rank keyword results and semantic results separately, then fuse
const keywordResults = fts5Search(query, topK * 2);
const semanticResults = searchTopK(queryEmbedding, vectorIndex, topK * 2);

const merged = mergeRRF(keywordResults, semanticResults, topK);
```

**k=60** is the standard default — it balances precision vs. recall without tuning. Lower k (e.g. 20) favors top-ranked results more strongly.

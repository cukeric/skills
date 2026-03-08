# Multimodal Fallback Chains & AI Output Validation

## Problem

When building AI applications that process images (vision/multimodal), fallback providers must also support vision. A text-only fallback silently drops image context, producing lower-quality or inaccurate results without any error signal.

---

## Multimodal Fallback Architecture

### Principle: Capability Matching Across Tiers

Every fallback tier must support the same input modalities as the primary. If Tier 1 processes images + text, Tier 2 and Tier 3 must also accept images.

```
Tier 1 (Primary):  Gemini Flash      — text + vision (multimodal)
Tier 2 (Fallback): Groq Llama 4 Scout — text + vision (multimodal, up to 5 images)
Tier 3 (Fallback): OpenRouter free    — text + vision (multimodal, free tier)
                                        ↑ ALL tiers preserve image analysis capability
```

### Anti-Pattern: Text-Only Fallback

```
Tier 1: Gemini Flash (multimodal)  ✓
Tier 2: Groq LLaMA 3.3 (text-only) ✗ — silently drops photos
Tier 3: NVIDIA NIM (text-only)     ✗ — silently drops photos
```

This degrades quality without any error — the worst kind of failure.

---

## Provider Comparison: Multimodal Capabilities (2026)

| Provider | Model | Vision | Max Images | Free Tier | SDK |
|---|---|---|---|---|---|
| Google Gemini | gemini-3.1-flash-lite | Yes | Many | No | `@google/generative-ai` |
| Groq | llama-4-scout-17b-16e-instruct | Yes | 5 | Yes | `groq-sdk` (OpenAI-compat) |
| OpenRouter | gemma-3-27b-it:free | Yes | Varies | Yes (200 req/day) | Raw `fetch` (OpenAI-compat) |
| OpenRouter | qwen/qwen2.5-vl-72b | Yes | Varies | Yes | Raw `fetch` |
| Together AI | Llama-4-Maverick | Yes | Yes | $1 credit | OpenAI-compat |
| Fireworks AI | Llama 4 Scout | Yes | Yes | Limited | OpenAI-compat |
| Mistral | pixtral-12b-2409 | Yes | Arbitrary | Yes | `@mistralai/mistralai` |
| Anthropic | claude-haiku-4.5 | Yes | Many | No | `@anthropic-ai/sdk` |

### Image Format for OpenAI-Compatible APIs (Groq, OpenRouter, Together, Fireworks)

```typescript
// Vision messages use the image_url content part format
const messages = [
  { role: "system", content: systemPrompt },
  {
    role: "user",
    content: [
      // Images first
      ...photos.slice(0, 5).map((p) => ({
        type: "image_url" as const,
        image_url: { url: `data:${p.mimeType};base64,${p.data}` },
      })),
      // Text prompt last
      { type: "text" as const, text: prompt },
    ],
  },
]
```

---

## AI Output Validation with Zod

### Problem

AI models return JSON that may have wrong shapes, missing fields, or unexpected types. Using `JSON.parse()` + `as T` blindly trusts the AI, propagating malformed data through the application.

### Solution: Zod Schemas at AI Boundaries

```typescript
import { z } from "zod"

// Define expected shapes with sensible defaults
const SocialPostSchema = z.object({
  platform: z.string().transform((s) => s.toLowerCase()),
  content: z.string(),
  hashtags: z.array(z.string()).default([]),
})

const PhotoAnalysisSchema = z.object({
  roomType: z.string(),
  description: z.string(),
  features: z.array(z.string()).default([]),
  condition: z.enum(["excellent", "good", "fair", "needs-work"]).default("good"),
  style: z.string().default("Unknown"),
})

// Parse with schema validation
function parseAIJson<T>(raw: string, schema?: z.ZodType<T>): T {
  let cleaned = raw.trim()
  cleaned = cleaned.replace(/^```(?:json)?\s*\n?/i, "")
  cleaned = cleaned.replace(/\n?\s*```\s*$/i, "")
  const parsed = JSON.parse(cleaned.trim())
  return schema ? schema.parse(parsed) : (parsed as T)
}

// Usage — validates at runtime, throws ZodError on bad shape
const posts = z.array(SocialPostSchema).min(1).parse(parseAIJson(raw))
const analysis = parseAIJson(raw, PhotoAnalysisSchema)
```

### Key Principles

1. **Use `.default()` liberally** — AI may omit optional fields; defaults prevent crashes
2. **Use `.transform()` for normalization** — e.g., lowercase platform names
3. **Use `.enum()` for constrained values** — catches AI hallucinating invalid options
4. **Validate arrays with `.min(1)`** — catch empty responses early
5. **Keep schemas close to the AI call** — don't scatter validation across the codebase
6. **Wrap in try/catch with safe fallbacks** — if Zod rejects AI output, use a sensible default instead of crashing

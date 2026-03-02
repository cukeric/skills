# AI Video Generation Reference — Google Veo API

This reference covers integration with Google's Veo video generation API (Veo 2.0 and 3.1) via the `@google/genai` SDK. Patterns are derived from production debugging of real estate video generation but apply to any image-to-video workflow.

---

## Setup & Prerequisites

```bash
npm install @google/genai
```

Required environment:
- `GEMINI_API_KEY` — Google AI API key
- Google Cloud project with **Generative Language API** enabled
- **Billing enabled** on the Google Cloud project (Veo requires paid tier)

### Common Setup Failures

| Symptom | Cause | Fix |
|---|---|---|
| `403 PERMISSION_DENIED` on API call | Generative Language API not enabled | Enable at Google Cloud Console → APIs |
| `429 RESOURCE_EXHAUSTED` | Free tier quota or billing not enabled | Enable billing on Google Cloud project |
| `403` on video download URI | Download endpoint requires API key auth | Append `?key=API_KEY` to download URL |
| `enhancePrompt isn't supported` | Parameter not available on all models | Remove — only supported on specific model versions |

---

## Core Pattern: Image-to-Video Generation

```typescript
import { GoogleGenAI, VideoGenerationReferenceType } from "@google/genai"

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY! })

async function generateVideo(
  photo: { data: string; mimeType: string },
  prompt: string
): Promise<Buffer> {
  // 1. Start generation (returns an operation to poll)
  let operation = await ai.models.generateVideos({
    model: "veo-3.1-generate-preview",
    prompt,
    image: {
      imageBytes: photo.data,
      mimeType: photo.mimeType as "image/jpeg" | "image/png",
    },
    config: {
      aspectRatio: "9:16",        // or "16:9"
      numberOfVideos: 1,
      durationSeconds: 8,         // 4, 6, or 8
      negativePrompt: "...",      // What to exclude
      // enhancePrompt: false,    // NOT supported on veo-3.1-generate-preview
      // referenceImages: [],     // Cannot use with `image` parameter
    },
  })

  // 2. Poll until done (typically 30-120 seconds)
  const maxAttempts = 60
  let attempts = 0
  while (!operation.done) {
    if (attempts >= maxAttempts) {
      throw new Error("Video generation timed out")
    }
    await new Promise((r) => setTimeout(r, 10_000))
    operation = await ai.operations.getVideosOperation({ operation })
    attempts++
  }

  // 3. Download the result
  const video = operation.response?.generatedVideos?.[0]
  if (!video?.video) throw new Error("No video generated")

  // CRITICAL: Download URI requires API key authentication
  if (video.video.uri) {
    const downloadUrl = new URL(video.video.uri)
    downloadUrl.searchParams.set("key", process.env.GEMINI_API_KEY!)
    const response = await fetch(downloadUrl.toString())
    if (!response.ok) throw new Error(`Download failed: HTTP ${response.status}`)
    return Buffer.from(await response.arrayBuffer())
  }

  // Fallback: Some responses include inline base64 data
  if (video.video.videoBytes) {
    return Buffer.from(video.video.videoBytes, "base64")
  }

  throw new Error("No video data in response")
}
```

---

## Accuracy Guardrails for Image-to-Video

When generating video from a reference photo, the AI model will embellish and "upgrade" the source material unless explicitly constrained.

### The Problem

Without guardrails, Veo will:
- Replace a modest kitchen with a luxury gourmet kitchen
- Add marble countertops, premium appliances to dated interiors
- Generate a completely different exterior than the reference photo
- Apply dramatic "golden hour" lighting to daytime photos
- Add architectural features that don't exist

### The Solution: Constrained Prompts + Negative Prompts

```typescript
// Prompt template emphasizing fidelity
const prompt = `Slow gentle camera pan of the EXACT property shown in the reference image.

The video MUST be a faithful representation of the reference photo:
- Match the architecture, materials, colors, condition, and style EXACTLY.
- Do NOT upgrade, renovate, modernize, or embellish anything.
- If showing areas not in the photo, match the same style, era, and condition.
- Minimal camera movement — slow steady pan only.
- Do NOT show any people, faces, or human figures.
- Vertical 9:16 aspect ratio.`

// Negative prompt blocks common hallucinations
const negativePrompt = "luxury upgrades, marble countertops, premium appliances, " +
  "fantasy architecture, unrealistic lighting, dramatic camera movements, " +
  "people, faces, human figures, different house, different building, " +
  "modern renovation of old property, aspirational imagery"
```

### Key Parameters

| Parameter | Supported On | Purpose |
|---|---|---|
| `negativePrompt` | veo-3.1, veo-2.0 | Explicitly block unwanted content |
| `enhancePrompt` | veo-2.0 only | Prevent prompt rewriting (NOT on 3.1) |
| `referenceImages` (ASSET) | veo-3.1, veo-2.0 | Preserve subject appearance (cannot use with `image`) |
| `referenceImages` (STYLE) | veo-2.0 only | Apply artistic style |

---

## Video Serving: Cross-Browser Compatibility

Serving video via an API endpoint requires HTTP Range request support. Without it, **Brave, Safari, and Edge will refuse to play the video** while Chrome works fine.

### Required Headers

```typescript
// Full response
return new Response(fileBuffer, {
  headers: {
    "Content-Type": "video/mp4",
    "Content-Length": String(fileSize),
    "Accept-Ranges": "bytes",              // CRITICAL for Safari/Brave/Edge
    "Content-Disposition": `inline; filename="${filename}"`,
    "Cache-Control": "private, max-age=3600",
  },
})
```

### Range Request Handling

```typescript
const rangeHeader = request.headers.get("range")
if (rangeHeader) {
  const match = rangeHeader.match(/bytes=(\d+)-(\d*)/)
  if (match) {
    const start = parseInt(match[1], 10)
    const end = match[2] ? parseInt(match[2], 10) : fileSize - 1
    const chunkSize = end - start + 1

    const fileHandle = await fs.open(filePath, "r")
    const buffer = Buffer.alloc(chunkSize)
    await fileHandle.read(buffer, 0, chunkSize, start)
    await fileHandle.close()

    return new Response(buffer, {
      status: 206,
      headers: {
        "Content-Type": "video/mp4",
        "Content-Length": String(chunkSize),
        "Content-Range": `bytes ${start}-${end}/${fileSize}`,
        "Accept-Ranges": "bytes",
      },
    })
  }
}
```

### HTML Video Element

```html
<!-- Use <source> with type for better browser support -->
<video controls playsInline preload="metadata">
  <source src="/api/videos/{id}" type="video/mp4" />
</video>
```

**Anti-pattern:** `<video src="...">` without `type` attribute — some browsers won't attempt playback.

---

## Async Generation + Status Polling (Frontend)

Video generation takes 1-3 minutes. Use async pattern with polling backoff:

```typescript
// Backend: Return immediately with video ID
const videoRecord = await prisma.video.create({ data: { status: "processing" } })
// Fire async generation (don't await)
;(async () => { /* generate + update record */ })()
return NextResponse.json({ videoId: videoRecord.id })

// Frontend: Poll with backoff (not setInterval)
useEffect(() => {
  let timeoutId: ReturnType<typeof setTimeout> | null = null
  let attempts = 0
  let cancelled = false

  const poll = async () => {
    if (cancelled) return
    const res = await fetch(`/api/videos/${videoId}/status`)
    const data = await res.json()
    if (data.status === "ready" || data.status === "failed") return
    // Backoff: 5s for first 10, then 8s
    const delay = ++attempts <= 10 ? 5000 : 8000
    timeoutId = setTimeout(poll, delay)
  }
  poll()
  return () => { cancelled = true; if (timeoutId) clearTimeout(timeoutId) }
}, [videoId])
```

**Anti-pattern:** `setInterval(poll, 3000)` — burns CPU/network for a 1-3 minute operation. Use `setTimeout` with backoff.

**Anti-pattern:** Heavy shimmer/animation on large skeleton elements during polling — causes browser jank. Use lightweight CSS-only indicators.

---

## React State Hydration for Persisted Video

When video state lives in both React state (runtime) and DB (persisted), you must hydrate on mount:

```typescript
// videoCardState only populated during in-session generation
// On page refresh, it resets to {} — video "disappears"

// Fix: Hydrate from persisted data
useEffect(() => {
  if (!detail?.videoId || !detail.result) return
  const posts = normaliseSocialPosts(detail.result)
  const tiktokIdx = posts.findIndex((p) => p.platform.toLowerCase() === "tiktok")
  if (tiktokIdx === -1) return
  setVideoCardState((prev) => {
    if (prev[tiktokIdx]?.videoId) return prev // Don't overwrite runtime state
    return { ...prev, [tiktokIdx]: { videoId: detail.videoId, ... } }
  })
}, [detail])
```

---

## Troubleshooting

| Issue | Cause | Solution |
|---|---|---|
| Video plays in Chrome but not Brave/Safari | Missing `Accept-Ranges` header and Range request support | Add 206 Partial Content handling |
| Video disappears after page refresh | React state not hydrated from persisted DB data | Add useEffect to sync on mount |
| Generated video looks nothing like the photo | Veo embellishes by default | Use constrained prompt + negativePrompt |
| Download returns 403 | Veo download URI needs API key | Append `key` query parameter |
| `enhancePrompt` causes 400 error | Not supported on veo-3.1-generate-preview | Remove the parameter |
| Browser becomes choppy during generation | Heavy animations (shimmer, motion.div) on large elements + aggressive polling | Lightweight CSS indicators + polling backoff |
| FIFO token deduction bypassed | Using raw Prisma updates instead of `deductTokens()` | Always use the FIFO batch functions |

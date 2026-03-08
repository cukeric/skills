# AI Video Generation Reference — Google Veo API

This reference covers integration with Google's Veo video generation API (Veo 2.0 and 3.1) via both the `@google/genai` SDK and the direct REST API (`predictLongRunning`). Patterns are derived from production real estate video generation but apply to any image-to-video workflow.

---

## Setup & Prerequisites

### Using the SDK
```bash
npm install @google/genai
```

### Using the Direct REST API (No SDK)
No additional packages needed — uses native `fetch`. This is the recommended approach for server-side generation to avoid SDK version churn.

Required environment:
- `GEMINI_API_KEY` — Google AI API key
- Google Cloud project with **Generative Language API** enabled
- **Billing enabled** on the Google Cloud project (Veo requires paid tier)

### Pricing (as of 2026-03)

| Mode | Resolution | Cost/second | 8s clip | 15s (2 clips) | 30s (4 clips) |
|---|---|---|---|---|---|
| **Fast** | 720p | $0.15 | $1.20 | $2.40 | $4.80 |
| **Standard** | 720p/1080p | $0.40 | $3.20 | $6.40 | $12.80 |

**Important:** Veo 3.1 generates clips of 4, 6, or 8 seconds maximum — there is no native 15s or 30s support. Longer videos require multi-clip generation + FFmpeg stitching.

### Common Setup Failures

| Symptom | Cause | Fix |
|---|---|---|
| `403 PERMISSION_DENIED` on API call | Generative Language API not enabled | Enable at Google Cloud Console → APIs |
| `429 RESOURCE_EXHAUSTED` | Free tier quota or billing not enabled | Enable billing on Google Cloud project |
| `403` on video download URI | Download endpoint requires API key auth | Pass `x-goog-api-key` header on download |
| `enhancePrompt isn't supported` | Parameter not available on all models | Remove — only supported on specific model versions |

---

## Core Pattern A: Direct REST API (Recommended for Server-Side)

```typescript
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || ""
const VEO_MODEL = "veo-3.1-generate-preview"
const VEO_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

async function generateClipVeo31(
  photo: { data: string; mimeType: string },
  prompt: string
): Promise<Buffer> {
  // 1. Submit long-running operation
  const generateRes = await fetch(
    `${VEO_BASE_URL}/models/${VEO_MODEL}:predictLongRunning`,
    {
      method: "POST",
      headers: {
        "x-goog-api-key": GEMINI_API_KEY,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        instances: [{
          prompt,
          image: {
            inlineData: {
              mimeType: photo.mimeType,
              data: photo.data,  // base64
            },
          },
        }],
        parameters: {
          aspectRatio: "9:16",
          durationSeconds: "8",
          personGeneration: "dont_allow",
          resolution: "720p",
        },
      }),
    }
  )

  if (!generateRes.ok) {
    const errBody = await generateRes.text().catch(() => "(unreadable)")
    if (errBody.includes("quota") || errBody.includes("RESOURCE_EXHAUSTED")) {
      throw new Error("Video generation quota exceeded.")
    }
    throw new Error(`Veo 3.1 generate failed: HTTP ${generateRes.status}`)
  }

  const generateData = await generateRes.json()
  const operationName = generateData.name
  if (!operationName) throw new Error("No operation name returned")

  // 2. Poll for completion (max 10 minutes)
  const maxAttempts = 60
  let attempts = 0
  while (attempts < maxAttempts) {
    await new Promise((r) => setTimeout(r, 10000))
    attempts++

    const statusRes = await fetch(`${VEO_BASE_URL}/${operationName}`, {
      headers: { "x-goog-api-key": GEMINI_API_KEY },
    })

    if (!statusRes.ok) continue  // transient failure, retry

    const statusData = await statusRes.json()

    if (statusData.done === true) {
      if (statusData.error) {
        throw new Error(`Generation failed: ${statusData.error.message}`)
      }

      const videoUri = statusData.response
        ?.generateVideoResponse?.generatedSamples?.[0]?.video?.uri
      if (!videoUri) throw new Error("No video URI in response")

      // 3. Download — API key as header (not query param)
      const videoRes = await fetch(videoUri, {
        headers: { "x-goog-api-key": GEMINI_API_KEY },
      })
      if (!videoRes.ok) throw new Error(`Download failed: HTTP ${videoRes.status}`)

      return Buffer.from(await videoRes.arrayBuffer())
    }
  }

  throw new Error("Video generation timed out after 10 minutes")
}
```

### Key Differences from SDK Pattern
- No `@google/genai` dependency — fewer version-related breakages
- Uses `x-goog-api-key` header instead of query param `?key=` for downloads
- Operation name is a string path (e.g., `operations/xxx`), polled via GET
- Response shape: `statusData.response.generateVideoResponse.generatedSamples[0].video.uri`

---

## Core Pattern B: SDK Pattern

```typescript
import { GoogleGenAI } from "@google/genai"

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY! })

async function generateVideo(
  photo: { data: string; mimeType: string },
  prompt: string
): Promise<Buffer> {
  let operation = await ai.models.generateVideos({
    model: "veo-3.1-generate-preview",
    prompt,
    image: {
      imageBytes: photo.data,
      mimeType: photo.mimeType as "image/jpeg" | "image/png",
    },
    config: {
      aspectRatio: "9:16",
      numberOfVideos: 1,
      durationSeconds: 8,
      negativePrompt: "...",
    },
  })

  const maxAttempts = 60
  let attempts = 0
  while (!operation.done) {
    if (attempts >= maxAttempts) throw new Error("Timed out")
    await new Promise((r) => setTimeout(r, 10_000))
    operation = await ai.operations.getVideosOperation({ operation })
    attempts++
  }

  const video = operation.response?.generatedVideos?.[0]
  if (!video?.video) throw new Error("No video generated")

  if (video.video.uri) {
    const downloadUrl = new URL(video.video.uri)
    downloadUrl.searchParams.set("key", process.env.GEMINI_API_KEY!)
    const response = await fetch(downloadUrl.toString())
    if (!response.ok) throw new Error(`Download failed: HTTP ${response.status}`)
    return Buffer.from(await response.arrayBuffer())
  }

  if (video.video.videoBytes) {
    return Buffer.from(video.video.videoBytes, "base64")
  }

  throw new Error("No video data in response")
}
```

---

## Multi-Clip Video Stitching with FFmpeg Crossfade

Veo 3.1 generates max 8s clips. For 15s and 30s videos, generate multiple clips and stitch with smooth crossfade transitions.

### Clip Strategy

| Target Duration | Clips Needed | Effective Duration (with 0.5s crossfade) |
|---|---|---|
| 8s | 1 clip | 8s (no stitching) |
| 15s | 2 clips | ~15.5s |
| 30s | 4 clips | ~30.5s |

### Prompt Angles for Multi-Clip Videos

Each clip gets a different "camera angle" prompt to create visual variety:

```typescript
const CLIP_ANGLES: Record<number, string[]> = {
  1: ["the property exactly as shown in the reference photo"],
  2: [
    "exterior as shown in the reference photo",
    "interior staying true to the style and condition visible in the photo",
  ],
  4: [
    "exterior exactly matching the reference photo",
    "interior living areas consistent with the home style shown",
    "kitchen and dining areas matching the property's style and era",
    "closing wide shot of the property exterior as shown in the reference",
  ],
}
```

### FFmpeg Crossfade Filter Graph

```typescript
import { execFile } from "child_process"
import { promisify } from "util"
const execFileAsync = promisify(execFile)

const CROSSFADE_DURATION = 0.5 // seconds of overlap

async function concatenateClipsWithCrossfade(
  clipPaths: string[],
  outputPath: string
): Promise<void> {
  if (clipPaths.length < 2) {
    await fs.copyFile(clipPaths[0], outputPath)
    return
  }

  // Build chained xfade (video) + acrossfade (audio) filter graph
  const filterParts: string[] = []
  let lastVideoLabel = "[0:v]"
  let lastAudioLabel = "[0:a]"

  for (let i = 1; i < clipPaths.length; i++) {
    const offset = i * 8 - i * CROSSFADE_DURATION
    const outVideoLabel = i < clipPaths.length - 1 ? `[v${i}]` : "[vout]"
    const outAudioLabel = i < clipPaths.length - 1 ? `[a${i}]` : "[aout]"

    filterParts.push(
      `${lastVideoLabel}[${i}:v]xfade=transition=fade:duration=${CROSSFADE_DURATION}:offset=${offset.toFixed(1)}${outVideoLabel}`
    )
    filterParts.push(
      `${lastAudioLabel}[${i}:a]acrossfade=d=${CROSSFADE_DURATION}:c1=tri:c2=tri${outAudioLabel}`
    )

    lastVideoLabel = outVideoLabel
    lastAudioLabel = outAudioLabel
  }

  const inputArgs: string[] = []
  for (const clip of clipPaths) {
    inputArgs.push("-i", clip)
  }

  await execFileAsync("ffmpeg", [
    ...inputArgs,
    "-filter_complex", filterParts.join(";"),
    "-map", "[vout]",
    "-map", "[aout]",
    "-c:v", "libx264",
    "-preset", "fast",
    "-crf", "23",
    "-c:a", "aac",
    "-b:a", "128k",
    "-movflags", "+faststart",  // enables progressive download
    "-y",
    outputPath,
  ], { timeout: 120000 })
}
```

### Key FFmpeg Concepts

- **`xfade`**: Video crossfade filter. `transition=fade` is smoothest. `offset` is when the transition starts (in seconds from the beginning of the output).
- **`acrossfade`**: Audio crossfade. `c1=tri:c2=tri` uses triangular fade curves for natural-sounding transitions.
- **`-movflags +faststart`**: Moves MP4 metadata to the beginning of the file, enabling progressive download/streaming.
- **Filter graph chaining**: For N clips, chain N-1 xfade filters. Each filter's output label feeds the next filter's input.
- **Timeout**: Set `execFile` timeout to 120s — crossfade encoding of 4 clips takes 30-60s on typical VPS hardware.

### EXIF Metadata Stripping (Privacy)

Always strip EXIF/GPS data before sending photos to any external API:

```typescript
import sharp from "sharp"

async function stripExifMetadata(
  photo: { data: string; mimeType: string }
): Promise<{ data: string; mimeType: string }> {
  const inputBuffer = Buffer.from(photo.data, "base64")
  const strippedBuffer = await sharp(inputBuffer)
    .rotate()                          // auto-orient based on EXIF rotation
    .withMetadata({ exif: undefined }) // strip all EXIF including GPS
    .toBuffer()
  return {
    data: strippedBuffer.toString("base64"),
    mimeType: photo.mimeType,
  }
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
const prompt = `Slow gentle camera pan of the EXACT property shown in the reference image.

The video MUST be a faithful representation of the reference photo:
- Match the architecture, materials, colors, condition, and style EXACTLY.
- Do NOT upgrade, renovate, modernize, or embellish anything.
- If showing areas not in the photo, match the same style, era, and condition.
- Minimal camera movement — slow steady pan only.
- Do NOT show any people, faces, or human figures.
- Vertical 9:16 aspect ratio.`

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
| `personGeneration` | veo-3.1 | `"dont_allow"` blocks person generation at API level |
| `referenceImages` (ASSET) | veo-3.1, veo-2.0 | Preserve subject appearance (cannot use with `image`) |
| `referenceImages` (STYLE) | veo-2.0 only | Apply artistic style |

---

## Video Serving: Cross-Browser Compatibility

Serving video via an API endpoint requires HTTP Range request support. Without it, **Brave, Safari, and Edge will refuse to play the video** while Chrome works fine.

### Required Headers

```typescript
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
useEffect(() => {
  if (!detail?.videoId || !detail.result) return
  const posts = normaliseSocialPosts(detail.result)
  const tiktokIdx = posts.findIndex((p) => p.platform.toLowerCase() === "tiktok")
  if (tiktokIdx === -1) return
  setVideoCardState((prev) => {
    if (prev[tiktokIdx]?.videoId) return prev
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
| Download returns 403 | Veo download URI needs API key | Pass `x-goog-api-key` header on download request |
| `enhancePrompt` causes 400 error | Not supported on veo-3.1-generate-preview | Remove the parameter |
| Browser becomes choppy during generation | Heavy animations on large elements + aggressive polling | Lightweight CSS indicators + polling backoff |
| FIFO token deduction bypassed | Using raw Prisma updates instead of `deductTokens()` | Always use the FIFO batch functions |
| Hard cuts between clips look jarring | Using ffmpeg concat demuxer without transitions | Use `xfade` + `acrossfade` filter graph |
| FFmpeg crossfade timeout | Processing 4+ clips on low-spec hardware | Increase `execFile` timeout, use `-preset ultrafast` |
| Unexpected Veo cost ($0.40/s vs $0.15/s) | Using standard mode instead of fast mode | Ensure `resolution: "720p"` for fast pricing tier |

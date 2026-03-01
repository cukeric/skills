# Multimodal AI Pipelines Reference

## Capability Matrix

| Modality | Claude | GPT-4o | Gemini | Local (Ollama) |
|---|---|---|---|---|
| **Image input** | ✅ (vision) | ✅ (vision) | ✅ (vision) | LLaVA, Llama 3.2 Vision |
| **PDF input** | ✅ (native) | Via parsing | ✅ (native) | Via parsing |
| **Audio input** | ❌ (parse first) | ✅ (native) | ✅ (native) | Whisper (local) |
| **Video input** | ❌ | ❌ | ✅ (native) | ❌ |
| **Image generation** | ❌ | DALL-E 3 | Imagen | Stable Diffusion |
| **Audio generation** | ❌ | TTS API | ❌ | Coqui TTS |

---

## Vision: Image Analysis

```typescript
// src/ai/patterns/vision.ts
import type { LLMProvider, ContentBlock } from '../clients/llm-client'

export interface ImageAnalysisResult {
  description: string
  extractedText?: string
  structuredData?: Record<string, unknown>
  usage: { inputTokens: number; outputTokens: number }
}

export async function analyzeImage(
  llmClient: LLMProvider,
  imageBuffer: Buffer,
  mimeType: string,
  prompt: string,
  options?: { structured?: boolean; model?: string },
): Promise<ImageAnalysisResult> {
  const base64 = imageBuffer.toString('base64')

  const systemPrompt = options?.structured
    ? 'Analyze the image and return your findings as a JSON object. Include all relevant details.'
    : 'Analyze the image thoroughly and provide a detailed description.'

  const response = await llmClient.complete({
    systemPrompt,
    messages: [{
      role: 'user',
      content: [
        { type: 'image', source: { type: 'base64', mediaType: mimeType, data: base64 } },
        { type: 'text', text: prompt },
      ],
    }],
    model: options?.model,
    maxTokens: 2048,
  })

  return {
    description: response.content,
    structuredData: options?.structured ? tryParseJSON(response.content) : undefined,
    usage: response.usage,
  }
}

// Batch image analysis (multiple images in one request)
export async function analyzeMultipleImages(
  llmClient: LLMProvider,
  images: { buffer: Buffer; mimeType: string; label?: string }[],
  prompt: string,
): Promise<ImageAnalysisResult> {
  const content: ContentBlock[] = []

  for (const img of images) {
    if (img.label) content.push({ type: 'text', text: `Image: ${img.label}` })
    content.push({ type: 'image', source: { type: 'base64', mediaType: img.mimeType, data: img.buffer.toString('base64') } })
  }
  content.push({ type: 'text', text: prompt })

  const response = await llmClient.complete({
    messages: [{ role: 'user', content }],
    maxTokens: 4096,
  })

  return { description: response.content, usage: response.usage }
}

function tryParseJSON(text: string): Record<string, unknown> | undefined {
  try {
    const cleaned = text.replace(/```json\n?|\n?```/g, '').trim()
    return JSON.parse(cleaned)
  } catch { return undefined }
}
```

---

## OCR: Text Extraction from Images

```typescript
// Use LLM vision for high-quality OCR
export async function extractTextFromImage(
  llmClient: LLMProvider,
  imageBuffer: Buffer,
  mimeType: string,
): Promise<string> {
  const result = await analyzeImage(llmClient, imageBuffer, mimeType,
    'Extract ALL text from this image exactly as written. Preserve formatting, line breaks, and structure. If there are tables, format them clearly. Output only the extracted text.')
  return result.description
}

// Extract structured data from receipts, invoices, business cards
export async function extractStructuredData(
  llmClient: LLMProvider,
  imageBuffer: Buffer,
  mimeType: string,
  schema: string,  // Description of expected structure
): Promise<Record<string, unknown>> {
  const result = await analyzeImage(llmClient, imageBuffer, mimeType,
    `Extract data from this image and return it as JSON matching this schema: ${schema}. Return ONLY valid JSON.`,
    { structured: true })
  return result.structuredData || {}
}

// Example: Invoice extraction
// const invoice = await extractStructuredData(llmClient, buffer, 'image/png',
//   '{ vendor: string, date: string, total: number, items: { description: string, quantity: number, price: number }[], invoiceNumber: string }')
```

---

## PDF Processing Pipeline

```typescript
// src/ai/patterns/pdf-pipeline.ts

export interface PDFAnalysisOptions {
  mode: 'summarize' | 'extract' | 'qa' | 'full'
  question?: string          // For 'qa' mode
  extractSchema?: string     // For 'extract' mode
}

export async function processPDF(
  llmClient: LLMProvider,
  pdfBuffer: Buffer,
  options: PDFAnalysisOptions,
): Promise<{ result: string; pages: number; usage: LLMResponse['usage'] }> {

  // Option A: Native PDF support (Claude, Gemini)
  // Send PDF directly as a document
  const base64 = pdfBuffer.toString('base64')

  const promptMap: Record<string, string> = {
    summarize: 'Provide a comprehensive summary of this document. Include key points, conclusions, and any important data.',
    extract: `Extract data from this document as JSON matching this schema: ${options.extractSchema}`,
    qa: `Based on this document, answer the following question: ${options.question}`,
    full: 'Analyze this document thoroughly. Provide: 1) Summary, 2) Key findings, 3) Important data points, 4) Any concerns or gaps.',
  }

  const response = await llmClient.complete({
    messages: [{
      role: 'user',
      content: [
        { type: 'document', source: { type: 'base64', mediaType: 'application/pdf', data: base64 } },
        { type: 'text', text: promptMap[options.mode] },
      ],
    }],
    maxTokens: 4096,
  })

  return { result: response.content, pages: 0, usage: response.usage }
}

// For providers without native PDF: parse first, then analyze
export async function processPDFWithParsing(
  llmClient: LLMProvider,
  pdfBuffer: Buffer,
  options: PDFAnalysisOptions,
) {
  // Parse PDF to text (see enterprise-ai-foundations: embeddings-chunking.md)
  const { text, pages } = await parsePDF(pdfBuffer)

  // If text fits in context window, send directly
  const approxTokens = Math.ceil(text.length / 4)
  if (approxTokens < 100000) {
    const response = await llmClient.complete({
      messages: [{ role: 'user', content: `Document content:\n\n${text}\n\n---\n\n${promptMap[options.mode]}` }],
      maxTokens: 4096,
    })
    return { result: response.content, pages, usage: response.usage }
  }

  // For large documents: chunk and use RAG approach
  // (Use the ingestion pipeline from enterprise-ai-foundations)
  throw new Error('Document too large for single-pass analysis. Use RAG pipeline for ingestion and querying.')
}
```

---

## Audio Processing

```typescript
// src/ai/patterns/audio.ts

// Transcription using OpenAI Whisper API
export async function transcribeAudio(
  audioBuffer: Buffer,
  mimeType: string,
  options?: { language?: string; prompt?: string },
): Promise<{ text: string; segments?: { start: number; end: number; text: string }[] }> {
  const formData = new FormData()
  formData.append('file', new Blob([audioBuffer], { type: mimeType }), 'audio.mp3')
  formData.append('model', 'whisper-1')
  formData.append('response_format', 'verbose_json')
  if (options?.language) formData.append('language', options.language)
  if (options?.prompt) formData.append('prompt', options.prompt)

  const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${env.OPENAI_API_KEY}` },
    body: formData,
  })

  const result = await response.json()
  return {
    text: result.text,
    segments: result.segments?.map((s: any) => ({ start: s.start, end: s.end, text: s.text })),
  }
}

// Local transcription with Whisper (via Ollama or whisper.cpp)
export async function transcribeLocal(audioBuffer: Buffer): Promise<string> {
  // Using whisper.cpp server (self-hosted)
  const formData = new FormData()
  formData.append('file', new Blob([audioBuffer]), 'audio.wav')
  const response = await fetch('http://localhost:8080/inference', { method: 'POST', body: formData })
  const result = await response.json()
  return result.text
}

// Text-to-Speech
export async function textToSpeech(
  text: string,
  options?: { voice?: string; speed?: number },
): Promise<Buffer> {
  const response = await fetch('https://api.openai.com/v1/audio/speech', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'tts-1',
      input: text,
      voice: options?.voice || 'alloy',
      speed: options?.speed || 1.0,
    }),
  })
  return Buffer.from(await response.arrayBuffer())
}
```

---

## Multi-Format Document Q&A

```typescript
// Unified endpoint: upload any file, ask questions about it

export async function documentQA(
  llmClient: LLMProvider,
  file: { buffer: Buffer; mimeType: string; filename: string },
  question: string,
): Promise<{ answer: string; usage: LLMResponse['usage'] }> {

  // Route based on file type
  if (file.mimeType === 'application/pdf') {
    const result = await processPDF(llmClient, file.buffer, { mode: 'qa', question })
    return { answer: result.result, usage: result.usage }
  }

  if (file.mimeType.startsWith('image/')) {
    const result = await analyzeImage(llmClient, file.buffer, file.mimeType, question)
    return { answer: result.description, usage: result.usage }
  }

  if (file.mimeType.startsWith('audio/')) {
    const transcript = await transcribeAudio(file.buffer, file.mimeType)
    const response = await llmClient.complete({
      messages: [{ role: 'user', content: `Audio transcript:\n\n${transcript.text}\n\n---\n\nQuestion: ${question}` }],
    })
    return { answer: response.content, usage: response.usage }
  }

  // Text-based files (DOCX, HTML, MD, TXT)
  const text = await parseDocument(file.buffer, file.mimeType)
  const response = await llmClient.complete({
    messages: [{ role: 'user', content: `Document content:\n\n${text}\n\n---\n\nQuestion: ${question}` }],
  })
  return { answer: response.content, usage: response.usage }
}
```

---

## Checklist

- [ ] Image analysis: single and multi-image support with vision models
- [ ] OCR: text extraction from images using LLM vision
- [ ] Structured extraction: receipts, invoices, forms → JSON
- [ ] PDF processing: native (Claude/Gemini) and parsed (fallback) paths
- [ ] Audio transcription: Whisper API or local whisper.cpp
- [ ] Text-to-speech: audio generation from LLM responses
- [ ] Multi-format Q&A: unified endpoint for any file type
- [ ] File size limits enforced before processing
- [ ] Large documents routed to RAG pipeline (not single-pass)

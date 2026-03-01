# ETL Pipelines Reference

## Pipeline Architecture

```
┌────────────┐     ┌──────────────┐     ┌────────────┐
│   Extract   │────▶│  Transform   │────▶│    Load     │
│  (Sources)  │     │  (Process)   │     │ (Destination)│
└────────────┘     └──────────────┘     └────────────┘
  CSV, API,          Validate,           Database,
  Database,          Clean, Map,         Warehouse,
  Webhook            Aggregate           Search Index
```

## Node.js ETL with Streams

```typescript
import { Transform, pipeline } from 'stream'
import { createReadStream } from 'fs'
import csv from 'fast-csv'

// Extract → Transform → Load pipeline
async function importProducts(filePath: string) {
  const readStream = createReadStream(filePath)
  const csvParser = csv.parse({ headers: true, trim: true })

  const validator = new Transform({
    objectMode: true,
    transform(row, encoding, callback) {
      try {
        const validated = ProductSchema.parse({
          name: row.name,
          price: parseFloat(row.price),
          category: row.category,
          sku: row.sku,
        })
        callback(null, validated)
      } catch (error) {
        logger.warn({ row, error }, 'Validation failed, skipping row')
        callback() // Skip invalid rows
      }
    },
  })

  const batchLoader = new BatchTransform(100, async (batch) => {
    await db.product.createMany({ data: batch, skipDuplicates: true })
  })

  await pipeline(readStream, csvParser, validator, batchLoader)
}

// Batch transform helper
class BatchTransform extends Transform {
  private batch: unknown[] = []
  constructor(
    private batchSize: number,
    private loadFn: (batch: unknown[]) => Promise<void>
  ) {
    super({ objectMode: true })
  }

  async _transform(chunk: unknown, _enc: string, cb: Function) {
    this.batch.push(chunk)
    if (this.batch.length >= this.batchSize) {
      await this.loadFn(this.batch)
      this.batch = []
    }
    cb()
  }

  async _flush(cb: Function) {
    if (this.batch.length > 0) await this.loadFn(this.batch)
    cb()
  }
}
```

## Scheduling

```typescript
// BullMQ scheduled ETL
await etlQueue.add('import-daily-sales', {}, {
  repeat: { pattern: '0 1 * * *' }, // Daily at 1 AM
  jobId: 'daily-sales-import',
})

await etlQueue.add('sync-crm-contacts', {}, {
  repeat: { pattern: '*/15 * * * *' }, // Every 15 minutes
  jobId: 'crm-sync',
})
```

## Error Handling

```typescript
// Track failed rows for retry/investigation
interface ETLResult {
  processed: number
  succeeded: number
  failed: number
  errors: Array<{ row: number; error: string; data: unknown }>
}

async function runETL(source: string): Promise<ETLResult> {
  const result: ETLResult = { processed: 0, succeeded: 0, failed: 0, errors: [] }

  for await (const row of extractRows(source)) {
    result.processed++
    try {
      const transformed = transform(row)
      await load(transformed)
      result.succeeded++
    } catch (error) {
      result.failed++
      result.errors.push({ row: result.processed, error: error.message, data: row })
    }
  }

  if (result.failed > 0) {
    logger.warn({ result }, 'ETL completed with errors')
    await saveFailedRows(result.errors) // For retry
  }

  return result
}
```

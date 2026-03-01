# Data Exports Reference

## CSV Export

```typescript
import { stringify } from 'csv-stringify'
import { Writable } from 'stream'

async function exportToCSV(query: any, reply: FastifyReply) {
  reply.header('Content-Type', 'text/csv')
  reply.header('Content-Disposition', 'attachment; filename="export.csv"')

  const stringifier = stringify({
    header: true,
    columns: ['id', 'name', 'email', 'createdAt'],
  })

  stringifier.pipe(reply.raw)

  const cursor = db.user.findManyCursor(query)
  for await (const user of cursor) {
    stringifier.write([user.id, user.name, user.email, user.createdAt.toISOString()])
  }
  stringifier.end()
}
```

## Excel Export

```typescript
import ExcelJS from 'exceljs'

async function exportToExcel(data: OrderData[]): Promise<Buffer> {
  const workbook = new ExcelJS.Workbook()
  const sheet = workbook.addWorksheet('Orders')

  // Headers with styling
  sheet.columns = [
    { header: 'Order ID', key: 'id', width: 20 },
    { header: 'Customer', key: 'customer', width: 30 },
    { header: 'Total', key: 'total', width: 15, style: { numFmt: '$#,##0.00' } },
    { header: 'Status', key: 'status', width: 15 },
    { header: 'Date', key: 'date', width: 20, style: { numFmt: 'yyyy-mm-dd' } },
  ]

  // Style header row
  sheet.getRow(1).font = { bold: true }
  sheet.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF6366F1' } }
  sheet.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } }

  // Add data
  for (const order of data) {
    sheet.addRow({
      id: order.id,
      customer: order.customerName,
      total: order.totalCents / 100,
      status: order.status,
      date: order.createdAt,
    })
  }

  return workbook.xlsx.writeBuffer() as Promise<Buffer>
}
```

## Background Export Job

```typescript
// API endpoint — starts background export
app.post('/api/v1/exports', authGuard, async (req) => {
  const { type, filters, format } = ExportRequestSchema.parse(req.body)

  const job = await exportQueue.add('generate-export', {
    type, filters, format,
    userId: req.user.id,
  })

  return { jobId: job.id, status: 'processing' }
})

// Check export status
app.get('/api/v1/exports/:jobId', authGuard, async (req) => {
  const job = await exportQueue.getJob(req.params.jobId)
  if (!job) throw errors.notFound('Export job')

  const state = await job.getState()
  return {
    status: state,
    progress: job.progress,
    downloadUrl: state === 'completed' ? job.returnvalue?.url : null,
  }
})
```

## Signed Download URLs

```typescript
import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3'
import { getSignedUrl } from '@aws-sdk/s3-request-presigner'

async function generateSignedUrl(key: string, expiresIn = 3600): Promise<string> {
  const command = new GetObjectCommand({ Bucket: process.env.S3_BUCKET, Key: key })
  return getSignedUrl(s3Client, command, { expiresIn })
}
```

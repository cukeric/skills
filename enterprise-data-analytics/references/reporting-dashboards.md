# Reporting & Dashboards Reference

## Chart Library Selection

| Library | Best For | Complexity |
|---|---|---|
| **Recharts** | React, simple charts | Low |
| **Chart.js** | Vanilla JS, quick setup | Low |
| **D3.js** | Custom, complex visualizations | High |
| **Nivo** | React, rich chart types | Medium |
| **Apache ECharts** | Large datasets, maps | Medium |

**Default: Recharts** for React apps. Chart.js for non-React.

## Recharts Dashboard Pattern

```typescript
import { LineChart, Line, BarChart, Bar, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'

function RevenueDashboard({ data }: { data: RevenueData[] }) {
  return (
    <div className="grid grid-cols-2 gap-6">
      <ResponsiveContainer width="100%" height={300}>
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="#2D2D4A" />
          <XAxis dataKey="date" stroke="#64748B" />
          <YAxis stroke="#64748B" tickFormatter={(v) => `$${v / 100}`} />
          <Tooltip formatter={(v: number) => [`$${(v / 100).toFixed(2)}`, 'Revenue']} />
          <Line type="monotone" dataKey="revenue" stroke="#6366F1" strokeWidth={2} dot={false} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
```

## Scheduled Reports

```typescript
// Generate and email weekly report
const reportWorker = new Worker('reports', async (job) => {
  const { type, recipients, dateRange } = job.data

  // Query data
  const data = await getReportData(type, dateRange)

  // Generate PDF
  const pdf = await generatePDFReport(data, type)

  // Upload to S3
  const url = await uploadToS3(pdf, `reports/${type}/${Date.now()}.pdf`)

  // Email to recipients
  for (const email of recipients) {
    await emailService.send({
      to: email,
      subject: `${type} Report — ${formatDateRange(dateRange)}`,
      template: 'report-delivery',
      attachments: [{ filename: `${type}-report.pdf`, url }],
    })
  }
})

// Schedule
await reportQueue.add('weekly-sales', {
  type: 'sales',
  recipients: ['team@company.com'],
  dateRange: 'last-7-days',
}, {
  repeat: { pattern: '0 9 * * 1' }, // Monday 9 AM
})
```

## Dashboard Query Optimization

```sql
-- Materialized view for dashboard metrics (refresh periodically)
CREATE MATERIALIZED VIEW dashboard_daily_metrics AS
SELECT
  date_trunc('day', created_at) AS date,
  count(*) AS order_count,
  sum(total_cents) AS revenue_cents,
  avg(total_cents) AS avg_order_cents,
  count(DISTINCT customer_id) AS unique_customers
FROM orders
WHERE created_at >= now() - interval '90 days'
GROUP BY date_trunc('day', created_at)
ORDER BY date;

-- Refresh on schedule
REFRESH MATERIALIZED VIEW CONCURRENTLY dashboard_daily_metrics;
```

# Data Warehouse Patterns Reference

## Star Schema

```
            ┌──────────────┐
            │  dim_product  │
            └──────┬───────┘
                   │
┌──────────┐  ┌────┴────────┐  ┌──────────────┐
│dim_date  ├──┤ fact_orders  ├──┤ dim_customer  │
└──────────┘  └────┬────────┘  └──────────────┘
                   │
            ┌──────┴───────┐
            │ dim_location  │
            └──────────────┘
```

```sql
-- Fact table (metrics)
CREATE TABLE fact_orders (
  order_key BIGINT PRIMARY KEY,
  date_key INT REFERENCES dim_date(date_key),
  product_key INT REFERENCES dim_product(product_key),
  customer_key INT REFERENCES dim_customer(customer_key),
  location_key INT REFERENCES dim_location(location_key),
  quantity INT,
  unit_price_cents BIGINT,
  total_cents BIGINT,
  discount_cents BIGINT DEFAULT 0
);

-- Dimension table (descriptive attributes)
CREATE TABLE dim_date (
  date_key INT PRIMARY KEY,       -- YYYYMMDD format
  full_date DATE NOT NULL,
  year INT, quarter INT, month INT, week INT, day INT,
  day_of_week VARCHAR(10),
  is_weekend BOOLEAN,
  is_holiday BOOLEAN
);

-- Pre-populate dim_date for 10 years
INSERT INTO dim_date
SELECT
  to_char(d, 'YYYYMMDD')::INT,
  d, extract(year from d), extract(quarter from d),
  extract(month from d), extract(week from d), extract(day from d),
  to_char(d, 'Day'), extract(dow from d) IN (0, 6), false
FROM generate_series('2020-01-01'::date, '2030-12-31'::date, '1 day') AS d;
```

## Materialized Views

```sql
-- Pre-computed daily metrics
CREATE MATERIALIZED VIEW mv_daily_revenue AS
SELECT
  dd.full_date,
  dd.year, dd.month, dd.day_of_week,
  dp.category AS product_category,
  dl.country,
  count(*) AS order_count,
  sum(fo.total_cents) AS total_revenue_cents,
  avg(fo.total_cents) AS avg_order_cents
FROM fact_orders fo
JOIN dim_date dd ON fo.date_key = dd.date_key
JOIN dim_product dp ON fo.product_key = dp.product_key
JOIN dim_location dl ON fo.location_key = dl.location_key
GROUP BY dd.full_date, dd.year, dd.month, dd.day_of_week, dp.category, dl.country;

CREATE UNIQUE INDEX ON mv_daily_revenue (full_date, product_category, country);

-- Refresh (schedule via cron)
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_revenue;
```

## Data Retention

```sql
-- Automated data archival
CREATE OR REPLACE FUNCTION archive_old_data() RETURNS void AS $$
BEGIN
  -- Move old orders to archive table
  INSERT INTO orders_archive SELECT * FROM orders WHERE created_at < now() - interval '2 years';
  DELETE FROM orders WHERE created_at < now() - interval '2 years';

  -- Delete old analytics events
  DELETE FROM analytics_events WHERE created_at < now() - interval '1 year';

  -- Delete old audit logs (keep 6 years for compliance)
  DELETE FROM audit_logs WHERE created_at < now() - interval '6 years';
END;
$$ LANGUAGE plpgsql;
```

## ClickHouse (Columnar Analytics DB)

```sql
-- ClickHouse: optimized for analytical queries
CREATE TABLE events (
  event_id UUID DEFAULT generateUUIDv4(),
  event_type LowCardinality(String),
  user_id String,
  properties String, -- JSON
  timestamp DateTime64(3),
  date Date DEFAULT toDate(timestamp)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (event_type, user_id, timestamp)
TTL date + INTERVAL 1 YEAR;

-- Queries on billions of rows in milliseconds
SELECT
  event_type,
  count() AS count,
  uniqExact(user_id) AS unique_users
FROM events
WHERE date >= today() - 30
GROUP BY event_type
ORDER BY count DESC;
```

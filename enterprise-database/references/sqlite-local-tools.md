# SQLite for Local Tools and MCP Servers

Covers `better-sqlite3` (Node.js, synchronous), schema versioning, WAL mode, and FK strategy for developer tools — including the cross-entity entity_id pattern.

---

## When to Use SQLite

| Use Case | SQLite | PostgreSQL |
|---|---|---|
| MCP server, CLI tool, local dev tool | ✅ Yes | No — external service, deployment overhead |
| Desktop app data storage | ✅ Yes | No |
| Single-writer production SaaS | Acceptable | ✅ Preferred |
| Multi-process concurrent writes | No | ✅ Yes |
| Hosted/VPS production with multiple instances | No | ✅ Yes |

---

## Setup with `better-sqlite3`

```bash
npm install better-sqlite3
npm install -D @types/better-sqlite3
```

```typescript
import Database from "better-sqlite3";

const db = new Database("/path/to/data.db");

// Always enable WAL mode — dramatically better concurrent read performance
db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");  // FK enforcement is OFF by default in SQLite
db.pragma("synchronous = NORMAL"); // Safe + faster than FULL with WAL
```

**WAL mode** allows readers to not block writers and vice versa — essential for MCP servers that handle search (read) while indexing (write) happens concurrently.

---

## Schema Versioning Pattern

For tools that evolve over time, use a `schema_version` table and explicit migration blocks:

```typescript
const SCHEMA_VERSION = 3;

function migrateSchema(db: Database.Database): void {
  // Create version tracking table if it doesn't exist
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)
  `);

  const row = db.prepare("SELECT version FROM schema_version").get() as
    | { version: number }
    | undefined;
  const fromVersion = row?.version ?? 0;

  if (fromVersion === SCHEMA_VERSION) return;

  db.transaction(() => {
    if (fromVersion < 1) {
      db.exec(`CREATE TABLE IF NOT EXISTS symbols (...)`);
    }
    if (fromVersion < 2) {
      // Additive migration — add new table without touching existing data
      db.exec(`CREATE TABLE IF NOT EXISTS vector_index (...)`);
    }
    if (fromVersion < 3) {
      // Breaking migration — incompatible data format change
      // Must DROP and recreate rather than trying to migrate data
      db.exec(`DROP TABLE IF EXISTS vector_index`);
      db.exec(`CREATE TABLE IF NOT EXISTS vector_index (...)`);
    }

    if (row) {
      db.prepare("UPDATE schema_version SET version = ?").run(SCHEMA_VERSION);
    } else {
      db.prepare("INSERT INTO schema_version (version) VALUES (?)").run(SCHEMA_VERSION);
    }
  })();
}
```

**Version bump rules:**
- Additive change (new table, new column with default) → increment version, additive migration
- Incompatible change (encoding change, column type change) → DROP + recreate, users re-run index
- Data-format-only change (e.g. switching from 3-bit to 4-bit encoding in a BLOB column) → always bump version and DROP+recreate — you cannot migrate arbitrary binary data

---

## Cross-Entity FK Strategy

**The problem:** When a table stores entities of multiple types (e.g. `symbols` AND `sections`) with a single `entity_id` column, a standard FK to any single parent table will fail for the other entity type.

```sql
-- ❌ Wrong: FK blocks inserts for 'section' entities not in symbols table
CREATE TABLE vector_index (
  entity_id TEXT PRIMARY KEY REFERENCES symbols(id),  -- sections will fail NOT IN
  entity_type TEXT NOT NULL,
  ...
);

-- ✅ Correct: no FK — app-managed referential integrity
CREATE TABLE vector_index (
  entity_id TEXT PRIMARY KEY,   -- no FK constraint
  entity_type TEXT NOT NULL,    -- 'symbol' | 'section'
  ...
);
CREATE INDEX idx_vector_entity_type ON vector_index(entity_type);
```

**App-managed integrity:** When deleting a file, clean up all entity types:

```typescript
function deleteVectorsByFile(db: Database.Database, filePath: string): void {
  // Delete vectors for symbols in this file
  db.prepare(`
    DELETE FROM vector_index
    WHERE entity_id IN (
      SELECT id FROM symbols WHERE file_path = ?
    )
  `).run(filePath);

  // Delete vectors for sections in this file
  db.prepare(`
    DELETE FROM vector_index
    WHERE entity_id IN (
      SELECT id FROM sections WHERE file_path = ?
    )
  `).run(filePath);
}
```

**When to use this pattern:**
- Any table where `entity_id` can refer to rows from multiple parent tables
- Polymorphic associations (same column references different tables depending on `entity_type`)
- Event log / audit tables that record actions across all entity types

---

## Transactions

`better-sqlite3` uses synchronous transactions:

```typescript
// Wrap multi-step writes — all succeed or all rollback
const insertBatch = db.transaction((items: Item[]) => {
  const stmt = db.prepare("INSERT INTO items (id, value) VALUES (?, ?)");
  for (const item of items) {
    stmt.run(item.id, item.value);
  }
});

insertBatch(myItems);
```

For the indexer pattern (symbol insert → embedding → vector insert), wrap the full sequence per file:

```typescript
const indexFile = db.transaction((symbols: Symbol[], vectors: Vector[]) => {
  for (const s of symbols) insertSymbol.run(s);
  for (const v of vectors) insertVector.run(v);
});
```

This ensures a file is never half-indexed — either all symbols+vectors are written or none are.

---

## Prepared Statements

Always prepare statements outside loops. `better-sqlite3` compiles SQL on `.prepare()`:

```typescript
// ✅ Prepare once, run many times
const insertStmt = db.prepare("INSERT INTO symbols (id, name, kind) VALUES (?, ?, ?)");
for (const sym of symbols) {
  insertStmt.run(sym.id, sym.name, sym.kind);
}

// ❌ Don't prepare inside a loop
for (const sym of symbols) {
  db.prepare("INSERT INTO ...").run(sym.id, sym.name, sym.kind); // re-compiles every iteration
}
```

---

## FTS5 Full-Text Search

```sql
-- Create FTS5 virtual table
CREATE VIRTUAL TABLE fts_symbols USING fts5(
  symbol_id UNINDEXED,   -- not searchable, just carried along
  name,
  signature,
  doc_comment,
  content='symbols',     -- content table (optional — keeps FTS in sync)
  tokenize='porter ascii'
);

-- Keyword search with ranking
SELECT s.*, rank
FROM fts_symbols
JOIN symbols s ON s.id = fts_symbols.symbol_id
WHERE fts_symbols MATCH ?
ORDER BY rank
LIMIT 20;
```

**FTS5 vs LIKE:** Always use FTS5 for text search — it's 10–100x faster and supports stemming, phrase matching, and BM25 ranking out of the box.

---

## BLOB Storage for Vectors

SQLite stores BLOB columns efficiently. For embedding vectors:

```typescript
// Store: Float32Array → Uint8Array for BLOB
const blob = Buffer.from(embedding.buffer);
insertVectorStmt.run({ embedding: blob });

// Read: BLOB → Float32Array
const row = selectStmt.get(id) as { embedding: Buffer };
const embedding = new Float32Array(row.embedding.buffer);
```

For compressed vectors (e.g. quantized), store the raw `Uint8Array` bytes:

```typescript
const pqAngles = Buffer.from(compressed.pqAngles);    // Uint8Array
const qjlBits = Buffer.from(compressed.qjlBits);      // Uint8Array
insertVectorStmt.run({ pqAngles, qjlBits });
```

---

## Performance Notes

| Operation | Typical Speed (SSD) |
|---|---|
| Single row INSERT | ~0.1ms |
| Batch 1000 INSERTs (transaction) | ~5–10ms |
| FTS5 keyword search (10k rows) | ~1ms |
| Full table scan (vector search, 2.5k rows) | ~5–15ms |
| Schema migration with DROP+recreate | ~50ms |

**Bottleneck for MCP/indexer tools:** Embedding generation (20–25ms/symbol), not SQLite writes.

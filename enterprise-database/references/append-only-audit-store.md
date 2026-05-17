# Append-Only Audit Store — PostgreSQL 16 + Prisma 7

Patterns for a durable, queryable, tamper-evident audit/event store: append-only
tables, row-level security, application-side PII encryption, and a verifiable hash
chain. Built and shipped to production for the AIGIST `@aigist/audit-db` package;
these patterns are battle-tested, including the failure modes a code review caught.

Read alongside `postgresql.md` (RLS, PITR) and `orm-guide.md` (Prisma adapter).

---

## 1. Prisma 7 adapter — and when to drop to the `pg` driver

Prisma 7 uses the driver-adapter pattern — **no `url` in `datasource db {}`**:

```prisma
datasource db {
  provider = "postgresql"
  // No `url` — the connection is injected via PrismaPg (prisma.config.ts).
}
```

```ts
// prisma.config.ts
import { defineConfig } from "prisma/config";
import { PrismaPg } from "@prisma/adapter-pg";
export default defineConfig({ migrate: { adapter: new PrismaPg(process.env.DB_URL!) } });
```

**An audit store legitimately bypasses the Prisma query API.** Three things cannot
be expressed through Prisma's query builder and require the raw `pg` driver
(`@prisma/adapter-pg` wraps `pg` anyway — same driver, no extra dependency):

| Need | Why Prisma's API can't do it |
|---|---|
| `SET LOCAL app.role = ...` per transaction (RLS identity) | Session/txn-scoped `SET` is not a query-builder concept. |
| `pg_advisory_xact_lock(...)` to serialise appends | Advisory locks are raw-SQL only. |
| Atomic "read chain head, then INSERT" in one txn | Needs an explicit transaction with raw statements. |

**The honest posture when you do this:** `schema.prisma` becomes a *documentation
artifact* of the shape; the **raw `0001_init.sql` migration is authoritative**;
`prisma generate` may not be run at all. Document this deviation in the package
README so the next reader is not surprised the Prisma client is unused at runtime.
Every raw query must still be parameterized — `$1`, `$2` — and `SET LOCAL` values
set via `set_config(name, $1, true)`, never string-interpolated.

---

## 2. Append-only enforcement — a trigger, not a convention

Revoking `UPDATE`/`DELETE` grants is not enough — the table owner and superusers
keep them. Enforce immutability with a trigger that fires regardless of role:

```sql
CREATE OR REPLACE FUNCTION event_log_append_only() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'event_log is append-only: % is not permitted', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_event_log_append_only
  BEFORE UPDATE OR DELETE ON event_log
  FOR EACH ROW EXECUTE FUNCTION event_log_append_only();

-- TRUNCATE is a separate event class — a row-level trigger does NOT catch it:
CREATE TRIGGER trg_event_log_no_truncate
  BEFORE TRUNCATE ON event_log
  FOR EACH STATEMENT EXECUTE FUNCTION event_log_append_only();
```

Apply the **same trigger to every provenance table** — export logs, signature
logs. A common review miss: protecting the main event table but leaving
`report_export_log` (who exported what, when) mutable. If a table is SOC 2
tamper-evidence, it gets the trigger. Tables that are mutable *by design* (an HITL
queue that goes `PENDING → ESCALATED → RESOLVED`) correctly do not — state that
intent in a comment so the asymmetry is not read as an oversight.

---

## 3. RLS for an audit store — `ENABLE`, not `FORCE`

Per-role policies (operator sees own rows, auditor/supervisor see all, admin sees
all + raw):

```sql
ALTER TABLE event_log ENABLE ROW LEVEL SECURITY;   -- NOT `FORCE` — see below
CREATE POLICY operator_own ON event_log FOR SELECT
  USING (actor_id = current_setting('app.actor_id', true));
CREATE POLICY auditor_all ON event_log FOR SELECT
  USING (current_setting('app.role', true) IN ('auditor','supervisor','admin'));
```

**`ENABLE` vs `FORCE` is load-bearing.** `FORCE ROW LEVEL SECURITY` subjects the
*table owner* to RLS too. If an owner-run `SECURITY DEFINER` function needs an
unfiltered read (see §4), `FORCE` silently re-filters it and breaks the function
with no error. Use `ENABLE` and ensure the runtime role is **never the table
owner** (own the schema with a dedicated admin role; the app connects as a
restricted, non-owner role). Add a comment on the `ALTER TABLE` explaining why it
is `ENABLE` — otherwise a future "hardening" pass flips it to `FORCE` and forks
your data.

**A redaction view** for non-admin reads — make it `security_invoker` so it does
not become an RLS bypass:

```sql
CREATE VIEW event_log_redacted WITH (security_invoker = true) AS
  SELECT id, created_at, actor_id, action, /* PII columns masked */ FROM event_log;
```

---

## 4. The chain-head problem with RLS + SECURITY DEFINER

An append-only hash chain links each row to the previous (`hash = H(prev_hash ||
canonical(row))`). To append, you must read the **true global head**. But under
RLS, an operator session's "head" is the operator's *own* last row — so each actor
forks the chain.

Fix: a `SECURITY DEFINER` function, owned by the schema-admin role, that returns
only the head hash + sequence (no PII, minimal surface):

```sql
CREATE FUNCTION event_log_chain_head() RETURNS TABLE(hash bytea, seq bigint)
  LANGUAGE sql SECURITY DEFINER SET search_path = public AS
$$ SELECT hash, seq FROM event_log ORDER BY seq DESC LIMIT 1 $$;
```

This is exactly why §3 insists on `ENABLE` not `FORCE` — the function runs as the
owner and must be RLS-exempt.

---

## 5. Order the chain by a sequence, not a timestamp

`created_at timestamptz` is **not** a safe chain order: two appends in the same
millisecond collide, and ordering by a non-unique column forks the chain
non-deterministically. Add a dedicated monotonic column:

```sql
CREATE SEQUENCE event_log_seq;
ALTER TABLE event_log ADD COLUMN seq bigint NOT NULL DEFAULT nextval('event_log_seq');
```

Assign `seq` *inside* the advisory-locked append transaction so it reflects true
append order. Cursor-paginate on `seq` (an opaque numeric token), never on a row
`id` resolved via a sub-`SELECT` — under RLS that sub-select returns nothing for
rows the caller cannot see, silently yielding an empty page.

---

## 6. PII encryption — application-side, fail-closed

Encrypt detected-PII columns with AES-256-GCM **in the application**, before INSERT
and before hashing (so the chain verifies without the decryption key). Do **not**
use `pgcrypto` — keep key management in one place (the app's KMS/derivation).

Two failure modes a review caught — both silent data loss:

- **Auto-generated keys.** A key loader that *generates and persists* a key on
  first use, when the persist path is an ephemeral container layer, mints a new key
  every deploy and orphans all prior ciphertext. The derive path for data-at-rest
  must be **load-only and fail-closed** — throw if the key is absent; never
  auto-generate. Provision the key as an explicit, persistent, backed-up secret.
- **One bad field fails the whole read.** Decrypting a page of rows: wrap each
  field in try/catch and return a `"[decrypt-failed]"` sentinel + log the row id.
  Otherwise one corrupt/wrong-key field throws and denies the entire audit query.

See `enterprise-security` for key provisioning, rotation, and the no-fallback
pattern.

---

## 7. WAL archiving — never fake it

For PITR, WAL archiving must be **real or off** — never a no-op pretending to work:

```sh
# WRONG — `|| true` makes archive_command always exit 0; Postgres recycles WAL it
# never archived. archive_mode=on + a command that cannot fail = silent WAL loss.
archive_command = 'wal-g wal-push %p || true'
```

If the archiver binary (`wal-g`, `pgbackrest`) is not installed in the image, or
its credentials are not yet provisioned, set `archive_mode = off` and rely on
nightly `pg_dump` as the documented working backup. Turning `archive_mode = on`
with a command that cannot fail is **worse than off** — it manufactures false
confidence in recoverability. Switch it on only with the archiver genuinely
installed and a command allowed to fail loudly.

---

## 8. The `migrate` script needs a build (CI gotcha)

`"migrate": "node ./dist/apply-migration.js"` fails in CI if it runs before the
package is built. If the integration suite already applies the migration in its
`beforeAll()`, a standalone CI migrate step is redundant — drop it.
See `enterprise-devx-monorepo/references/ci-local-parity.md` §4.

---

## Verification checklist

- [ ] Prisma 7: no `url` in datasource; adapter in `prisma.config.ts`
- [ ] Raw-`pg` deviations (RLS `SET LOCAL`, advisory locks) documented in the README
- [ ] All raw SQL parameterized; `SET LOCAL` via `set_config(_, $1, true)`
- [ ] Append-only trigger on every immutable table — incl. `BEFORE TRUNCATE`
- [ ] RLS `ENABLE` (not `FORCE`); runtime role is not the table owner; reason commented
- [ ] Redaction view is `security_invoker = true`
- [ ] Chain ordered by a dedicated `seq`, assigned inside the locked append txn
- [ ] PII key load is fail-closed (no auto-generate); per-field decrypt tolerance
- [ ] `archive_mode = off` unless the WAL archiver is genuinely installed + provisioned
- [ ] Integration suite verified against a real Postgres matching the CI image tag

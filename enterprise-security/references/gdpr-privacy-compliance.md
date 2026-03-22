# GDPR, CCPA & Privacy Compliance — Implementation Patterns

Covers the technical implementation of privacy regulations (GDPR, CCPA, PIPEDA) in web applications. For SOC2/HIPAA/PCI-DSS, see `compliance-soc2-hipaa.md`. For secrets management, see `secrets-rotation.md`.

---

## Cookie Consent

### Architecture

Cookie consent must gate all non-essential tracking (analytics, marketing pixels, third-party scripts). Essential cookies (session, CSRF, locale preference) do not require consent.

```typescript
// CookieConsent component pattern
// 1. Check localStorage for existing consent
// 2. If no consent, show banner (non-blocking, bottom of page)
// 3. On accept/reject, store preference in localStorage
// 4. Emit custom event so other components react immediately

const CONSENT_KEY = 'cookie-consent'

function grantConsent() {
  localStorage.setItem(CONSENT_KEY, JSON.stringify({
    analytics: true,
    marketing: false, // separate toggles for granular control
    timestamp: new Date().toISOString(),
  }))
  window.dispatchEvent(new Event('consent-change'))
}
```

### Cross-Component Sync

Use a custom DOM event (not prop drilling) to synchronize consent state:

```typescript
// AnalyticsProvider listens for consent changes
useEffect(() => {
  const checkConsent = () => {
    const stored = localStorage.getItem('cookie-consent')
    setEnabled(stored ? JSON.parse(stored).analytics : false)
  }
  checkConsent()
  window.addEventListener('consent-change', checkConsent)
  return () => window.removeEventListener('consent-change', checkConsent)
}, [])
```

### Cookie Categories (EU ePrivacy Directive)

| Category | Requires Consent | Examples |
|---|---|---|
| Strictly necessary | No | Session cookies, CSRF tokens, auth tokens |
| Preferences | Yes | Language, theme, locale |
| Analytics | Yes | Page views, events, funnels |
| Marketing | Yes | Ad pixels, retargeting, third-party trackers |

---

## Data Export (GDPR Article 20 — Portability)

Users must be able to export all their data in a machine-readable format.

```typescript
// /api/account/export pattern
export async function GET(req: Request) {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) return unauthorized()

  const user = await prisma.user.findUnique({
    where: { id: session.user.id },
    include: {
      listings: true,
      purchases: true,
      tokenBatches: true,
      referrals: true,
      // Include ALL user-owned data
    },
  })

  // NEVER include: password hashes, encrypted tokens, internal IDs, storage keys
  const exportData = {
    profile: { name: user.name, email: user.email, createdAt: user.createdAt },
    listings: user.listings.map(l => ({ /* sanitized fields */ })),
    purchases: user.purchases.map(p => ({ /* sanitized fields */ })),
    exportedAt: new Date().toISOString(),
  }

  return new Response(JSON.stringify(exportData, null, 2), {
    headers: {
      'Content-Type': 'application/json',
      'Content-Disposition': `attachment; filename="data-export-${Date.now()}.json"`,
    },
  })
}
```

---

## Account Deletion (GDPR Article 17 — Right to Erasure)

Account deletion must cascade across all systems, not just the database.

### Deletion Cascade Order

```
1. External services (Stripe: cancel subscriptions, delete customer)
2. Filesystem (photos, videos, uploaded files)
3. Database (cascade delete all user-owned records)
4. Session invalidation (sign out everywhere)
```

### Implementation

```typescript
// Require explicit confirmation to prevent accidental deletion
const CONFIRMATION_STRING = 'DELETE MY ACCOUNT'

export async function DELETE(req: Request) {
  const { confirmation } = await req.json()
  if (confirmation !== CONFIRMATION_STRING) {
    return Response.json({ error: { code: 'INVALID_CONFIRMATION' } }, { status: 400 })
  }

  const session = await getServerSession(authOptions)

  await prisma.$transaction(async (tx) => {
    // 1. Cancel Stripe subscriptions
    if (user.stripeCustomerId) {
      const subs = await stripe.subscriptions.list({ customer: user.stripeCustomerId })
      for (const sub of subs.data) {
        await stripe.subscriptions.cancel(sub.id)
      }
    }

    // 2. Delete filesystem artifacts
    await deleteUserFiles(user.id) // photos, videos

    // 3. Cascade delete in database
    await tx.user.delete({ where: { id: user.id } })
    // Prisma cascade handles related records if schema has onDelete: Cascade
  })
}
```

### What NOT to delete

- **Audit logs** — retain for compliance (anonymize user references)
- **Financial records** — Stripe retains these; your database records may be legally required for tax purposes
- **Anonymized analytics** — aggregate data with no PII can be retained

---

## App-Level Encryption Key Rotation

For applications that encrypt user data (OAuth tokens, PII) with AES-256-GCM at the application level:

### Dual-Key Decrypt Pattern (Zero Downtime)

```typescript
// crypto.ts — zero-downtime key rotation
function getKey(): Buffer {
  return Buffer.from(process.env.TOKEN_ENCRYPTION_KEY!, 'hex')
}

function getPreviousKey(): Buffer | null {
  const prev = process.env.TOKEN_ENCRYPTION_KEY_PREVIOUS
  return prev ? Buffer.from(prev, 'hex') : null
}

function decrypt(encrypted: string): string {
  // Try current key first
  try {
    return decryptWithKey(encrypted, getKey())
  } catch {
    // Fallback to previous key during rotation window
    const prev = getPreviousKey()
    if (!prev) throw new Error('Decryption failed')
    return decryptWithKey(encrypted, prev)
  }
}

function reEncrypt(encrypted: string): string {
  const plaintext = decrypt(encrypted) // works with either key
  return encrypt(plaintext) // always encrypts with current key
}
```

### Rotation Procedure

1. Generate new key: `openssl rand -hex 32`
2. Set `TOKEN_ENCRYPTION_KEY_PREVIOUS` = current key value
3. Set `TOKEN_ENCRYPTION_KEY` = new key value
4. Deploy — dual-key decrypt handles both old and new
5. Run batch re-encryption endpoint (admin-protected, processes N records at a time)
6. After all records migrated, remove `TOKEN_ENCRYPTION_KEY_PREVIOUS`

---

## Regional Compliance Quick Reference

| Regulation | Region | Key Requirements |
|---|---|---|
| **GDPR** | EU/EEA | Consent, portability, erasure, DPO, 72h breach notification |
| **CCPA/CPRA** | California | Opt-out of sale, access, deletion, no discrimination |
| **PIPEDA** | Canada | Consent, limited collection, accuracy, accountability |
| **LGPD** | Brazil | Similar to GDPR — consent, access, deletion, DPO |

### PIPEDA-Specific (Canadian SaaS)

- Privacy policy must be available in both English and French for federal compliance
- Consent must be "meaningful" — explain in plain language what data you collect and why
- Data breach notification to Privacy Commissioner within 72 hours if "real risk of significant harm"
- Ontario businesses: also subject to Ontario Consumer Protection Act provisions

# Third-Party Vendor & API Risk Assessment

When integrating any third-party service that handles user data (photos, PII, financial data, credentials), perform this audit before going to production.

---

## Vendor Identity Checklist

Before sending any user data to a third-party API:

| Check | Required | How to Verify |
|---|---|---|
| Identifiable legal entity | Yes | Company registration, website "About" page, LinkedIn company page |
| Physical address or jurisdiction | Yes | Footer, Terms of Service, privacy policy |
| Named founders or team | Recommended | LinkedIn, Crunchbase, GitHub org members visible |
| Contact information | Yes | Support email, phone, registered agent |
| Business registration | Yes | State/country business registry lookup |

**If any of these fail:** The vendor is anonymous. Do NOT send user PII or sensitive data. If you must use the service, apply maximum safeguards (see below).

---

## Privacy & Compliance Checklist

| Check | Required | What to Look For |
|---|---|---|
| Privacy policy exists | Yes | Must state what data is collected, how it's used, and retention period |
| Data retention period stated | Yes | "We delete data after X days" — vague policies are red flags |
| DPA (Data Processing Agreement) available | For EU data | GDPR Article 28 requirement for any processor handling EU personal data |
| GDPR compliance claimed | For EU users | Must document legal basis, data subject rights, DPO contact |
| CCPA compliance claimed | For CA users | Must disclose data categories, sale/sharing, opt-out rights |
| Subprocessor disclosure | Recommended | Who else gets access to your data? |
| Breach notification commitment | Yes | How quickly will they notify you of a data breach? |

---

## Technical Security Checklist

| Check | Required | How to Verify |
|---|---|---|
| TLS/HTTPS enforced | Yes | `curl -sI https://api.vendor.com` — check for HSTS header |
| API authentication | Yes | Bearer token, API key, or OAuth — never unauthenticated |
| Rate limiting | Recommended | Check API docs for rate limit headers |
| Input size limits | Recommended | What's the max payload size? |
| Output sanitization | Recommended | Does the API return sanitized content? |

---

## Data Safeguards (When Using High-Risk Vendors)

When a vendor fails identity or compliance checks but you still need to use them:

### 1. Strip Metadata Before Sending

```typescript
// Strip EXIF (GPS, camera, timestamps) from images using sharp
import sharp from "sharp"

async function stripExifMetadata(photo: { data: string; mimeType: string }) {
  const inputBuffer = Buffer.from(photo.data, "base64")
  const strippedBuffer = await sharp(inputBuffer)
    .rotate()                          // preserve orientation before stripping
    .withMetadata({ exif: undefined }) // remove all EXIF data
    .toBuffer()
  return { data: strippedBuffer.toString("base64"), mimeType: photo.mimeType }
}
```

### 2. Minimize Data Sent

- Don't send user IDs, email addresses, or account info in API calls
- Strip or generalize addresses if possible
- Send only the minimum data needed for the API to function

### 3. Don't Persist Vendor-Side

- Download results immediately and store locally
- Don't rely on vendor URLs for long-term storage
- Assume vendor may delete or change URLs at any time

### 4. Monitor and Audit

- Log all API calls to third-party services (without logging PII payloads)
- Track credit/cost consumption
- Set up alerts for unexpected usage patterns

### 5. Document the Risk

- Add vendor risk assessment to your Terms of Service
- Disclose third-party processing in your Privacy Policy
- Maintain a vendor register with risk ratings

---

## Risk Rating Matrix

| Rating | Criteria | Action |
|---|---|---|
| **LOW** | Known company, DPA available, GDPR compliant, data retention documented | Use with standard monitoring |
| **MEDIUM** | Known company, privacy policy exists but incomplete, no DPA | Use with safeguards, request DPA |
| **HIGH** | Anonymous operator, no compliance docs, unclear data retention | Apply all safeguards, plan migration to alternative |
| **CRITICAL** | Anonymous + handles PII/financial + no TLS/weak auth | Do not use. Find alternative immediately. |

---

## ToS Violation Risk

If a vendor resells another company's API (e.g., reselling Google Veo, OpenAI, etc.):

- **Check if reselling is authorized** — most cloud API ToS prohibit unauthorized resale
- **Service continuity risk** — the upstream provider can terminate the reseller's account at any time
- **No SLA inheritance** — the reseller's uptime depends on their relationship with the upstream provider
- **Price instability** — upstream price changes can kill the reseller's business model overnight

**Recommendation:** Prefer official APIs or authorized resellers with partnership documentation.

# Compliance Frameworks Reference — SOC2, HIPAA, PCI-DSS

## SOC2 Type II

### Overview

SOC2 certifies that your organization handles customer data securely based on the Trust Service Criteria (TSC): Security, Availability, Processing Integrity, Confidentiality, Privacy.

### Technical Controls Checklist

**Security (Required)**

- [ ] Access control: RBAC, MFA for all internal systems
- [ ] Network security: firewalls, VPN, network segmentation
- [ ] Encryption: TLS 1.2+ in transit, AES-256 at rest
- [ ] Logging: centralized audit logs with 1-year retention
- [ ] Vulnerability management: regular scanning, patching SLA
- [ ] Incident response plan documented and tested
- [ ] Background checks on employees with data access
- [ ] Security awareness training (annual)

**Availability**

- [ ] Uptime SLA defined (99.9% typical)
- [ ] Disaster recovery plan with RTO/RPO targets
- [ ] Automated backups with tested restoration
- [ ] Health monitoring with alerting
- [ ] Capacity planning documented

**Confidentiality**

- [ ] Data classification policy (public, internal, confidential, restricted)
- [ ] NDA for employees and contractors
- [ ] Data retention and destruction policies
- [ ] Encryption for confidential data at rest

**Processing Integrity**

- [ ] Input validation on all data entry points
- [ ] Reconciliation processes for financial data
- [ ] Error handling that preserves data integrity
- [ ] Change management process documented

**Privacy**

- [ ] Privacy policy published and current
- [ ] Data subject access request (DSAR) process
- [ ] Data minimization: collect only what's needed
- [ ] Consent management for data collection

### Evidence Collection

```markdown
## SOC2 Evidence Checklist
- [ ] Architecture diagram (current)
- [ ] Network topology diagram
- [ ] Data flow diagram (how data moves through systems)
- [ ] Access control matrix (who has access to what)
- [ ] Encryption configuration screenshots
- [ ] Vulnerability scan reports (last 4 quarters)
- [ ] Incident response runbook
- [ ] Employee onboarding/offboarding procedures
- [ ] Change management logs (last 12 months)
- [ ] Backup verification logs
- [ ] Monitoring dashboard screenshots
- [ ] Security training completion records
```

---

## HIPAA (Healthcare)

### Overview

HIPAA requires safeguards for Protected Health Information (PHI). Applies to Covered Entities and Business Associates.

### Technical Safeguards (§164.312)

**Access Control**

- [ ] Unique user identification (no shared accounts)
- [ ] Emergency access procedure documented
- [ ] Automatic logoff after inactivity (15 minutes max)
- [ ] Encryption of ePHI at rest and in transit

**Audit Controls**

- [ ] Record and examine access to ePHI
- [ ] Audit logs retained for 6 years
- [ ] Regular audit log review (at least quarterly)

**Integrity Controls**

- [ ] Mechanism to authenticate ePHI
- [ ] Protect ePHI from improper modification or destruction

**Transmission Security**

- [ ] Encryption of ePHI transmitted over networks (TLS 1.2+)
- [ ] Integrity controls for transmitted data

### BAA (Business Associate Agreement)

Required with every vendor that handles PHI:

- Cloud providers (AWS, GCP, Azure)
- Email services
- Analytics tools
- Monitoring services
- Database hosting

### HIPAA Implementation Patterns

```typescript
// PHI Access Logging (required)
async function logPHIAccess(params: {
  userId: string
  action: 'view' | 'create' | 'update' | 'delete' | 'export'
  resourceType: string
  resourceId: string
  ip: string
  reason?: string
}) {
  await db.phiAuditLog.create({
    data: {
      ...params,
      timestamp: new Date(),
      // Immutable — retention: 6 years
    },
  })
}

// Auto-logout middleware
const SESSION_TIMEOUT = 15 * 60 * 1000 // 15 minutes

app.addHook('onRequest', async (req) => {
  if (req.user) {
    const lastActivity = await redis.get(`session:${req.user.sessionId}:lastActivity`)
    if (lastActivity && Date.now() - parseInt(lastActivity) > SESSION_TIMEOUT) {
      await invalidateSession(req.user.sessionId)
      throw errors.unauthorized('Session expired due to inactivity')
    }
    await redis.set(`session:${req.user.sessionId}:lastActivity`, Date.now().toString())
  }
})
```

---

## PCI-DSS (Payment Card Data)

### Overview

PCI-DSS applies to any system that stores, processes, or transmits cardholder data (CHD).

### Key Requirements

**Build & Maintain Secure Network**

- [ ] Firewall configuration to protect cardholder data
- [ ] Do not use vendor-supplied default passwords

**Protect Cardholder Data**

- [ ] Protect stored cardholder data (encrypt with AES-256)
- [ ] Encrypt transmission of CHD across open networks (TLS 1.2+)
- [ ] Never store CVV/CVC after authorization

**Vulnerability Management**

- [ ] Use and regularly update anti-virus
- [ ] Develop and maintain secure systems (patching, secure development)

**Access Control**

- [ ] Restrict access to CHD on need-to-know basis
- [ ] Assign unique ID to each person with computer access
- [ ] Restrict physical access to cardholder data

**Monitoring & Testing**

- [ ] Track and monitor all access to network resources and CHD
- [ ] Regularly test security systems and processes

**Note**: Using Stripe Elements/Checkout means cardholder data never touches your servers, reducing PCI scope to SAQ-A (minimal requirements).

---

## Audit Preparation Timeline

| Weeks Before | Action |
|---|---|
| 12 weeks | Select auditor, define scope |
| 10 weeks | Gap analysis (internal review against framework) |
| 8 weeks | Remediate identified gaps |
| 6 weeks | Document all policies and procedures |
| 4 weeks | Collect evidence (screenshots, logs, configs) |
| 2 weeks | Internal review of evidence package |
| 0 weeks | Audit engagement begins |

---

## Compliance Checklist

- [ ] Compliance framework identified (SOC2/HIPAA/PCI-DSS)
- [ ] Data classification completed
- [ ] Technical controls implemented per framework requirements
- [ ] Audit logging with appropriate retention period
- [ ] Access control matrix documented
- [ ] Encryption at rest and in transit verified
- [ ] Incident response plan documented and tested
- [ ] Vendor agreements (BAA/DPA) executed
- [ ] Evidence collection automated where possible
- [ ] Regular internal reviews scheduled (quarterly)

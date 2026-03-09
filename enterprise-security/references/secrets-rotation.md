# Secrets Management & Rotation Reference

## Secrets Manager Selection

| Tool | Best For | Cost |
|---|---|---|
| **Doppler** | Teams, multi-env, easy setup | Free tier |
| **HashiCorp Vault** | Enterprise, dynamic secrets, self-hosted | OSS / Enterprise |
| **AWS Secrets Manager** | AWS-native workloads | $0.40/secret/month |
| **1Password Service Accounts** | Small teams, CI/CD | Team plan |
| **Infisical** | Open source, dev-friendly | OSS / Cloud |

---

## Environment Variables (Baseline)

### Typed Environment Validation

```typescript
// src/config/env.ts
import { z } from 'zod'

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'staging', 'production']),
  PORT: z.coerce.number().default(3000),

  // Database
  DATABASE_URL: z.string().url(),
  DATABASE_POOL_SIZE: z.coerce.number().default(10),

  // Auth
  JWT_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  SESSION_SECRET: z.string().min(32),

  // External services
  STRIPE_SECRET_KEY: z.string().startsWith('sk_'),
  STRIPE_WEBHOOK_SECRET: z.string().startsWith('whsec_'),
  RESEND_API_KEY: z.string().startsWith('re_'),

  // Encryption
  ENCRYPTION_KEY: z.string().length(64), // 32 bytes hex-encoded

  // Redis
  REDIS_URL: z.string().url(),

  // CORS
  CORS_ORIGINS: z.string().transform((s) => s.split(',')),
})

export const env = envSchema.parse(process.env)
```

### Rules

- **Never hardcode secrets** in source code, config files, or Dockerfiles
- **Never commit .env files** — add to .gitignore
- **Different secrets per environment** — dev, staging, production must have separate credentials
- **Validate at startup** — fail fast if required secrets are missing

---

## Doppler

### Setup

```bash
# Install
brew install dopplerhq/cli/doppler

# Login and configure
doppler login
doppler setup  # Select project and environment

# Run with injected secrets
doppler run -- node dist/index.js

# CI: use service token
export DOPPLER_TOKEN=${{ secrets.DOPPLER_TOKEN }}
doppler run -- npm start
```

### Multi-Environment

```bash
# Set up environments
doppler environments create staging
doppler environments create production

# Set secrets per environment
doppler secrets set DATABASE_URL "postgres://..." --config staging
doppler secrets set DATABASE_URL "postgres://..." --config production
```

---

## HashiCorp Vault

### Dynamic Database Credentials

```typescript
import Vault from 'node-vault'

const vault = Vault({
  endpoint: process.env.VAULT_ADDR,
  token: process.env.VAULT_TOKEN,
})

// Get dynamic database credentials (auto-expire)
async function getDatabaseCredentials() {
  const result = await vault.read('database/creds/my-app-role')
  return {
    username: result.data.username,
    password: result.data.password,
    leaseDuration: result.lease_duration,
    leaseId: result.lease_id,
  }
}

// Renew lease before expiry
async function renewLease(leaseId: string) {
  await vault.write('sys/leases/renew', { lease_id: leaseId, increment: 3600 })
}
```

---

## Rotation Automation

### Zero-Downtime Secret Rotation Pattern

```
1. Generate new secret (key B)
2. Update application to accept BOTH old (key A) AND new (key B)
3. Deploy application with dual-key support
4. Switch primary to new secret (key B)
5. Wait for all sessions/tokens using old key to expire
6. Remove old secret (key A)
7. Deploy application with only new key
```

### JWT Secret Rotation

```typescript
// Support multiple signing keys during rotation
const JWT_KEYS = [
  { kid: 'key-2', secret: process.env.JWT_SECRET_CURRENT },
  { kid: 'key-1', secret: process.env.JWT_SECRET_PREVIOUS },
]

// Sign with current key
function signToken(payload: object): string {
  return jwt.sign(payload, JWT_KEYS[0].secret, {
    algorithm: 'HS256',
    expiresIn: '15m',
    header: { kid: JWT_KEYS[0].kid },
  })
}

// Verify with any valid key
function verifyToken(token: string): JWTPayload {
  const decoded = jwt.decode(token, { complete: true })
  const key = JWT_KEYS.find((k) => k.kid === decoded?.header.kid)
  if (!key) throw new Error('Unknown signing key')
  return jwt.verify(token, key.secret) as JWTPayload
}
```

### Database Password Rotation

```bash
#!/bin/bash
# scripts/rotate-db-password.sh

NEW_PASSWORD=$(openssl rand -base64 32)

# 1. Create new user or update password
psql -c "ALTER USER app_user PASSWORD '${NEW_PASSWORD}'"

# 2. Update secrets manager
doppler secrets set DATABASE_PASSWORD "${NEW_PASSWORD}" --config production

# 3. Rolling restart (zero downtime)
# Application picks up new env vars on restart
kubectl rollout restart deployment/api-server
```

### API Key Rotation

```typescript
// Store API keys with version for graceful rotation
const apiKeys = {
  current: process.env.API_KEY_V2,
  previous: process.env.API_KEY_V1,
}

function validateApiKey(key: string): boolean {
  return key === apiKeys.current || key === apiKeys.previous
}
```

---

## CI/CD Secrets

### GitHub Actions

```yaml
# Use GitHub Secrets (Settings → Secrets → Actions)
jobs:
  deploy:
    steps:
      - name: Deploy
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
          STRIPE_SECRET_KEY: ${{ secrets.STRIPE_SECRET_KEY }}
        run: npm run deploy

      # Or use Doppler
      - name: Deploy with Doppler
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
        run: doppler run -- npm run deploy
```

### Docker Secrets

```yaml
# docker-compose.yml — use secrets, not env vars
services:
  api:
    image: my-app
    secrets:
      - db_password
      - jwt_secret

secrets:
  db_password:
    file: ./secrets/db_password.txt
  jwt_secret:
    file: ./secrets/jwt_secret.txt
```

---

## Emergency Rotation

### When to Emergency Rotate

- Secret committed to git (even if immediately removed)
- Employee with access leaves unexpectedly
- Breach suspected or confirmed
- Third-party reports unauthorized access

### Emergency Procedure

1. Generate new secrets immediately
2. Deploy with new + old keys (dual-key)
3. Invalidate old keys
4. Investigate exposure scope
5. Rotate all secrets that shared the same access
6. Notify affected parties per incident response plan
7. Post-incident review

---

## Crontab Secret Exposure (Common Pitfall)

Secrets hardcoded in crontab entries are visible to any user via `crontab -l` and in process listings via `ps aux`. This is a frequently overlooked exposure vector.

**BAD — Secret visible in crontab and process list:**
```bash
# crontab -e
0 3 * * * curl -s -H "Authorization: Bearer s3cr3t-t0k3n" https://app.com/api/cron/cleanup
```

**GOOD — Script reads secret from env file at runtime:**
```bash
# /root/cron-cleanup.sh (chmod 700, root-only)
#!/bin/bash
SECRET=$(grep '^CRON_SECRET=' /path/to/.env.local | cut -d= -f2)
curl -s -H "Authorization: Bearer $SECRET" https://app.com/api/cron/cleanup > /dev/null 2>&1
```

```bash
# crontab -e — no secrets visible
0 3 * * * /root/cron-cleanup.sh
```

**Key rules:**
- Cron scripts must have `700` permissions (owner-only execute)
- Secrets read from `.env` files at runtime, never inlined
- Rotate the secret if it was previously exposed in crontab

---

## Secrets Checklist

- [ ] All secrets in environment variables or secrets manager
- [ ] .env files in .gitignore
- [ ] No secrets hardcoded in crontab entries (use script files instead)
- [ ] Different secrets per environment (dev/staging/prod)
- [ ] Secrets validated at application startup
- [ ] Rotation schedule defined (90 days recommended)
- [ ] Zero-downtime rotation pattern implemented
- [ ] CI/CD uses encrypted secrets (not plaintext)
- [ ] Secret detection in pre-commit hooks
- [ ] Emergency rotation procedure documented
- [ ] Access to secrets limited by role
- [ ] Secrets audit log (who accessed what, when)

# Authentication, SSO & MFA Reference

This reference covers two distinct authentication environments. Choose the correct path based on where the application runs and who uses it.

---

## Environment Decision Matrix

| Question | Enterprise (Env A) | Consumer/Public (Env B) |
|---|---|---|
| Who are the users? | Employees, contractors, partners | Public users, customers |
| Where does the app run? | Corporate network, Azure/AWS cloud, intranet | Public internet, SaaS |
| Who manages identities? | IT department (Azure AD, Okta, OneLogin) | Your application |
| Who manages passwords? | Identity Provider (IdP) | Your application |
| Who enforces MFA? | Identity Provider | Your application |
| User provisioning | SCIM from IdP directory | Self-registration |
| Example apps | Internal dashboards, admin panels, corporate tools, B2B SaaS | E-commerce, content platforms, social apps, public SaaS |

**Hybrid:** Many B2B SaaS apps support BOTH — local auth for small customers, SSO for enterprise customers. See "Hybrid Architecture" section below.

---

# ENVIRONMENT A: Enterprise / Corporate Auth

## Azure AD / Entra ID Integration (Microsoft Ecosystem)

This is the most common enterprise IdP. If the organization uses Microsoft 365, Teams, or Azure, this is the path.

### Architecture Flow

```
1. User visits your app → app checks for session cookie
2. No session → redirect to Azure AD authorization endpoint
3. User authenticates with Azure AD (MFA enforced by Conditional Access policy)
4. Azure AD redirects back with authorization code
5. Your app exchanges code for tokens (access + ID + refresh)
6. Your app validates ID token, extracts user info + group memberships
7. Your app creates local session, maps Azure AD groups to app roles
8. Session cookie set → user is in
```

### Implementation (Node.js — MSAL)

```bash
pnpm add @azure/msal-node jsonwebtoken
```

```typescript
// src/lib/azure-ad.ts
import { ConfidentialClientApplication } from '@azure/msal-node'
import { env } from '../config/env'

const msalConfig = {
  auth: {
    clientId: env.AZURE_CLIENT_ID,
    authority: `https://login.microsoftonline.com/${env.AZURE_TENANT_ID}`,
    clientSecret: env.AZURE_CLIENT_SECRET,
  },
}

export const msalClient = new ConfidentialClientApplication(msalConfig)

const SCOPES = ['openid', 'profile', 'email', 'User.Read', 'GroupMember.Read.All']
const REDIRECT_URI = `${env.APP_URL}/api/auth/azure/callback`

// Step 1: Generate auth URL
export async function getAuthUrl(state: string) {
  return msalClient.getAuthCodeUrl({
    scopes: SCOPES,
    redirectUri: REDIRECT_URI,
    state,
    prompt: 'select_account',
  })
}

// Step 2: Exchange code for tokens
export async function handleCallback(code: string) {
  const result = await msalClient.acquireTokenByCode({
    code,
    scopes: SCOPES,
    redirectUri: REDIRECT_URI,
  })

  return {
    accessToken: result.accessToken,
    idToken: result.idToken,
    account: result.account,
    // Extract claims from ID token
    email: result.idTokenClaims?.preferred_username || result.idTokenClaims?.email,
    name: result.idTokenClaims?.name,
    oid: result.idTokenClaims?.oid,            // Azure AD Object ID
    groups: result.idTokenClaims?.groups || [], // Group IDs (if configured in token claims)
    roles: result.idTokenClaims?.roles || [],   // App roles (if configured in Azure AD)
  }
}
```

### Route Handlers

```typescript
// src/modules/auth/auth.controller.ts (Enterprise SSO routes)
import { randomBytes } from 'crypto'
import { getAuthUrl, handleCallback } from '../../lib/azure-ad'
import { redis } from '../../lib/redis'

// Initiate SSO
app.get('/api/auth/azure/login', async (req, reply) => {
  const state = randomBytes(16).toString('hex')
  await redis.setex(`oauth-state:${state}`, 300, 'pending')  // 5 min TTL

  const authUrl = await getAuthUrl(state)
  return reply.redirect(authUrl)
})

// SSO Callback
app.get('/api/auth/azure/callback', async (req, reply) => {
  const { code, state, error, error_description } = req.query

  // Handle Azure AD errors
  if (error) {
    logger.warn({ error, error_description }, 'Azure AD auth error')
    return reply.redirect(`${env.FRONTEND_URL}/login?error=sso_failed`)
  }

  // Validate state
  const storedState = await redis.get(`oauth-state:${state}`)
  if (!storedState) throw errors.unauthorized('Invalid or expired OAuth state')
  await redis.del(`oauth-state:${state}`)

  // Exchange code for tokens
  const azureUser = await handleCallback(code)
  if (!azureUser.email) throw errors.unauthorized('No email in Azure AD response')

  // Find or provision user in local database
  let user = await db.user.findUnique({ where: { email: azureUser.email } })

  if (!user) {
    // Auto-provision from Azure AD
    user = await db.user.create({
      data: {
        email: azureUser.email,
        name: azureUser.name || azureUser.email,
        provider: 'azure-ad',
        providerId: azureUser.oid,
        role: mapAzureGroupsToRole(azureUser.groups),  // Map IdP groups to app roles
        emailVerified: true,  // Azure AD already verified the email
      },
    })
    logger.info({ userId: user.id, email: user.email }, 'User auto-provisioned from Azure AD')
  } else {
    // Update role from Azure AD groups on every login (IdP is source of truth)
    const newRole = mapAzureGroupsToRole(azureUser.groups)
    if (user.role !== newRole) {
      await db.user.update({ where: { id: user.id }, data: { role: newRole } })
      logger.info({ userId: user.id, oldRole: user.role, newRole }, 'User role updated from Azure AD')
    }
  }

  // Create session
  const sessionId = randomBytes(32).toString('hex')
  await redis.setex(`session:${sessionId}`, 86400, JSON.stringify({
    userId: user.id, role: user.role, provider: 'azure-ad', loginAt: Date.now(),
  }))

  reply.setCookie('session', sessionId, {
    httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 86400, domain: env.COOKIE_DOMAIN,
  })

  return reply.redirect(`${env.FRONTEND_URL}/dashboard`)
})

// Group-to-role mapping
function mapAzureGroupsToRole(groupIds: string[]): string {
  // Map Azure AD Group Object IDs to application roles
  const GROUP_ROLE_MAP: Record<string, string> = {
    [env.AZURE_ADMIN_GROUP_ID]: 'admin',
    [env.AZURE_EDITOR_GROUP_ID]: 'editor',
    [env.AZURE_VIEWER_GROUP_ID]: 'viewer',
  }

  for (const [groupId, role] of Object.entries(GROUP_ROLE_MAP)) {
    if (groupIds.includes(groupId)) return role
  }
  return 'viewer'  // Default role
}
```

### Azure AD Configuration (Azure Portal)

Required setup in Azure Portal → Azure Active Directory → App registrations:

1. **Register application** — get Client ID and Tenant ID
2. **Add client secret** — Certificates & secrets → New client secret
3. **Configure redirect URIs** — Authentication → Add `https://yourapp.com/api/auth/azure/callback`
4. **API permissions** — Add `User.Read`, `GroupMember.Read.All` (admin consent required for groups)
5. **Token configuration** — Add optional claims: `email`, `groups` (group IDs in token)
6. **App roles** (optional) — Define custom app roles in manifest, assign to users/groups
7. **Conditional Access** — Enforce MFA, device compliance, trusted locations (IT manages this)

### SCIM User Provisioning (Auto-Sync)

For large organizations, auto-sync users from Azure AD to your app:

```typescript
// SCIM 2.0 endpoints your app exposes
// Azure AD calls these automatically when users are created/updated/disabled

app.post('/scim/v2/Users', async (req) => {
  // Azure AD sends user data → create user in your DB
  const { userName, displayName, active } = req.body
  await db.user.upsert({
    where: { email: userName },
    create: { email: userName, name: displayName, provider: 'azure-ad', active },
    update: { name: displayName, active },
  })
})

app.patch('/scim/v2/Users/:id', async (req) => {
  // Azure AD sends updates (disable, role change, name change)
})

app.delete('/scim/v2/Users/:id', async (req) => {
  // Azure AD sends deprovisioning → soft-delete/disable user
  await db.user.update({ where: { providerId: req.params.id }, data: { active: false, deletedAt: new Date() } })
})
```

---

## Generic SAML 2.0 SSO (Okta, OneLogin, PingFederate, ADFS)

For non-Azure IdPs or when customers bring their own IdP.

```bash
pnpm add @node-saml/node-saml
```

```typescript
// Each enterprise customer/tenant gets their own SSO config
interface TenantSSOConfig {
  tenantId: string
  provider: 'saml'
  entryPoint: string       // IdP Sign-On URL
  issuer: string           // Your app's entity ID (SP Entity ID)
  cert: string             // IdP's X.509 signing certificate
  callbackUrl: string      // Your ACS URL
  logoutUrl?: string       // IdP SLO URL
  nameIdFormat?: string    // e.g., 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'
}

// Store per-tenant SSO configs in database
// Admin UI allows enterprise customers to configure their own IdP

app.get('/api/auth/sso/:tenantId', async (req, reply) => {
  const config = await db.ssoConfig.findUnique({ where: { tenantId: req.params.tenantId } })
  if (!config) throw errors.notFound('SSO configuration')

  const saml = new SAML({
    entryPoint: config.entryPoint,
    issuer: config.issuer,
    cert: config.cert,
    callbackUrl: config.callbackUrl,
  })

  const loginUrl = await saml.getAuthorizeUrlAsync('', req.id, {})
  return reply.redirect(loginUrl)
})

app.post('/api/auth/sso/callback', async (req, reply) => {
  const { SAMLResponse } = req.body
  // Validate signature, extract NameID (email), attributes (name, groups)
  // Find/provision user, create session, redirect
})
```

---

## Enterprise Auth: What Your App Does NOT Do

When running behind an enterprise IdP:
- ❌ Store passwords — IdP handles credentials
- ❌ Implement MFA — IdP enforces it via Conditional Access / policies
- ❌ Handle password resets — IdP self-service portal
- ❌ Manage password complexity rules — IdP policy
- ❌ Lock accounts on failed attempts — IdP handles lockout
- ✅ Map IdP users/groups to local roles
- ✅ Manage session lifecycle (create/validate/destroy)
- ✅ Enforce authorization (RBAC/ABAC) within the app
- ✅ Audit log all access and actions
- ✅ Handle token refresh and session expiry

---

# ENVIRONMENT B: Consumer / Public-Facing Auth

## Local Authentication (Email + Password)

### Password Hashing — Argon2id (Non-Negotiable)

```typescript
import { hash, verify } from 'argon2'

export async function hashPassword(password: string): Promise<string> {
  return hash(password, {
    type: 2,            // argon2id
    memoryCost: 65536,  // 64 MB
    timeCost: 3,        // 3 iterations
    parallelism: 4,     // 4 threads
  })
}

export async function verifyPassword(password: string, storedHash: string): Promise<boolean> {
  return verify(storedHash, password)
}
```

### Registration Flow

```typescript
const RegisterSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128).regex(
    /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/,
    'Password must contain uppercase, lowercase, and a number'
  ),
  name: z.string().min(2).max(100),
})

app.post('/api/auth/register', async (req, reply) => {
  const data = RegisterSchema.parse(req.body)

  const existing = await db.user.findUnique({ where: { email: data.email } })
  if (existing) throw errors.conflict('Email already registered')

  const passwordHash = await hashPassword(data.password)
  const user = await db.user.create({
    data: { email: data.email, name: data.name, passwordHash, role: 'user', emailVerified: false },
  })

  // Send verification email
  await sendVerificationEmail(user.email, await generateVerificationToken(user.id))

  logger.info({ userId: user.id }, 'User registered')
  return reply.status(201).send({ message: 'Account created. Check your email to verify.' })
})
```

### Login Flow (with MFA support)

```typescript
app.post('/api/auth/login', async (req, reply) => {
  const { email, password, mfaCode } = LoginSchema.parse(req.body)

  // Check rate limiting / lockout
  const attempts = await redis.get(`login-attempts:${email}`)
  if (Number(attempts) >= 5) {
    const ttl = await redis.ttl(`login-attempts:${email}`)
    throw errors.rateLimit(`Account locked. Try again in ${Math.ceil(ttl / 60)} minutes.`)
  }

  const user = await db.user.findUnique({ where: { email } })
  if (!user || !user.passwordHash) {
    await incrementLoginAttempts(email)
    throw errors.unauthorized('Invalid credentials')
  }

  const validPassword = await verifyPassword(password, user.passwordHash)
  if (!validPassword) {
    await incrementLoginAttempts(email)
    throw errors.unauthorized('Invalid credentials')
  }

  // MFA check
  if (user.mfaEnabled) {
    if (!mfaCode) {
      // First step: password correct, need MFA
      return reply.send({ requiresMFA: true, mfaMethod: user.mfaMethod })
    }
    const mfaValid = verifyTOTP(decrypt(user.mfaSecret), mfaCode)
    if (!mfaValid) {
      // Check recovery codes
      const recoveryValid = await verifyRecoveryCode(user.id, mfaCode)
      if (!recoveryValid) {
        await incrementLoginAttempts(email)
        throw errors.unauthorized('Invalid MFA code')
      }
    }
  }

  // Success — clear attempts, create session
  await redis.del(`login-attempts:${email}`)

  const sessionId = randomBytes(32).toString('hex')
  await redis.setex(`session:${sessionId}`, 86400 * 7, JSON.stringify({
    userId: user.id, role: user.role, provider: 'local', loginAt: Date.now(),
  }))

  reply.setCookie('session', sessionId, {
    httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 86400 * 7, domain: env.COOKIE_DOMAIN,
  })

  logger.info({ userId: user.id }, 'User logged in')
  return reply.send({ user: { id: user.id, email: user.email, name: user.name, role: user.role } })
})

async function incrementLoginAttempts(email: string) {
  const key = `login-attempts:${email}`
  await redis.incr(key)
  await redis.expire(key, 900)  // 15 min progressive lockout
}
```

### Session Management

```typescript
// Validate session (used in auth middleware)
export async function validateSession(sessionId: string) {
  const data = await redis.get(`session:${sessionId}`)
  if (!data) return null

  const session = JSON.parse(data)

  // Check if session is too old (force re-login after 7 days)
  if (Date.now() - session.loginAt > 86400 * 7 * 1000) {
    await redis.del(`session:${sessionId}`)
    return null
  }

  return session
}

// Logout
app.post('/api/auth/logout', async (req, reply) => {
  const sessionId = req.cookies.session
  if (sessionId) await redis.del(`session:${sessionId}`)
  reply.clearCookie('session', { path: '/', domain: env.COOKIE_DOMAIN })
  return reply.send({ success: true })
})

// Logout all sessions (on password change)
app.post('/api/auth/logout-all', async (req, reply) => {
  const sessions = await redis.keys(`session:*`)
  for (const key of sessions) {
    const data = await redis.get(key)
    if (data && JSON.parse(data).userId === req.user.id) {
      await redis.del(key)
    }
  }
  reply.clearCookie('session', { path: '/', domain: env.COOKIE_DOMAIN })
  return reply.send({ success: true })
})
```

---

## OAuth 2.0 Social Login (Consumer Apps)

### Supported Providers

| Provider | Library | Scopes |
|---|---|---|
| Google | arctic | openid, email, profile |
| GitHub | arctic | user:email |
| Apple | arctic | name, email |
| Discord | arctic | identify, email |
| Facebook | arctic | email, public_profile |
| Microsoft (personal) | arctic | openid, email, profile |

### Implementation (arctic library — lightweight, no framework dependency)

```bash
pnpm add arctic
```

```typescript
import { Google, GitHub, Apple, generateState, generateCodeVerifier } from 'arctic'

const google = new Google(env.GOOGLE_CLIENT_ID, env.GOOGLE_CLIENT_SECRET, `${env.APP_URL}/api/auth/oauth/google/callback`)
const github = new GitHub(env.GITHUB_CLIENT_ID, env.GITHUB_CLIENT_SECRET, `${env.APP_URL}/api/auth/oauth/github/callback`)

// Generic OAuth flow factory
function createOAuthRoutes(providerName: string, provider: any, profileFetcher: (accessToken: string) => Promise<{ email: string; name: string; avatar?: string; providerId: string }>) {

  // Initiate
  app.get(`/api/auth/oauth/${providerName}`, async (req, reply) => {
    const state = generateState()
    const codeVerifier = generateCodeVerifier()

    reply.setCookie('oauth_state', state, { httpOnly: true, secure: true, maxAge: 300, path: '/', sameSite: 'lax' })
    reply.setCookie('oauth_verifier', codeVerifier, { httpOnly: true, secure: true, maxAge: 300, path: '/', sameSite: 'lax' })

    const url = provider.createAuthorizationURL(state, codeVerifier, ['openid', 'email', 'profile'])
    return reply.redirect(url.toString())
  })

  // Callback
  app.get(`/api/auth/oauth/${providerName}/callback`, async (req, reply) => {
    const { code, state } = req.query as { code: string; state: string }
    const storedState = req.cookies.oauth_state
    const codeVerifier = req.cookies.oauth_verifier

    if (!state || state !== storedState) throw errors.unauthorized('Invalid OAuth state')

    const tokens = await provider.validateAuthorizationCode(code, codeVerifier)
    const profile = await profileFetcher(tokens.accessToken())

    // Find or create user (link to existing account by email)
    let user = await db.user.findUnique({ where: { email: profile.email } })
    if (!user) {
      user = await db.user.create({
        data: {
          email: profile.email, name: profile.name, avatar: profile.avatar,
          provider: providerName, providerId: profile.providerId,
          emailVerified: true, role: 'user',
        },
      })
    }

    // Create session + set cookie
    const sessionId = await createSession(user)
    setSessionCookie(reply, sessionId)

    // Clear OAuth cookies
    reply.clearCookie('oauth_state', { path: '/' })
    reply.clearCookie('oauth_verifier', { path: '/' })

    return reply.redirect(`${env.FRONTEND_URL}/dashboard`)
  })
}

// Register providers
createOAuthRoutes('google', google, async (token) => {
  const res = await fetch('https://openidconnect.googleapis.com/v1/userinfo', { headers: { Authorization: `Bearer ${token}` } })
  const data = await res.json()
  return { email: data.email, name: data.name, avatar: data.picture, providerId: data.sub }
})

createOAuthRoutes('github', github, async (token) => {
  const [user, emails] = await Promise.all([
    fetch('https://api.github.com/user', { headers: { Authorization: `Bearer ${token}` } }).then(r => r.json()),
    fetch('https://api.github.com/user/emails', { headers: { Authorization: `Bearer ${token}` } }).then(r => r.json()),
  ])
  const primary = emails.find((e: any) => e.primary && e.verified)
  return { email: primary?.email || user.email, name: user.name || user.login, avatar: user.avatar_url, providerId: String(user.id) }
})
```

---

## Application-Managed MFA / 2FA (TOTP — Consumer Apps Only)

In enterprise environments, the IdP handles MFA. This section is for consumer apps that manage their own MFA.

### Setup TOTP

```bash
pnpm add otpauth qrcode
```

```typescript
import { TOTP, Secret } from 'otpauth'
import QRCode from 'qrcode'

// Step 1: User requests MFA setup → generate secret + QR
app.post('/api/auth/mfa/setup', { preHandler: [authGuard, requireReauth] }, async (req, reply) => {
  const secret = new Secret()
  const totp = new TOTP({ issuer: 'YourApp', label: req.user.email, secret, digits: 6, period: 30 })

  const uri = totp.toString()
  const qrCodeDataUrl = await QRCode.toDataURL(uri)

  // Store secret temporarily (not confirmed yet)
  await redis.setex(`mfa-setup:${req.user.id}`, 600, encrypt(secret.base32))

  return reply.send({ qrCode: qrCodeDataUrl, manualEntry: secret.base32 })
})

// Step 2: User confirms with a code from their authenticator app
app.post('/api/auth/mfa/confirm', { preHandler: [authGuard] }, async (req, reply) => {
  const { code } = z.object({ code: z.string().length(6).regex(/^\d+$/) }).parse(req.body)

  const encryptedSecret = await redis.get(`mfa-setup:${req.user.id}`)
  if (!encryptedSecret) throw errors.validation('MFA setup expired. Start over.')

  const secret = decrypt(encryptedSecret)
  const valid = verifyTOTP(secret, code)
  if (!valid) throw errors.unauthorized('Invalid code. Try again.')

  // Generate recovery codes
  const recoveryCodes = generateRecoveryCodes()
  const hashedCodes = await Promise.all(recoveryCodes.map(c => hashRecoveryCode(c)))

  // Save to database
  await db.user.update({
    where: { id: req.user.id },
    data: { mfaEnabled: true, mfaSecret: encrypt(secret), mfaMethod: 'totp' },
  })
  await db.recoveryCode.createMany({
    data: hashedCodes.map(hash => ({ userId: req.user.id, codeHash: hash, used: false })),
  })

  await redis.del(`mfa-setup:${req.user.id}`)

  return reply.send({
    success: true,
    recoveryCodes,  // Show ONCE, user must save them
    message: 'MFA enabled. Save your recovery codes — they will not be shown again.',
  })
})

// Verify TOTP code
function verifyTOTP(secret: string, code: string): boolean {
  const totp = new TOTP({ secret: Secret.fromBase32(secret), digits: 6, period: 30 })
  return totp.validate({ token: code, window: 1 }) !== null
}

// Generate recovery codes
function generateRecoveryCodes(count = 10): string[] {
  return Array.from({ length: count }, () =>
    randomBytes(4).toString('hex').toUpperCase().match(/.{4}/g)!.join('-')
  )
}

// Verify recovery code (single-use)
async function verifyRecoveryCode(userId: string, code: string): Promise<boolean> {
  const stored = await db.recoveryCode.findMany({ where: { userId, used: false } })
  for (const rc of stored) {
    if (await verify(rc.codeHash, code.replace(/-/g, '').toLowerCase())) {
      await db.recoveryCode.update({ where: { id: rc.id }, data: { used: true, usedAt: new Date() } })
      logger.warn({ userId }, 'Recovery code used')
      return true
    }
  }
  return false
}
```

### Disable MFA (requires re-authentication)

```typescript
app.post('/api/auth/mfa/disable', { preHandler: [authGuard, requireReauth] }, async (req, reply) => {
  await db.user.update({ where: { id: req.user.id }, data: { mfaEnabled: false, mfaSecret: null } })
  await db.recoveryCode.deleteMany({ where: { userId: req.user.id } })
  logger.info({ userId: req.user.id }, 'MFA disabled')
  return reply.send({ success: true })
})
```

---

# HYBRID ARCHITECTURE (B2B SaaS — Both Environments)

For B2B SaaS apps where small customers use email+password and enterprise customers use SSO:

```typescript
// Login endpoint determines auth method by email domain
app.post('/api/auth/login', async (req, reply) => {
  const { email } = req.body
  const domain = email.split('@')[1]

  // Check if this domain has SSO configured
  const ssoConfig = await db.ssoConfig.findUnique({ where: { domain } })

  if (ssoConfig) {
    // Enterprise customer → redirect to SSO
    return reply.send({
      ssoRequired: true,
      ssoUrl: `/api/auth/sso/${ssoConfig.tenantId}`,
      message: 'Your organization uses Single Sign-On.',
    })
  }

  // No SSO → proceed with local auth (password + optional MFA)
  return handleLocalLogin(req, reply)
})
```

### Tenant-Aware SSO Configuration

```typescript
// Admin API for enterprise customers to configure their SSO
app.post('/api/admin/sso/configure', { preHandler: [authGuard, requireRole('tenant-admin')] }, async (req, reply) => {
  const data = SSOConfigSchema.parse(req.body)

  await db.ssoConfig.upsert({
    where: { tenantId: req.user.tenantId },
    create: {
      tenantId: req.user.tenantId,
      domain: data.domain,            // e.g., 'company.com'
      provider: data.provider,         // 'saml' or 'oidc'
      entryPoint: data.entryPoint,
      cert: data.cert,
      issuer: `${env.APP_URL}/saml/metadata/${req.user.tenantId}`,
      callbackUrl: `${env.APP_URL}/api/auth/sso/${req.user.tenantId}/callback`,
    },
    update: { entryPoint: data.entryPoint, cert: data.cert },
  })
})
```

---

## RBAC Implementation (Both Environments)

```typescript
// Permission definitions
const PERMISSIONS = {
  admin:   ['*'],  // Wildcard = everything
  editor:  ['users:read', 'content:read', 'content:write', 'content:delete', 'settings:read'],
  user:    ['users:read:own', 'content:read', 'content:write:own'],
  viewer:  ['content:read'],
} as const

function hasPermission(role: string, required: string): boolean {
  const perms = PERMISSIONS[role as keyof typeof PERMISSIONS]
  if (!perms) return false
  if (perms.includes('*')) return true
  return perms.some(p => p === required || (p.endsWith(':own') && required.startsWith(p.replace(':own', ''))))
}

// Middleware
export function requirePermission(permission: string) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    if (!req.user || !hasPermission(req.user.role, permission)) {
      logger.warn({ userId: req.user?.id, permission, role: req.user?.role }, 'Authorization denied')
      throw errors.forbidden()
    }
  }
}

// Enterprise: roles come from IdP group mapping
// Consumer: roles stored in database, managed via admin UI
```

---

## Security Checklist

### Enterprise Auth (Env A)
- [ ] SSO redirect validates state parameter
- [ ] SAML assertions are signature-verified with IdP certificate
- [ ] Azure AD tokens validated (issuer, audience, expiry, signature)
- [ ] IdP groups mapped to application roles (not hardcoded per-user)
- [ ] SCIM endpoints authenticated with bearer token
- [ ] Session created after SSO callback, not during
- [ ] No local passwords stored for SSO users
- [ ] Conditional Access policies enforced at IdP (MFA, device compliance)
- [ ] Audit log: SSO login, role mapping changes, provisioning events

### Consumer Auth (Env B)
- [ ] Passwords hashed with Argon2id (64MB / 3 iterations / 4 parallelism)
- [ ] Account lockout after 5 failures (15 min progressive delay)
- [ ] TOTP secrets encrypted at rest (AES-256-GCM or similar)
- [ ] Recovery codes hashed (bcrypt), single-use, generated during MFA setup
- [ ] Email verification required before full account access
- [ ] Password reset tokens: single-use, 1 hour expiry, invalidate on use
- [ ] OAuth state parameter + PKCE code verifier validated on callback
- [ ] Re-authentication required for: password change, email change, MFA disable, billing
- [ ] All sessions invalidated on password change
- [ ] Audit log: login, failed attempts, MFA changes, password resets

### Both Environments
- [ ] Sessions in httpOnly, Secure, SameSite cookies — never localStorage
- [ ] CORS strict origin allowlist
- [ ] Rate limiting on all auth endpoints (stricter: 5/min login, 3/min password reset)
- [ ] All auth events logged with: userId, IP, userAgent, timestamp, result

---

## NextAuth v5 (next-auth@beta) — Next.js App Router

NextAuth v5 is a major rewrite for App Router compatibility. Key differences from v4: single `auth.ts` config file, JWT/session callbacks for role extension, `auth()` function for server-side session access.

### Setup

```bash
pnpm add next-auth@beta @auth/prisma-adapter
```

### Configuration

```typescript
// src/lib/auth.ts
import NextAuth from "next-auth";
import Credentials from "next-auth/providers/credentials";
import { verify } from "argon2";
import { prisma } from "@/lib/prisma";

export const { handlers, signIn, signOut, auth } = NextAuth({
  providers: [
    Credentials({
      credentials: { email: {}, password: {} },
      authorize: async (credentials) => {
        const user = await prisma.user.findUnique({
          where: { email: credentials.email as string },
        });
        if (!user?.passwordHash) return null;
        const valid = await verify(user.passwordHash, credentials.password as string);
        if (!valid) return null;
        return { id: user.id, email: user.email, name: user.name, role: user.role, orgId: user.orgId };
      },
    }),
  ],
  session: { strategy: "jwt" },
  callbacks: {
    jwt({ token, user }) {
      if (user) { token.role = user.role; token.orgId = user.orgId; }
      return token;
    },
    session({ session, token }) {
      if (session.user) { session.user.role = token.role; session.user.orgId = token.orgId; }
      return session;
    },
  },
  pages: { signIn: "/login" },
});
```

### Route Handler & Middleware

```typescript
// src/app/api/auth/[...nextauth]/route.ts
export { handlers as GET, handlers as POST } from "@/lib/auth";

// middleware.ts — protects pages AND API routes
export { auth as middleware } from "@/lib/auth";
export const config = {
  matcher: ["/overview/:path*", "/batches/:path*", "/api/((?!auth).*)"],
};
```

### Server-Side Auth Guards

```typescript
// src/lib/auth-guard.ts
import { auth } from "@/lib/auth";
import { redirect } from "next/navigation";

export async function requireAuth() {
  const session = await auth();
  if (!session) redirect("/login");
  return session;
}

export async function requireRole(role: string) {
  const session = await requireAuth();
  if (session.user?.role !== role) redirect("/unauthorized");
  return session;
}
```

### Key Gotchas

- **JWT strategy required for Credentials provider** — database sessions don't work with Credentials.
- **Extend JWT/session types** via `next-auth.d.ts` module augmentation for custom fields (role, orgId).
- **Edge middleware** — `auth()` works in middleware but Prisma doesn't run on Edge. Keep DB queries in API routes/server components.
- **v5 env vars renamed**: `AUTH_SECRET` (was `NEXTAUTH_SECRET`) and `AUTH_URL` (was `NEXTAUTH_URL`). Both names work in v5 but `AUTH_*` is the canonical form.
- **Reverse proxy deployments require `AUTH_TRUST_HOST=true`** — without it, NextAuth rejects requests because the host header doesn't match. Add to `.env`: `AUTH_TRUST_HOST=true`. Required for nginx → container setups.

### Next.js 15 — `useSearchParams()` Requires `<Suspense>`

In Next.js 15, calling `useSearchParams()` in a client component that is NOT wrapped in `<Suspense>` causes a **build error**, not just a warning.

The pattern for login pages that read `?error=` or `?callbackUrl=`:

```tsx
// ❌ Build fails in Next.js 15 — useSearchParams without Suspense boundary
export default function LoginPage() {
  const searchParams = useSearchParams(); // throws at build time
  ...
}

// ✅ Correct — extract the hook into a child, wrap in Suspense
"use client";
import { Suspense } from "react";
import { useSearchParams } from "next/navigation";

function LoginForm() {
  const searchParams = useSearchParams();
  const callbackUrl = searchParams.get("callbackUrl") ?? "/";
  const reason = searchParams.get("reason"); // e.g. "timeout"
  
  return (
    <>
      {reason === "timeout" && (
        <p aria-live="polite" style={{ /* amber warning banner */ }}>
          Your session expired due to inactivity. Please sign in again.
        </p>
      )}
      {/* form here */}
    </>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}
```

**Rule:** Any component that calls `useSearchParams()`, `usePathname()`, or other navigation hooks that depend on request-time data MUST be wrapped in `<Suspense>`. Extract an inner component and wrap the outer page in `<Suspense fallback={null}>` or a loading skeleton.

---

## Standalone Admin Auth (Separate from Main Auth)

When building an internal admin dashboard that must NOT share the main application's auth system (e.g., NextAuth, Clerk, Supabase Auth), use a standalone cookie-based auth with its own credentials.

### When to Use

- Admin panel accessible at a hidden URL (e.g., `/admin`) — not linked from navigation
- Credentials stored as env vars (not in the user database)
- Single-instance or low-traffic admin use (in-memory session store acceptable)
- Admin route must not interfere with the main auth system

### Implementation Pattern

```typescript
import crypto from 'crypto'

// Env-based credentials — never hardcoded
const ADMIN_USERNAME = process.env.ADMIN_USERNAME!
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD!
const SESSION_SECRET = process.env.ADMIN_SESSION_SECRET || process.env.NEXTAUTH_SECRET!

// In-memory session store (acceptable for single-instance VPS)
const activeSessions = new Map<string, { expiresAt: number }>()

// HMAC-based constant-time comparison — prevents length-leak timing attacks
function constantTimeEqual(a: string, b: string): boolean {
  const ha = crypto.createHmac('sha256', SESSION_SECRET).update(a).digest()
  const hb = crypto.createHmac('sha256', SESSION_SECRET).update(b).digest()
  return crypto.timingSafeEqual(ha, hb)
}

// Random session token — revocable, unlike static HMAC tokens
function createSession(): string {
  const token = crypto.randomBytes(32).toString('hex')
  activeSessions.set(token, { expiresAt: Date.now() + 8 * 60 * 60 * 1000 })
  // Purge expired sessions on each creation
  for (const [key, s] of activeSessions) {
    if (s.expiresAt < Date.now()) activeSessions.delete(key)
  }
  return token
}

function validateSession(token: string): boolean {
  const session = activeSessions.get(token)
  if (!session || session.expiresAt < Date.now()) {
    if (session) activeSessions.delete(token)
    return false
  }
  return true
}
```

### Security Checklist for Standalone Admin

- [ ] Credentials in env vars, never hardcoded
- [ ] HMAC constant-time comparison for credential checks (no length leak)
- [ ] Random session tokens (not static HMAC), stored in Map with expiry
- [ ] HttpOnly + Secure + SameSite=strict cookie
- [ ] Rate limiting on login endpoint (5/min/IP)
- [ ] `robots: noindex, nofollow` meta tag on admin pages
- [ ] Admin layout has no `<meta>` for robots indexing
- [ ] Not linked from any navigation, footer, or sitemap
- [ ] Email/PII masked in admin dashboard responses (e.g., `j***@example.com`)

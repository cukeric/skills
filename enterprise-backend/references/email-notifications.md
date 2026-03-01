# Email & Notifications Reference

## Provider Selection

| Provider | Best For | Pricing Model | Rate Limits |
|---|---|---|---|
| **Resend** | Modern APIs, React Email templates, developer-first | Per email | 100/day free, 50k/mo at $20 |
| **SendGrid** | High volume, established, SMTP + API | Per email | 100/day free, 100k/mo at $20 |
| **AWS SES** | Highest volume, lowest cost, AWS ecosystem | Per 1000 emails | $0.10/1000, no free tier after 12mo |
| **Postmark** | Transactional only, best deliverability | Per email | 100/mo free |

**Default recommendation: Resend** for new projects (best DX, React Email support). **AWS SES** for high volume or existing AWS infrastructure.

---

## Resend Integration

```bash
pnpm add resend
```

```typescript
// src/lib/email.ts
import { Resend } from 'resend'
import { env } from '../config/env'
import { logger } from './logger'

const resend = new Resend(env.RESEND_API_KEY)

interface SendEmailOptions {
  to: string | string[]
  subject: string
  html: string
  text?: string            // Plain text fallback (always include)
  replyTo?: string
  tags?: { name: string; value: string }[]
}

export async function sendEmail({ to, subject, html, text, replyTo, tags }: SendEmailOptions) {
  try {
    const result = await resend.emails.send({
      from: `${env.APP_NAME} <noreply@${env.EMAIL_DOMAIN}>`,
      to: Array.isArray(to) ? to : [to],
      subject,
      html,
      text: text || stripHtml(html),
      reply_to: replyTo,
      tags,
    })

    logger.info({ emailId: result.data?.id, to, subject }, 'Email sent')
    return result
  } catch (error) {
    logger.error({ error, to, subject }, 'Email send failed')
    throw error
  }
}

function stripHtml(html: string): string {
  return html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim()
}
```

### SendGrid Alternative

```bash
pnpm add @sendgrid/mail
```

```typescript
import sgMail from '@sendgrid/mail'
sgMail.setApiKey(env.SENDGRID_API_KEY)

export async function sendEmail({ to, subject, html, text }: SendEmailOptions) {
  await sgMail.send({
    to, from: { email: `noreply@${env.EMAIL_DOMAIN}`, name: env.APP_NAME },
    subject, html, text: text || stripHtml(html),
  })
}
```

### AWS SES Alternative

```bash
pnpm add @aws-sdk/client-sesv2
```

```typescript
import { SESv2Client, SendEmailCommand } from '@aws-sdk/client-sesv2'
const ses = new SESv2Client({ region: env.AWS_REGION })

export async function sendEmail({ to, subject, html, text }: SendEmailOptions) {
  await ses.send(new SendEmailCommand({
    FromEmailAddress: `${env.APP_NAME} <noreply@${env.EMAIL_DOMAIN}>`,
    Destination: { ToAddresses: Array.isArray(to) ? to : [to] },
    Content: {
      Simple: {
        Subject: { Data: subject },
        Body: { Html: { Data: html }, Text: { Data: text || stripHtml(html) } },
      },
    },
  }))
}
```

---

## Email Templates

### Template System Architecture

```
src/
├── emails/
│   ├── components/          # Reusable email components
│   │   ├── header.ts
│   │   ├── footer.ts
│   │   ├── button.ts
│   │   └── layout.ts
│   ├── templates/
│   │   ├── welcome.ts
│   │   ├── verify-email.ts
│   │   ├── password-reset.ts
│   │   ├── payment-receipt.ts
│   │   ├── payment-failed.ts
│   │   ├── subscription-renewed.ts
│   │   ├── subscription-canceled.ts
│   │   ├── team-invite.ts
│   │   └── mfa-enabled.ts
│   └── render.ts            # Template renderer
```

### Template Pattern (Framework-Agnostic HTML)

```typescript
// src/emails/components/layout.ts
export function emailLayout(content: string, options: { preheader?: string } = {}) {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title></title>
  ${options.preheader ? `<span style="display:none;max-height:0;overflow:hidden">${options.preheader}</span>` : ''}
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 0; background: #f8f6f3; color: #2d2a26; }
    .container { max-width: 560px; margin: 0 auto; padding: 40px 20px; }
    .card { background: #ffffff; border-radius: 12px; padding: 32px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
    .button { display: inline-block; padding: 12px 24px; background: #c07a45; color: #ffffff; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 14px; }
    .text-secondary { color: #6b6560; font-size: 14px; }
    .text-small { color: #9e9790; font-size: 12px; }
    .divider { border: none; border-top: 1px solid #eee; margin: 24px 0; }
    h1 { font-size: 22px; font-weight: 700; margin: 0 0 8px; }
    p { line-height: 1.6; margin: 0 0 16px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="card">
      ${content}
    </div>
    <div style="text-align:center;padding:24px 0;">
      <p class="text-small">&copy; ${new Date().getFullYear()} ${process.env.APP_NAME}. All rights reserved.</p>
      <p class="text-small">
        <a href="${process.env.FRONTEND_URL}/unsubscribe" style="color:#9e9790;">Unsubscribe</a> ·
        <a href="${process.env.FRONTEND_URL}/privacy" style="color:#9e9790;">Privacy Policy</a>
      </p>
    </div>
  </div>
</body>
</html>`
}

// src/emails/components/button.ts
export function emailButton(text: string, url: string) {
  return `<a href="${url}" class="button" style="display:inline-block;padding:12px 24px;background:#c07a45;color:#ffffff;text-decoration:none;border-radius:8px;font-weight:600;">${text}</a>`
}
```

### Template Implementations

```typescript
// src/emails/templates/verify-email.ts
import { emailLayout } from '../components/layout'
import { emailButton } from '../components/button'

export function verifyEmailTemplate(data: { name: string; verifyUrl: string }) {
  return emailLayout(`
    <h1>Verify your email</h1>
    <p>Hi ${data.name},</p>
    <p>Thanks for signing up. Please verify your email address to get started.</p>
    <div style="text-align:center;margin:24px 0;">
      ${emailButton('Verify Email', data.verifyUrl)}
    </div>
    <p class="text-secondary">This link expires in 24 hours. If you didn't create an account, you can safely ignore this email.</p>
  `, { preheader: 'Verify your email to get started' })
}

// src/emails/templates/password-reset.ts
export function passwordResetTemplate(data: { name: string; resetUrl: string }) {
  return emailLayout(`
    <h1>Reset your password</h1>
    <p>Hi ${data.name},</p>
    <p>We received a request to reset your password. Click the button below to choose a new one.</p>
    <div style="text-align:center;margin:24px 0;">
      ${emailButton('Reset Password', data.resetUrl)}
    </div>
    <p class="text-secondary">This link expires in 1 hour. If you didn't request this, no action is needed — your password is safe.</p>
  `, { preheader: 'Password reset requested' })
}

// src/emails/templates/payment-receipt.ts
export function paymentReceiptTemplate(data: { name: string; amount: string; currency: string; date: string; invoiceUrl: string }) {
  return emailLayout(`
    <h1>Payment received</h1>
    <p>Hi ${data.name},</p>
    <p>We've received your payment of <strong>${data.currency} ${data.amount}</strong> on ${data.date}.</p>
    <hr class="divider" />
    <div style="text-align:center;margin:16px 0;">
      ${emailButton('View Invoice', data.invoiceUrl)}
    </div>
    <p class="text-secondary">Thank you for your business.</p>
  `, { preheader: `Payment of ${data.currency} ${data.amount} received` })
}

// src/emails/templates/payment-failed.ts
export function paymentFailedTemplate(data: { name: string; amount: string; currency: string; updateUrl: string }) {
  return emailLayout(`
    <h1>Payment failed</h1>
    <p>Hi ${data.name},</p>
    <p>We were unable to process your payment of <strong>${data.currency} ${data.amount}</strong>. Please update your payment method to avoid service interruption.</p>
    <div style="text-align:center;margin:24px 0;">
      ${emailButton('Update Payment Method', data.updateUrl)}
    </div>
    <p class="text-secondary">We'll retry the payment in 3 days. If you need help, contact support.</p>
  `, { preheader: 'Action required: payment failed' })
}
```

### Template Renderer (send via queue)

```typescript
// src/emails/render.ts
import { verifyEmailTemplate } from './templates/verify-email'
import { passwordResetTemplate } from './templates/password-reset'
import { paymentReceiptTemplate } from './templates/payment-receipt'
import { paymentFailedTemplate } from './templates/payment-failed'

const TEMPLATES = {
  'verify-email': verifyEmailTemplate,
  'password-reset': passwordResetTemplate,
  'payment-receipt': paymentReceiptTemplate,
  'payment-failed': paymentFailedTemplate,
} as const

type TemplateName = keyof typeof TEMPLATES

export function renderEmail(template: TemplateName, data: Record<string, unknown>): { subject: string; html: string } {
  const SUBJECTS: Record<TemplateName, string> = {
    'verify-email': 'Verify your email address',
    'password-reset': 'Reset your password',
    'payment-receipt': 'Payment receipt',
    'payment-failed': 'Action required: payment failed',
  }

  return {
    subject: SUBJECTS[template],
    html: TEMPLATES[template](data as any),
  }
}

// Usage from any service (sends via background queue)
import { queueEmail } from '../lib/queue'

await queueEmail(user.email, 'verify-email', { name: user.name, verifyUrl: `${env.FRONTEND_URL}/verify?token=${token}` })
```

---

## Push Notifications (Optional)

### Web Push (Service Worker)

```bash
pnpm add web-push
```

```typescript
import webPush from 'web-push'

webPush.setVapidDetails('mailto:admin@yourapp.com', env.VAPID_PUBLIC_KEY, env.VAPID_PRIVATE_KEY)

export async function sendPushNotification(subscription: PushSubscription, payload: { title: string; body: string; url?: string }) {
  try {
    await webPush.sendNotification(subscription, JSON.stringify(payload))
  } catch (error: any) {
    if (error.statusCode === 410) {
      // Subscription expired — remove from database
      await db.pushSubscription.delete({ where: { endpoint: subscription.endpoint } })
    }
    throw error
  }
}
```

---

## Notification Preferences

```typescript
// Users can control which notifications they receive
const NotificationPrefsSchema = z.object({
  email: z.object({
    marketing: z.boolean().default(false),
    productUpdates: z.boolean().default(true),
    securityAlerts: z.boolean().default(true),   // Cannot be disabled
    paymentAlerts: z.boolean().default(true),     // Cannot be disabled
  }),
  push: z.object({
    enabled: z.boolean().default(false),
    mentions: z.boolean().default(true),
    comments: z.boolean().default(true),
  }),
})

// Before sending any notification:
async function shouldSendNotification(userId: string, type: string, channel: 'email' | 'push'): Promise<boolean> {
  // Security and payment alerts always send
  if (['security-alert', 'payment-failed', 'payment-receipt'].includes(type)) return true

  const prefs = await db.notificationPrefs.findUnique({ where: { userId } })
  if (!prefs) return true  // Default: send

  return prefs[channel]?.[type] !== false
}
```

---

## Deliverability Checklist

- [ ] SPF record configured for sending domain
- [ ] DKIM signing enabled (provider configures this)
- [ ] DMARC policy published (start with `p=none`, monitor, then enforce)
- [ ] Return-Path / bounce address configured
- [ ] Unsubscribe link in every non-transactional email (CAN-SPAM)
- [ ] List-Unsubscribe header on marketing emails
- [ ] Plain text version included alongside HTML
- [ ] Sender address verified with provider
- [ ] Bounce and complaint handling configured
- [ ] Send rate within provider limits (use queue to throttle)

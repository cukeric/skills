# Nginx Reverse Proxy & SSL/TLS Reference

## Installation

```bash
apt install -y nginx certbot python3-certbot-nginx

# Enable and start
systemctl enable nginx
systemctl start nginx
```

---

## Reverse Proxy Configuration

### Single Application

```nginx
# /etc/nginx/sites-available/myapp.conf
server {
    listen 80;
    server_name myapp.com www.myapp.com;

    # Redirect all HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name myapp.com www.myapp.com;

    # SSL certificates (managed by Certbot)
    ssl_certificate /etc/letsencrypt/live/myapp.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myapp.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

    # Proxy to application
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Buffering
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 16k;
    }

    # Health check endpoint (no rate limiting, no logging)
    location = /health {
        proxy_pass http://127.0.0.1:3000/health;
        access_log off;
    }

    # Static assets (if served by nginx directly)
    location /static/ {
        alias /home/deploy/apps/myapp/public/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;

    # Request limits
    client_max_body_size 10M;
    client_body_timeout 30s;
    client_header_timeout 30s;
}
```

### Enable Site

```bash
ln -s /etc/nginx/sites-available/myapp.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default   # Remove default site
nginx -t                                  # Test configuration
systemctl reload nginx
```

---

## WebSocket Proxy

```nginx
# WebSocket connections need special handling
location /ws {
    proxy_pass http://127.0.0.1:3000/ws;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Longer timeouts for persistent connections
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
}
```

---

## SSE (Server-Sent Events) Proxy

```nginx
location /api/events {
    proxy_pass http://127.0.0.1:3000/api/events;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Critical: disable buffering for SSE
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 86400s;

    # Disable gzip for SSE
    gzip off;
}
```

---

## Rate Limiting at Proxy Level

```nginx
# Define rate limit zones (in http block or top of server block)
# /etc/nginx/conf.d/rate-limits.conf
limit_req_zone $binary_remote_addr zone=api:10m rate=30r/s;
limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/m;
limit_req_zone $binary_remote_addr zone=general:10m rate=60r/s;

# Apply to locations
location /api/auth/ {
    limit_req zone=auth burst=3 nodelay;
    limit_req_status 429;
    proxy_pass http://127.0.0.1:3000;
}

location /api/ {
    limit_req zone=api burst=20 nodelay;
    limit_req_status 429;
    proxy_pass http://127.0.0.1:3000;
}
```

---

## SSL Certificate (Let's Encrypt)

### Initial Setup

```bash
# Obtain certificate (nginx plugin handles config automatically)
certbot --nginx -d myapp.com -d www.myapp.com --non-interactive --agree-tos -m admin@myapp.com

# Verify auto-renewal
certbot renew --dry-run

# Auto-renewal is installed as a systemd timer
systemctl status certbot.timer
```

### Manual Renewal (if needed)

```bash
certbot renew
systemctl reload nginx
```

### Wildcard Certificate (for subdomains)

```bash
# Requires DNS challenge (not HTTP)
certbot certonly --manual --preferred-challenges dns -d "*.myapp.com" -d "myapp.com"
# Follow prompts to add DNS TXT record
```

---

## Multiple Applications on One Server

```nginx
# App 1: Main application
server {
    listen 443 ssl http2;
    server_name myapp.com;
    ssl_certificate /etc/letsencrypt/live/myapp.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myapp.com/privkey.pem;
    location / { proxy_pass http://127.0.0.1:3000; }
}

# App 2: Admin panel
server {
    listen 443 ssl http2;
    server_name admin.myapp.com;
    ssl_certificate /etc/letsencrypt/live/admin.myapp.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/admin.myapp.com/privkey.pem;
    location / { proxy_pass http://127.0.0.1:3001; }
}

# App 3: API
server {
    listen 443 ssl http2;
    server_name api.myapp.com;
    ssl_certificate /etc/letsencrypt/live/api.myapp.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.myapp.com/privkey.pem;
    location / { proxy_pass http://127.0.0.1:3002; }
}
```

---

## Performance Tuning

```nginx
# /etc/nginx/nginx.conf — top-level settings
worker_processes auto;                    # Match CPU cores
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}

http {
    # Connection keep-alive
    keepalive_timeout 65;
    keepalive_requests 100;

    # File serving optimization
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    # Buffer sizes
    client_body_buffer_size 16k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;

    # Logging
    access_log /var/log/nginx/access.log combined buffer=512k flush=1m;
    error_log /var/log/nginx/error.log warn;
}
```

---

## Testing & Verification

```bash
# Test config syntax
nginx -t

# Test SSL configuration (should be A+)
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=myapp.com

# Test security headers
curl -I https://myapp.com

# Expected headers:
# Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
# X-Content-Type-Options: nosniff
# X-Frame-Options: SAMEORIGIN
```

---

## Checklist

- [ ] HTTP → HTTPS redirect on all domains
- [ ] TLS 1.2+ only, modern cipher suite
- [ ] HSTS header with long max-age
- [ ] Security headers (X-Content-Type-Options, X-Frame-Options, Referrer-Policy)
- [ ] Let's Encrypt certificate with auto-renewal verified
- [ ] WebSocket proxy configured (if using WebSockets)
- [ ] SSE proxy with buffering disabled (if using SSE)
- [ ] Rate limiting on auth and API endpoints
- [ ] Gzip compression enabled
- [ ] Static assets served with long cache headers
- [ ] client_max_body_size set appropriately
- [ ] SSL Labs rating A or A+

# Secure Static Site — Terraform Template

Production-ready, security-hardened static site hosting on AWS. Deploy a React, Vue, or any SPA with CloudFront, WAF, HTTPS enforcement, and a full suite of security response headers — all provisioned as code.

Optionally proxies `/api/*` traffic to an API Gateway backend.

Built by a cleared AWS Security Specialty engineer with hands-on experience on classified DoD networks.

**[Download full package on Gumroad → $29](https://kenflowe.gumroad.com/l/ktnjgw)**

---

## What This Deploys

```
                    ┌─────────────────────────────────────────┐
  Internet  ──────► │  WAF (OWASP rules + rate limiting)      │
                    └────────────────┬────────────────────────┘
                                     │
                    ┌────────────────▼────────────────────────┐
                    │  CloudFront (HTTP→HTTPS redirect)        │
                    │  Security headers: HSTS, CSP, X-Frame   │
                    │  TLSv1.2 minimum, HTTP/2+3 enabled       │
                    └──────┬─────────────────┬────────────────┘
                           │                 │ /api/* (optional)
              ┌────────────▼──────┐   ┌──────▼──────────────┐
              │  S3 (private)     │   │  API Gateway        │
              │  CloudFront OAC   │   │  (your backend)     │
              │  AES-256 encrypt  │   └─────────────────────┘
              └───────────────────┘
                           │
              ┌────────────▼──────────────────────────────────┐
              │  Route 53 — apex + www DNS records             │
              │  ACM Certificate — auto DNS validation         │
              └───────────────────────────────────────────────┘
                           │
              ┌────────────▼──────────────────────────────────┐
              │  S3 access logs + CloudFront access logs       │
              └───────────────────────────────────────────────┘
```

---

## Security Controls Satisfied (NIST SP 800-53 Rev 5)

| Control | Family | What Implements It |
|---------|--------|--------------------|
| AC-3 | Access Enforcement | CloudFront OAC — only CloudFront can read S3 objects |
| AC-4 | Information Flow | CORS locked to your domain only |
| AU-2 | Audit Events | S3 access logging + CloudFront access logging enabled |
| SC-5 | Denial of Service Protection | WAF rate limiting per IP |
| SC-7 | Boundary Protection | WAF filters malicious requests at the edge |
| SC-8 | Transmission Confidentiality | HTTPS enforced, HTTP redirected, TLSv1.2 minimum |
| SC-12 | Cryptographic Key Management | ACM manages TLS certificate lifecycle |
| SC-28 | Protection at Rest | S3 server-side encryption AES-256 |
| SI-2 | Flaw Remediation | ACM auto-renews certificates |
| SI-3 | Malicious Code Protection | WAF OWASP + known bad inputs managed rules |
| SI-10 | Information Input Validation | Content-Security-Policy blocks XSS, clickjacking |

**Bonus security headers applied at CloudFront edge:**
- `Strict-Transport-Security` (HSTS with preload)
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Content-Security-Policy` (configurable)

---

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with appropriate permissions
- Domain already registered and a hosted zone exists in Route 53
- `aws_region` must be `us-east-1` (CloudFront ACM requirement)

---

## Usage

**1. Configure**

```bash
git clone <repo>
cd secure-static-site
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
project_name = "myapp"
environment  = "prod"
domain_name  = "myapp.com"
```

**2. Deploy infrastructure**

```bash
terraform init
terraform apply
```

**3. Upload your site**

```bash
# Build your frontend
npm run build

# Sync to S3
aws s3 sync ./dist s3://$(terraform output -raw frontend_bucket_name) --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

**4. Visit your site**

DNS propagation takes 1-5 minutes. Use the `cloudfront_url` output immediately, or wait for your domain to resolve.

---

## With an API Backend

If you have a backend API, set `api_gateway_url` and all `/api/*` traffic is proxied through CloudFront to your API Gateway — same domain, no CORS issues:

```hcl
api_gateway_url = "https://abc123.execute-api.us-east-1.amazonaws.com"
```

Pairs directly with the **Secure Serverless App Stack** template.

---

## Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `project_name` | required | Prefix for all resource names |
| `environment` | `"prod"` | Deployment environment |
| `aws_region` | `"us-east-1"` | Must be us-east-1 for CloudFront ACM |
| `domain_name` | required | Root domain in Route 53 |
| `api_gateway_url` | `""` | Optional API backend URL |
| `waf_rate_limit` | `2000` | Requests per IP per 5 min before block |
| `price_class` | `"PriceClass_100"` | CloudFront edge location coverage |
| `log_retention_days` | `30` | Log retention in days |
| `content_security_policy` | `""` | Override default CSP header |

---

## Outputs

| Output | Description |
|--------|-------------|
| `cloudfront_url` | CloudFront URL (available immediately) |
| `website_url` | Your domain URL |
| `frontend_bucket_name` | S3 bucket — upload build artifacts here |
| `cloudfront_distribution_id` | For cache invalidations in CI/CD |
| `waf_web_acl_arn` | WAF ARN |

---

## Estimated Monthly Cost

| Service | Estimated Cost |
|---------|---------------|
| S3 storage | ~$0.023/GB |
| CloudFront | ~$0.0085/GB transfer (US/EU) |
| WAF | ~$5/month base + $1/million requests |
| ACM Certificate | Free |
| Route 53 | $0.50/hosted zone/month |

**Typical small site: $5-8/month**

---

## Pairing With Other Templates

- **Secure Serverless App Stack** — adds Lambda + API Gateway + DynamoDB backend
- **AWS Security Baseline** — adds GuardDuty, CloudTrail, and AWS Config across your account

---

## License

MIT — use freely in commercial and personal projects.

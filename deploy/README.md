# theotroom.co.uk hosting (Terraform)

Infrastructure for The OT Room website on AWS:

| URL | Serves | Origin |
|---|---|---|
| `https://www.theotroom.co.uk` | production site (canonical) | `the-ot-room-live` bucket, via the prod CloudFront distribution |
| `https://theotroom.co.uk` | 301 → `https://www.theotroom.co.uk` | (CloudFront function on the prod distribution) |
| `https://test.theotroom.co.uk` | test / staging site | `the-ot-room-test` bucket, via the test CloudFront distribution |

> The site is authored with `www` as its canonical host (the `canonical`/`og:url` tags, `sitemap.xml`
> and `robots.txt` all use `www.theotroom.co.uk`), so `www` is primary and the bare apex redirects to
> it. Both hostnames are aliases on the production distribution and both resolve in Route 53; the
> redirect is done by the shared CloudFront function.

Each bucket is **private** and fronted by CloudFront with an ACM certificate, so every page is served
over HTTPS. Buckets are never public; CloudFront reaches them via Origin Access Control (OAC). This is
the same shape used for the Benzene sites.

Deploy flow: **push to `main` → test** (`.github/workflows/deploy-site.yml`), then **manual promote
→ live** (`.github/workflows/promote-site.yml`, an S3 `test → live` copy + prod invalidation).

## One-time setup

Run these from `deploy/` with AWS credentials that can create S3 / CloudFront / ACM / Route 53.

### 1. Create the hosted zone first, to learn the nameservers

The ACM certificate is DNS-validated in the new Route 53 zone, but those records only resolve once
GoDaddy points at Route 53 — a chicken-and-egg. So apply the zone alone first:

```bash
terraform init
terraform apply -target=aws_route53_zone.this
terraform output nameservers
```

### 2. Point GoDaddy at Route 53 (one-time)

In GoDaddy → **theotroom.co.uk → DNS → Nameservers → Change → "I'll use my own nameservers"**, enter
the four `nameservers` from the output. **If GoDaddy shows DNSSEC as enabled, turn it off first** —
moving nameservers with stale DNSSEC keys breaks resolution. Propagation is usually minutes, up to a
few hours.

### 3. Apply the rest

Once the nameservers have switched (check with `dig NS theotroom.co.uk`), apply everything. The ACM
validation step will now complete:

```bash
terraform apply
terraform output
```

### 4. Wire the GitHub Actions variables

Both workflows sync the test **and** live buckets (the promote job copies test → live), so the
credentials and bucket/distribution identifiers are shared. Set them **at the repository level** —
**repository → Settings → Secrets and variables → Actions**, on the *Repository* tab (not inside an
environment) — so both the test and production jobs can read them without duplicating anything:

**Variables** (Repository → Variables)

| Variable | Value (from `terraform output`) |
|---|---|
| `AWS_ACCESS_KEY_ID` | the CI IAM user's access key id |
| `WEBSITE_AWS_REGION` | `eu-west-2` (or your chosen region) |
| `WEBSITE_TEST_BUCKET` | `test_bucket` |
| `WEBSITE_LIVE_BUCKET` | `live_bucket` |
| `WEBSITE_TEST_DISTRIBUTION_ID` | `test_distribution_id` |
| `WEBSITE_LIVE_DISTRIBUTION_ID` | `live_distribution_id` |

**Secrets** (Repository → Secrets)

| Secret | Value |
|---|---|
| `AWS_SECRET_ACCESS_KEY` | the CI IAM user's secret access key |

### 4b. Create the environments (and the production approval gate)

Under **repository → Settings → Environments**, create two:

- **`test`** — no protection rules needed. The `Deploy Site (test)` job runs under it and records each
  deploy against it.
- **`production`** — the `Promote Site (test → live)` job runs under this one. Add a protection rule
  **Required reviewers** and list yourself (and anyone else who should sign off). With that in place,
  every promote run **pauses and waits for a manual approval** before it copies anything to the live
  bucket — that is the approval gate. Optionally also restrict the environment's deployment branches
  to `main`.

Because the credentials live at the repository level (step 4), you do **not** need to add any
variables or secrets inside these environments — they exist purely to record deployments and to carry
the production approval gate. (Environment-scoped values would override the repository ones if you
ever need per-environment differences.)

### 5. First deploy, then promote

- Push to `main` (or run **Actions → Deploy Site (test) → Run workflow**) → publishes to
  `https://test.theotroom.co.uk`.
- Review it, then run **Actions → Promote Site (test → live)**, typing `promote` to confirm. The run
  **waits for an approval** on the `production` environment; approve it (**Review deployments →
  Approve and deploy**) and it copies test to `https://www.theotroom.co.uk`.

## CI credentials — required IAM permissions

The static CI credentials need to sync both buckets and invalidate both distributions. Attach a
policy like this to that IAM user (tighten the CloudFront resource ARN to the two distributions if
you prefer):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::the-ot-room-test", "arn:aws:s3:::the-ot-room-live"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::the-ot-room-test/*", "arn:aws:s3:::the-ot-room-live/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["cloudfront:CreateInvalidation"],
      "Resource": "*"
    }
  ]
}
```

## Notes

- **`.co.uk` vs plain S3.** A `.co.uk` domain could technically serve over plain HTTP from an S3
  website endpoint, but that's HTTP-only and unencrypted. The CloudFront + private-bucket + ACM shape
  here gives HTTPS on every URL and a CDN in front, which is what you want for a real site.
- **State.** This stack uses local Terraform state by default. For a shared/CI-managed setup, add a
  remote backend (e.g. an S3 backend).
- **404s until first deploy.** The buckets start empty, so the site returns 404 until step 5 runs.
- **Cost.** Route 53 hosted zone (~$0.50/mo) + CloudFront/S3 usage (pennies at this traffic).
  `price_class` defaults to `PriceClass_100` (NA+EU) to keep it cheap; set `PriceClass_All` for
  global edge coverage.
- **Branded 404.** Both distributions map an origin 403 (a missing object behind OAC) to `/404.html`,
  which ships from `site/404.html`.

# theotroom.co.uk hosting (Terraform)

Infrastructure for The OT Room website on AWS:

| URL | Serves | Origin |
|---|---|---|
| `https://theotroom.co.uk` | production site | `the-ot-room-live` bucket, via the prod CloudFront distribution |
| `https://www.theotroom.co.uk` | 301 → `https://theotroom.co.uk` | (CloudFront function on the prod distribution) |
| `https://test.theotroom.co.uk` | test / staging site | `the-ot-room-test` bucket, via the test CloudFront distribution |

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

Set these under **repository → Settings → Secrets and variables → Actions**, in the `test`
environment (create it if it doesn't exist):

**Variables**

| Variable | Value (from `terraform output`) |
|---|---|
| `AWS_ACCESS_KEY_ID` | the CI IAM user's access key id |
| `WEBSITE_AWS_REGION` | `eu-west-2` (or your chosen region) |
| `WEBSITE_TEST_BUCKET` | `test_bucket` |
| `WEBSITE_LIVE_BUCKET` | `live_bucket` |
| `WEBSITE_TEST_DISTRIBUTION_ID` | `test_distribution_id` |
| `WEBSITE_LIVE_DISTRIBUTION_ID` | `live_distribution_id` |

**Secrets**

| Secret | Value |
|---|---|
| `AWS_SECRET_ACCESS_KEY` | the CI IAM user's secret access key |

> Both workflows run under the `test` environment because that is where the shared CI credentials
> live. If you want an approval gate before anything reaches production, create a separate
> `production` environment with **required reviewers**, move the promote job to
> `environment: production`, and add the same AWS variables/secret there.

### 5. First deploy, then promote

- Push to `main` (or run **Actions → Deploy Site (test) → Run workflow**) → publishes to
  `https://test.theotroom.co.uk`.
- Review it, then run **Actions → Promote Site (test → live)**, typing `promote` to confirm →
  copies test to `https://theotroom.co.uk`.

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

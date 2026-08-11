# Manual setup guide

Everything in this repo is code: the site (`site/`), the infrastructure (`deploy/`) and the two
deploy workflows (`.github/workflows/`). But a few things can only be done by hand, with your own
AWS and GoDaddy credentials. This guide walks through all of them, in order, once.

**End state:** the site auto-deploys to `https://test.theotroom.co.uk` on every push to `main`, and a
manual, approval-gated action promotes it to `https://www.theotroom.co.uk`.

You do these steps **once**. Roughly 30–60 minutes of work, plus DNS propagation waiting time.

---

## What you need before you start

- [ ] An **AWS account** (root or an admin IAM user you can log into).
- [ ] Access to the **GoDaddy** account that owns `theotroom.co.uk`.
- [ ] **Admin** on the GitHub repo `daniellepelley/the-ot-room` (to add secrets and environments).
- [ ] **Terraform** ≥ 1.5 and the **AWS CLI** installed locally.
      - macOS: `brew install terraform awscli`
      - or see the Terraform / AWS CLI install docs for your OS.

---

## Step 1 — Create AWS credentials

You need **two** sets of AWS credentials, for two different jobs:

| Credential | Used by | Scope |
|---|---|---|
| **Admin / Terraform** | you, running `terraform` locally | broad — creates S3, CloudFront, ACM, Route 53 |
| **CI deploy user** | GitHub Actions | narrow — only sync the buckets + invalidate the CDNs |

### 1a. Credentials to run Terraform

The simplest path is to use an admin user you already have. If you'd rather create a dedicated one:

1. AWS Console → **IAM → Users → Create user**, name it e.g. `theotroom-terraform`.
2. **Attach policies directly** and add these four AWS-managed policies:
   `AmazonS3FullAccess`, `CloudFrontFullAccess`, `AmazonRoute53FullAccess`,
   `AWSCertificateManagerFullAccess`.
3. After creating the user → **Security credentials → Create access key → Command Line Interface (CLI)**.
   Copy the **Access key ID** and **Secret access key**.
4. Configure the CLI locally with them:
   ```bash
   aws configure
   # AWS Access Key ID:     <paste>
   # AWS Secret Access Key: <paste>
   # Default region name:   eu-west-2
   # Default output format:  json
   ```
   (The ACM certificate is created in `us-east-1` automatically by the Terraform config — you don't
   need to change your default region for that.)

> You can delete this Terraform user (or detach its policies) after the one-time setup if you like —
> day-to-day deploys use the narrow CI user below, not this one.

### 1b. Create the CI deploy user (for GitHub Actions)

This user only needs to copy files into the two buckets and invalidate the two CloudFront
distributions.

1. IAM → **Users → Create user**, name it e.g. `theotroom-ci`.
2. **Attach policies directly → Create policy**, choose the **JSON** tab, and paste:
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
   Name it `theotroom-ci-deploy` and attach it to the `theotroom-ci` user.
3. `theotroom-ci` → **Security credentials → Create access key → Third-party service / CLI**. Copy the
   **Access key ID** and **Secret access key** — you'll paste these into GitHub in Step 6.

> If you change the bucket names in `deploy/variables.tf`, update the ARNs in this policy to match.

---

## Step 2 — Create the Route 53 hosted zone (to learn the nameservers)

The TLS certificate is validated via DNS records in a new Route 53 zone, but those records only
resolve once GoDaddy points at Route 53 — a chicken-and-egg. So create the zone **first**, on its own:

```bash
cd deploy
terraform init
terraform apply -target=aws_route53_zone.this
terraform output nameservers
```

That prints **four nameservers**, like:

```
ns-123.awsdns-45.com
ns-678.awsdns-90.net
ns-1011.awsdns-12.org
ns-1314.awsdns-15.co.uk
```

Keep them handy for the next step.

---

## Step 3 — Point GoDaddy at Route 53

This hands DNS for `theotroom.co.uk` over to AWS.

1. Log in to **GoDaddy → My Products → theotroom.co.uk → DNS** (or **Domain Settings → Manage DNS**).
2. Find **Nameservers** → **Change** → **I'll use my own nameservers** (sometimes "Enter my own
   nameservers").
3. Enter the **four** nameservers from Step 2. Remove any GoDaddy defaults so only these four remain.
   (Leave off any trailing dot GoDaddy doesn't want.)
4. **DNSSEC:** if GoDaddy shows DNSSEC as **enabled**, turn it **off** first. Moving nameservers while
   stale DNSSEC keys are published breaks resolution.
5. Save.

Propagation is usually minutes, occasionally a few hours. Check from your machine:

```bash
dig NS theotroom.co.uk +short
```

When that returns the four `awsdns` nameservers (not GoDaddy's), you're ready for the next step.

---

## Step 4 — Apply the rest of the infrastructure

Now that DNS resolves through Route 53, the certificate validation can complete. From `deploy/`:

```bash
terraform apply
```

Review the plan and confirm. This creates: the ACM certificate (+ validation), the two S3 buckets,
the two CloudFront distributions, the shared router function, the bucket policies, and the DNS records
for apex, `www` and `test`. CloudFront distributions take a few minutes to deploy.

Then print the values you'll need for GitHub:

```bash
terraform output
```

You'll get `test_bucket`, `live_bucket`, `test_distribution_id`, `live_distribution_id`, and the URLs.

---

## Step 5 — (reference) what Terraform just built

| URL | Serves |
|---|---|
| `https://www.theotroom.co.uk` | production (canonical) |
| `https://theotroom.co.uk` | 301 → `www` |
| `https://test.theotroom.co.uk` | test / staging |

The buckets are **private**; CloudFront reads them over HTTPS via Origin Access Control. They start
**empty**, so every URL returns 404 until the first deploy (Step 8).

---

## Step 6 — Add the GitHub repository variables and secret

These let the workflows authenticate to AWS and know which buckets/distributions to use. Set them at
the **repository** level (not inside an environment), because both the test and promote jobs need
them.

GitHub → repo → **Settings → Secrets and variables → Actions**.

**Variables tab → New repository variable** (create each):

| Name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | the `theotroom-ci` **access key id** (from Step 1b) |
| `WEBSITE_AWS_REGION` | `eu-west-2` |
| `WEBSITE_TEST_BUCKET` | `terraform output test_bucket` → `the-ot-room-test` |
| `WEBSITE_LIVE_BUCKET` | `terraform output live_bucket` → `the-ot-room-live` |
| `WEBSITE_TEST_DISTRIBUTION_ID` | `terraform output test_distribution_id` |
| `WEBSITE_LIVE_DISTRIBUTION_ID` | `terraform output live_distribution_id` |

**Secrets tab → New repository secret:**

| Name | Value |
|---|---|
| `AWS_SECRET_ACCESS_KEY` | the `theotroom-ci` **secret access key** (from Step 1b) |

> The access key **id** is stored as a variable and the **secret** as a secret — that matches how the
> workflows read them (`vars.AWS_ACCESS_KEY_ID` and `secrets.AWS_SECRET_ACCESS_KEY`). An access key id
> is not sensitive on its own; the secret is.

---

## Step 7 — Create the GitHub environments (and the production approval gate)

GitHub → repo → **Settings → Environments**.

1. **New environment → `test`.** No protection rules needed — the deploy job just records against it.
2. **New environment → `production`.** Add the protection rule **Required reviewers** and add
   **yourself** (and anyone else who should sign off). Optionally set **Deployment branches → Selected
   branches → `main`**.

With required reviewers on `production`, every promote run **pauses and waits for your approval**
before it copies anything to the live bucket. That's the approval gate.

You do **not** add any variables or secrets inside these environments — the credentials live at the
repository level (Step 6).

---

## Step 8 — First deploy to test

The workflows are already in the repo. Get the site onto `main`:

- If you're merging the setup branch: open and merge the pull request for
  `claude/ot-room-deployment-setup-ey5i97` into `main`.
- Any push to `main` that touches `site/` runs **Deploy Site (test)** automatically. You can also run
  it by hand: repo → **Actions → Deploy Site (test) → Run workflow**.

When it finishes, open **https://test.theotroom.co.uk** and check the site. (First load can lag a
minute while CloudFront settles and the DNS record is cached.)

---

## Step 9 — Promote to production

1. Repo → **Actions → Promote Site (test → live) → Run workflow**.
2. In the **confirm** box type `promote` and run it.
3. The run **stops at an approval prompt** on the `production` environment. Click **Review
   deployments → Approve and deploy**.
4. It copies the exact bytes from the test bucket to the live bucket and invalidates the production
   CDN. Check **https://www.theotroom.co.uk**, and that **https://theotroom.co.uk** redirects to it.

That's the whole loop: **push → test → approve → live.**

---

## Verifying it all works

```bash
# DNS points at AWS
dig NS theotroom.co.uk +short

# Apex redirects to www (expect 301 -> https://www.theotroom.co.uk/)
curl -sI https://theotroom.co.uk | grep -i location

# All three hostnames serve over HTTPS
curl -sI https://www.theotroom.co.uk   | head -1
curl -sI https://test.theotroom.co.uk  | head -1
```

---

## Troubleshooting

- **Certificate won't validate / `terraform apply` hangs on ACM.** DNS hasn't propagated to Route 53
  yet. Confirm `dig NS theotroom.co.uk +short` shows the `awsdns` servers, then re-run `terraform
  apply`. Also double-check DNSSEC is off at GoDaddy.
- **404 on every page.** Expected until the first deploy (buckets start empty). Run Step 8.
- **403 / AccessDenied on a page that should exist.** The object isn't in the bucket, or the deploy
  didn't run — check the **Deploy Site (test)** run logs.
- **Workflow fails at the AWS step.** The CI keys are wrong or missing, or the `WEBSITE_*` variables
  don't match the `terraform output` values. Re-check Step 6.
- **Promote didn't wait for approval.** The `production` environment has no required reviewers, or the
  job isn't targeting it — confirm Step 7 and that `promote-site.yml` says `environment: production`.
- **Old content still showing after a deploy.** CloudFront caches; the workflows invalidate
  automatically, but a hard refresh (or a minute's wait) may be needed.

---

## Costs

Very low for a small site:

- Route 53 hosted zone: ~**$0.50/month** + a few pennies per million queries.
- CloudFront + S3: **pennies** at this traffic. `price_class` defaults to `PriceClass_100` (North
  America + Europe) to keep egress cheap; set `PriceClass_All` in `deploy/variables.tf` for global
  edge coverage if ever needed.
- ACM certificate: **free**.

---

## Maintenance notes

- **Rotating the CI keys.** Create a new access key for `theotroom-ci`, update the GitHub
  variable/secret (Step 6), then delete the old key in IAM.
- **Changing bucket names or region.** Edit `deploy/variables.tf`, `terraform apply`, update the CI
  IAM policy ARNs (Step 1b) and the GitHub variables (Step 6).
- **Terraform state.** This stack uses local state by default (a `terraform.tfstate` file in
  `deploy/`, git-ignored). Keep it safe — it's how Terraform tracks what it created. For a
  team/shared setup, configure a remote backend (e.g. an S3 backend).

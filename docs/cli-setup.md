# Setup with the CLI — no local install (AWS CloudShell)

You don't need Terraform (or anything else) installed on your computer. **AWS CloudShell** is a
terminal that runs inside the AWS Console in your browser, with the AWS CLI already installed and
**your login's credentials already loaded**. Everything below runs there.

> Open it: sign in to the [AWS Console](https://console.aws.amazon.com/), then click the
> **`>_` CloudShell** icon in the top navigation bar (or search "CloudShell"). Pick region
> **Europe (London) eu-west-2** in the top-right first.

There are two ways to build the infrastructure. Both run in CloudShell; pick one:

- **Path B — one script, no clone** (recommended): upload the single self-contained
  `deploy/cloudshell-provision.sh` and run it. No git, no Terraform. Best when you can't clone the
  private repo.
- **Path A — the repo's Terraform**: reuses the tested `deploy/*.tf`. Needs the repo cloned (with a
  token, since it's private) and a one-time Terraform install.

The steps around them — GoDaddy, GitHub — are identical.

---

> **This repo is private**, so `git clone` in CloudShell fails without a token. You don't need to
> clone at all for **Path B** (recommended) — it runs from a single self-contained script you upload.
> Only **Path A** needs the repo files.

---

## Path B — one script, no clone, no Terraform (recommended)

`deploy/cloudshell-provision.sh` is self-contained (the CloudFront function code is embedded in it),
so it needs nothing else from the repo. Get it into CloudShell one of two ways:

- **Upload it:** in CloudShell, **Actions → Upload file**, and choose `cloudshell-provision.sh`.
- **Or paste it:** run `cat > cloudshell-provision.sh` in CloudShell, paste the file's contents,
  press Ctrl-D.

It runs in two passes because DNS has to move to Route 53 before the certificate can validate:

```bash
# Pass 1 — create the hosted zone and print the nameservers:
bash cloudshell-provision.sh zone
```

→ Now do the **[GoDaddy step](#point-godaddy-at-route-53-both-paths)** below, wait for it, then:

```bash
# Pass 2 — cert, buckets, CloudFront, policies, DNS records:
bash cloudshell-provision.sh rest
```

The script prints the `WEBSITE_*` values for GitHub at the end. (Pass 2 waits for the certificate to
validate; if it times out, the GoDaddy switch hasn't propagated yet — wait and re-run
`bash cloudshell-provision.sh rest`.)

Skip Path A and continue at **[GitHub setup](#wire-up-github-both-paths)**.

---

## Path A — Terraform in CloudShell

Terraform needs the repo's `deploy/` files. Clone with a **fine-grained personal access token** (GitHub
→ Settings → Developer settings → Personal access tokens, read access to this repo):

```bash
git clone https://YOUR_TOKEN@github.com/daniellepelley/the-ot-room.git
cd the-ot-room
```

Install Terraform once (CloudShell is Amazon Linux 2023; this drops the binary in your home dir, which
persists):

```bash
cd ~
TERRAFORM_VERSION=1.9.8
curl -fsSLo tf.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
unzip -o tf.zip terraform -d ~/.local/bin
terraform -version        # should print v1.9.8
```

Then run it against the repo:

```bash
cd ~/the-ot-room/deploy
terraform init

# Pass 1 — create just the hosted zone, to learn the nameservers:
terraform apply -target=aws_route53_zone.this
terraform output nameservers
```

→ Now do the **[GoDaddy step](#point-godaddy-at-route-53-both-paths)** below, wait for it, then:

```bash
terraform apply          # builds everything else; completes once DNS has moved
terraform output         # prints the bucket + distribution values for GitHub
```

---

## Point GoDaddy at Route 53 (both paths)

Pass 1 (either path) prints four nameservers like `ns-123.awsdns-45.com`.

1. **GoDaddy → My Products → theotroom.co.uk → DNS** (or **Manage DNS**).
2. **Nameservers → Change → I'll use my own nameservers.**
3. Enter the **four** nameservers from pass 1; remove any GoDaddy defaults.
4. If **DNSSEC** is shown as enabled, **turn it off first** (moving nameservers with stale DNSSEC keys
   breaks resolution).
5. Save. Then check from CloudShell until it returns the `awsdns` servers:
   ```bash
   dig NS theotroom.co.uk +short
   ```
   Usually minutes, occasionally a few hours. Once it shows the AWS nameservers, run pass 2.

---

## Wire up GitHub (both paths)

You need a small **CI user** for GitHub Actions to deploy with (separate from your console login, which
CloudShell used to build the infra). Create it in CloudShell:

```bash
aws iam create-user --user-name theotroom-ci

cat > /tmp/ci-policy.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::the-ot-room-test", "arn:aws:s3:::the-ot-room-live"] },
    { "Effect": "Allow", "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::the-ot-room-test/*", "arn:aws:s3:::the-ot-room-live/*"] },
    { "Effect": "Allow", "Action": ["cloudfront:CreateInvalidation"], "Resource": "*" }
  ]
}
JSON

aws iam put-user-policy --user-name theotroom-ci \
  --policy-name theotroom-ci-deploy --policy-document file:///tmp/ci-policy.json

aws iam create-access-key --user-name theotroom-ci --output table
```

That last command prints an **AccessKeyId** and **SecretAccessKey** — copy them now (the secret is
shown only once).

### Repository variables and secret

GitHub → repo → **Settings → Secrets and variables → Actions**, at the **repository** level:

**Variables** (from your `terraform output` / the script summary):

| Variable | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | the `theotroom-ci` AccessKeyId |
| `WEBSITE_AWS_REGION` | `eu-west-2` |
| `WEBSITE_TEST_BUCKET` | `the-ot-room-test` |
| `WEBSITE_LIVE_BUCKET` | `the-ot-room-live` |
| `WEBSITE_TEST_DISTRIBUTION_ID` | (test distribution id) |
| `WEBSITE_LIVE_DISTRIBUTION_ID` | (live distribution id) |

**Secrets:**

| Secret | Value |
|---|---|
| `AWS_SECRET_ACCESS_KEY` | the `theotroom-ci` SecretAccessKey |

### Environments (the production approval gate)

GitHub → repo → **Settings → Environments**:

- **`test`** — create it, no rules needed.
- **`production`** — create it, add **Required reviewers** → yourself. That makes every promote run
  pause for your approval before it touches the live site.

---

## Deploy, then promote

1. Merge the setup branch into `main` (or push any change under `site/`). **Actions → Deploy Site
   (test)** runs and publishes to **https://test.theotroom.co.uk**.
2. Review it there.
3. **Actions → Promote Site (test → live) → Run workflow**, type `promote`. The run stops for approval
   on the `production` environment → **Review deployments → Approve and deploy**. It goes live at
   **https://www.theotroom.co.uk** (and `theotroom.co.uk` redirects there).

---

## Verify

```bash
dig NS theotroom.co.uk +short                                   # AWS nameservers
curl -sI https://theotroom.co.uk | grep -i location             # 301 -> https://www.theotroom.co.uk/
curl -sI https://www.theotroom.co.uk  | head -1                 # 200
curl -sI https://test.theotroom.co.uk | head -1                 # 200
```

Full IAM/console detail, troubleshooting, and costs are in
[`docs/manual-setup.md`](manual-setup.md). The infrastructure reference is in
[`deploy/README.md`](../deploy/README.md).

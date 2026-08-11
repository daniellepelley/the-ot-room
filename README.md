# The OT Room

The website for The OT Room — Amy's independent paediatric occupational therapy practice. A static
site hosted on AWS (S3 + CloudFront + Route 53), with a test environment and a production environment
and a one-click promotion between them.

## Layout

```
site/                       the static website (this is what gets deployed)
  index.html                home page
  reading-room.html         The Reading Room
  404.html                  not-found page
  robots.txt, sitemap.xml   SEO
  assets/                   photos and icons
deploy/                     Terraform for S3 + CloudFront + Route 53 (see deploy/README.md)
docs/site.md                the site's own authoring & design-system guide
.github/workflows/
  deploy-site.yml           push to main  ->  publishes site/ to test.theotroom.co.uk
  promote-site.yml          manual        ->  copies test bucket -> live (www.theotroom.co.uk)
```

## Environments

| Environment | URL | Bucket | Updated by |
|---|---|---|---|
| Test | https://test.theotroom.co.uk | `the-ot-room-test` | every push to `main` |
| Production | https://www.theotroom.co.uk | `the-ot-room-live` | manual **Promote** action |

`www.theotroom.co.uk` is the canonical production host; the bare apex `theotroom.co.uk` 301-redirects
to it. Both sites are private S3 buckets served over HTTPS through CloudFront (with a Route 53 hosted
zone whose nameservers live at GoDaddy).

## First-time setup

The one-time manual setup — AWS credentials, provisioning the infrastructure, pointing GoDaddy at
Route 53, and the GitHub variables/environments — has two walkthroughs:

- **[`docs/cli-setup.md`](docs/cli-setup.md)** — do it all in the browser with **AWS CloudShell**,
  nothing to install locally (either the repo's Terraform, or the pure-CLI
  `deploy/cloudshell-provision.sh` script). Start here if you don't have Terraform installed.
- **[`docs/manual-setup.md`](docs/manual-setup.md)** — the same steps assuming a local Terraform +
  AWS CLI, with fuller IAM/console detail, troubleshooting and costs.

The infrastructure reference (what gets built and why) is in [`deploy/README.md`](deploy/README.md).

## Editing the site

Edit the files in `site/` and push to `main`; that publishes to test automatically. The site is plain
HTML with no build step. Its design system and editing notes (colours, type, the handwriting-guide
rules, photo aspect ratios) are documented in [`docs/site.md`](docs/site.md).

## Publishing

1. **Push to `main`** — the changed `site/` is deployed to **test** automatically.
2. **Review** it at https://test.theotroom.co.uk.
3. **Promote** — run **Actions → Promote Site (test → live)** and type `promote` to confirm. The run
   targets the protected `production` environment, so it **pauses for a manual approval**; once
   approved it copies the exact bytes from the test bucket to the production bucket and invalidates the
   production CDN, so what you reviewed on test is what goes live at https://www.theotroom.co.uk.

   > The approval gate is the `production` environment's **Required reviewers** rule — set it up under
   > **Settings → Environments → production** (see [`deploy/README.md`](deploy/README.md), step 4b).

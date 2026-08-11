# The OT Room

The website for The OT Room — a static site hosted on AWS (S3 + CloudFront + Route 53), with a test
environment and a production environment and a one-click promotion between them.

## Layout

```
site/                       the static website (this is what gets deployed)
deploy/                     Terraform for S3 + CloudFront + Route 53 (see deploy/README.md)
.github/workflows/
  deploy-site.yml           push to main  ->  publishes site/ to test.theotroom.co.uk
  promote-site.yml          manual        ->  copies test bucket -> live (theotroom.co.uk)
```

## Environments

| Environment | URL | Bucket | Updated by |
|---|---|---|---|
| Test | https://test.theotroom.co.uk | `the-ot-room-test` | every push to `main` |
| Production | https://theotroom.co.uk | `the-ot-room-live` | manual **Promote** action |

Both sites are private S3 buckets served over HTTPS through CloudFront (with a Route 53 hosted zone
whose nameservers live at GoDaddy). Full infrastructure and one-time setup steps — including pointing
GoDaddy at Route 53 — are in [`deploy/README.md`](deploy/README.md).

## Adding the site content

The `site/` folder currently holds a placeholder. Replace it with the real site: unzip your site
archive and copy its files into `site/` (so the home page is `site/index.html`), then commit and push
to `main`. That triggers **Deploy Site (test)**, which publishes to https://test.theotroom.co.uk.

## Publishing

1. **Push to `main`** — the changed `site/` is deployed to **test** automatically.
2. **Review** it at https://test.theotroom.co.uk.
3. **Promote** — run **Actions → Promote Site (test → live)** and type `promote` to confirm. It copies
   the exact bytes from the test bucket to the production bucket and invalidates the production CDN, so
   what you reviewed on test is what goes live at https://theotroom.co.uk.

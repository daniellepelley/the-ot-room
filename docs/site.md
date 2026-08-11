# The OT Room

Static site for **The OT Room** — Amy's independent paediatric occupational therapy
practice. Two pages, no build step, no dependencies. Fonts load from Google Fonts;
everything else is in this repo.

## Structure

```
index.html          home page
reading-room.html   The Reading Room
404.html            not-found page
assets/             photos and icons
CNAME               custom domain for GitHub Pages
robots.txt          allows all, points at the sitemap
sitemap.xml         two URLs
```

## Running it locally

Open `index.html` in a browser, or serve the folder if you want correct
absolute paths:

```bash
python3 -m http.server 8000
# http://localhost:8000
```

## Deploying to GitHub Pages

```bash
git init
git add .
git commit -m "The OT Room website"
git branch -M main
git remote add origin git@github.com:<user>/theotroom.git
git push -u origin main
```

Then in the repo: **Settings → Pages → Source: Deploy from a branch**, branch
`main`, folder `/ (root)`.

The `CNAME` file sets the custom domain to `www.theotroom.co.uk`. At the DNS
provider add:

| Type | Name | Value |
|---|---|---|
| CNAME | `www` | `<user>.github.io` |
| A | `@` | `185.199.108.153` |
| A | `@` | `185.199.109.153` |
| A | `@` | `185.199.110.153` |
| A | `@` | `185.199.111.153` |

The four A records let the apex domain redirect to `www`. Tick **Enforce HTTPS**
once the certificate has been issued — usually within the hour.

If the site is hosted anywhere other than `www.theotroom.co.uk`, delete `CNAME`
and update the absolute URLs in the `<link rel="canonical">` and `og:` tags in
each page, plus `sitemap.xml` and `robots.txt`.

## Design system

Do not introduce new colours or typefaces.

| Token | Hex | Use |
|---|---|---|
| Petrol | `#12383F` | Primary text, headings, baseline rules |
| Petrol 70 | `#456A70` | Secondary text |
| Petrol 25 | `#A9BFC1` | Faint text, footers |
| Paper | `#EFF2EF` | Page background |
| Mist | `#DDE8E3` | Panels and notes |
| Ochre | `#B87A1C` | The `@`, kickers, accents, dashed midline |
| Rule | `#C8D5D2` | Hairlines, ascender line |

Type is **Fraunces** (display, weight 600, `font-variation-settings:'SOFT' 0,'WONK' 0`)
and **Karla** (body). Both OFL-licensed.

### The handwriting guide

The signature element. Three rules behind the wordmark and every section title,
positioned from Fraunces' own metrics (ascender `0.750em`, x-height `0.460em`,
descender `0.240em`, font ascent `0.980em`):

- **ascender line** — 1px `--rule`, at the top of `h` and `l`
- **midline** — 1px dashed `--ochre` at 55% opacity, on the top of the lowercase
- **baseline** — 2px `--petrol`, through the foot of the letters

For a `line-height:1.15` heading the baseline sits at `0.935em` from the top of
the element, the midline at `0.475em`, the ascender line at `0.185em`. If the
line-height changes, recompute rather than nudging by eye — the offsets are
derived, not chosen.

Below 700px, headings that wrap drop the ascender and midline and keep the
baseline only; a single ruled line cannot sit correctly under two lines of text.

## Editing

- **Photos** — replace the files in `assets/`, keeping the same names and aspect
  ratios (hero 5:4, portrait 4:5, reading room 3:2).
- **Fees** are deliberately not published. The site says "available on request";
  the fee sheet is a separate PDF sent on enquiry.
- **The Reading Room** has three strands marked *coming soon*. Entries go in the
  `.strands` grid in `reading-room.html`.

## Still to do

- Real content for The Reading Room
- Decide whether a contact form is wanted (needs a service such as Formspree or
  Netlify Forms — GitHub Pages is static and cannot process one)
- Analytics, if any

## Credits

HCPC registered OT093958. RCOT registered.

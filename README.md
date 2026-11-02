# vicaro-public

The public face of Vicaro: the landing page, the download artifacts, the installer
script, and the helper's web UI bundle. Nothing here is application source, and the
app itself is closed source.

## What is served

| Path | What | Notes |
|---|---|---|
| `/` | landing page (`index.html`) | product copy, install one-liner |
| `/install.sh` | macOS installer | copied verbatim from the app repo's `deploy/macos/install.sh` |
| `/downloads/` | release tarballs + `.sha256`, extension zip | what `install.sh` fetches |
| `/privacy.html` | privacy policy | the URL pasted into the Chrome Web Store dashboard |
| `/webui/<version>/` | helper web UI bundle + manifest | hash-pinned; also mirrored by jsDelivr over this repo so UI traffic costs nothing |

## The web UI bundle

The helper ships its UI embedded in the binary, and can also load a signed bundle
from here. That exists so UI, store and connector screens ship without a helper
release, and without waiting on Chrome Web Store review (which only gates the
extension, not the helper).

Rules:

- **Version-pinned directories, immutable.** Publish `/webui/0.4.2/`, never edit
  `0.4.0` after the fact.
- **Manifest lists every file with its sha256**, plus a signature over the manifest.
  The helper verifies both and falls back to its embedded copy on any mismatch.
- **The helper never executes remote code.** The bundle is UI: HTML, CSS, JS in a
  browser window it served, with the same loopback API and token as the embedded
  copy.

## Deploying

GitHub Actions deploys to Netlify on push to `main`, **but only when something
Netlify serves has changed** (`index.html`, `install.sh`, `privacy.html`, the icons,
or `downloads/`). README, workflow and doc edits deploy nothing. `workflow_dispatch`
is there for a manual deploy.

Deploys are serialised (`concurrency: netlify-production`), so two pushes cannot
overlap and pay for two builds.

> **Credits.** Every production deploy and every byte served is billed. Nine pushes
> in two days is nine deploys, and a single macOS install pulls a 38 MB tarball
> through Netlify. That is what drains the allowance, not the 11 KB landing page.

### Getting the binaries off Netlify

Two moves, in order of value:

1. **Downloads to GitHub Releases.** Free, CDN-backed, no size limit.
   `install.sh` reads `VICARO_BASE_URL`, so the installer needs one line changed;
   a `_redirects` rule keeps the old `/downloads/*` URLs working:

   ```
   /downloads/*  https://github.com/sandeshwar/vicaro-public/releases/download/v<tag>/:splat  302
   ```

   `<tag>` cannot contain the arch filename, so either publish one release per arch
   or point at a stable `latest` tag.

2. **The helper web UI bundle to a CDN over this repo** (`cdn.jsdelivr.net/gh/…`),
   which is free and caches at the edge. Version directories are immutable, so the
   URL never changes meaning.

If Netlify stays too expensive, the whole site is static and small: GitHub Pages
with a `CNAME` for `vicaro.creativeducks.com` serves it for nothing, and Pages has
its own free bandwidth allowance. The only thing lost is Netlify's form handling,
which this site does not use.

## Releasing a build

1. Build and pack in the app repo (`deploy/macos/build.sh --tarball`,
   `npm run pack:extension`).
2. Copy the tarballs, their `.sha256` files, `install.sh` and the extension zip
   here, and commit.
3. Verify: `curl -fsSL https://vicaro.creativeducks.com/install.sh | sh --dry-run`.

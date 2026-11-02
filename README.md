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

Push to `main`. GitHub Actions deploys the repo to Netlify, which serves the page
and `/downloads/` directly (no CDN in front, `max-age=0, must-revalidate`).

That matters for cost: a 38 MB tarball per install is real bandwidth, and the free
tier is not unlimited. Two consequences, in order of value:

1. **The web UI bundle goes to GitHub, not Netlify** — `cdn.jsdelivr.net/gh/` over
   this repo, or GitHub Pages, both free and cacheable, with an immutable
   version directory.
2. **Downloads belong in GitHub Releases** (`/releases/download/<tag>/…`), which is
   free and CDN-backed. `install.sh` already takes `VICARO_BASE_URL`, so moving is a
   one-line change plus a redirect for the old path.

## Releasing a build

1. Build and pack in the app repo (`deploy/macos/build.sh --tarball`,
   `npm run pack:extension`).
2. Copy the tarballs, their `.sha256` files, `install.sh` and the extension zip
   here, and commit.
3. Verify: `curl -fsSL https://vicaro.creativeducks.com/install.sh | sh --dry-run`.

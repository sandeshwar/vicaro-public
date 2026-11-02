# vicaro-public

The public face of Vicaro: the landing page, the installer script, and the helper's
web UI bundle. Nothing here is application source, and the app itself is closed
source.

## What is served

| Path | What | Notes |
|---|---|---|
| `/` | landing page (`index.html`) | product copy, install one-liner |
| `/install.sh` | macOS installer | copied verbatim from the app repo's `deploy/macos/install.sh` |
| `/privacy.html` | privacy policy | the URL pasted into the Chrome Web Store dashboard |
| `/webui/<version>/` | helper web UI bundle + manifest | hash-pinned; also mirrored by jsDelivr over this repo so UI traffic costs nothing |

Builds are **not** served from this repo. The tarballs, their `.sha256` files and
`Vicaro-extension.zip` are assets on a GitHub Release (tag `v<version>`), and
`install.sh` fetches them from `releases/latest/download`.

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

**GitHub Pages is the deployment.** It builds this repo on every push, for nothing,
at <https://sandeshwar.github.io/vicaro-public/> — the landing page, `install.sh`,
`privacy.html` and the web UI bundles included.

`CNAME` names the custom domain, and `vicaro.creativeducks.com` now answers from
Pages. The Netlify workflow is **manual only** (`workflow_dispatch`); with the domain
moved it can be deleted along with its two secrets.

> **Credits.** Every production deploy and every byte served is billed. Nine pushes
> in two days is nine deploys, and a single macOS install pulled a 38 MB tarball
> through Netlify on every run. That is what drained the allowance, not the 11 KB
> landing page.

### Where the bytes go now

1. **Downloads are GitHub Release assets.** `install.sh` points `BASE_URL` at
   `releases/latest/download`. There is no fallback: an earlier version retried
   `vicaro.creativeducks.com/downloads`, which is this same repository on GitHub
   Pages — so it failed whenever the release did.
2. **The helper web UI bundle can still move to a CDN over this repo**
   (`cdn.jsdelivr.net/gh/…`), which is free and caches at the edge. Version
   directories are immutable, so the URL never changes meaning.

The `downloads/` directory that used to sit here — 76 MB across two tarballs, their
checksums and the extension zip — is gone, and the history was rewritten to drop it,
because every clone and every Pages deploy carried it. The old commits survive only
in clones made before the rewrite.

## Releasing a build

1. Build and pack in the app repo (`deploy/macos/build.sh --tarball`,
   `npm run pack:extension`).
2. Create a GitHub Release (tag `v<version>`) with `Vicaro-macos-arm64.tar.gz`,
   `Vicaro-macos-x86_64.tar.gz`, both `.sha256` files and `Vicaro-extension.zip`
   attached. `install.sh` reads `latest/download`, so the newest release has to
   carry all five.
3. Copy `install.sh` from the app repo here, and commit.
4. Verify: `curl -fsSL https://vicaro.creativeducks.com/install.sh | sh -s -- --dry-run`
   (`sh --dry-run` passes the flag to the shell, not the script).

# vicaro-public

The public face of Vicaro: the landing page, the installer script, and the helper's
web UI bundle. Nothing here is application source, and the app itself is closed
source.

## What is served

| Path | What | Notes |
|---|---|---|
| `/` | landing page (`index.html`) | product copy, screenshots, install one-liner |
| `/support.html` | support and troubleshooting | setup, model, access, sign-in, beta safety |
| `/privacy.html` | privacy policy | the URL pasted into the Chrome Web Store dashboard |
| `/assets/shots/` | screenshot assets | 1280x800 PNG plus WebP variants used by the landing page and store listing |
| `/site.css`, `/site.js` | shared page shell | styles and small progressive enhancements, no framework |
| `/install.sh` | macOS installer | installs `Vicaro Helper.app` and stages the unpacked extension |
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
`support.html`, `privacy.html` and the web UI bundles included.

`CNAME` names the custom domain, and `vicaro.creativeducks.com` answers from Pages.

> **Why Pages.** Netlify billed every deploy and every byte. Nine pushes in two days
> were nine deploys, and a single macOS install pulled a 38 MB tarball through it on
> every run. Pages serves the same static site for nothing, and the release now
> carries the downloads.

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

## Previewing the pages

```sh
python3 -m http.server 8088
# open http://127.0.0.1:8088/
```

The pages have no build step. `site.js` is optional: the copy button falls back to
selecting the command, and the mobile menu is a native `<details>` element.

## Releasing a build

1. In the app repo, run `./deploy/rust/release.sh`. It builds the Rust helper for
   arm64 and x86_64, bundles the pinned development extension, signs both apps
   ad-hoc, and writes the tarballs, checksums and `Vicaro-extension.zip` to
   `dist/release/`.
2. Create a GitHub Release (tag `v<version>`) with `Vicaro-macos-arm64.tar.gz`,
   `Vicaro-macos-x86_64.tar.gz`, both `.sha256` files, `Vicaro-Beta-<version>.dmg`
   with its checksum, and `Vicaro-extension.zip` attached. `install.sh` reads
   `latest/download`, so the newest release has to carry the tarballs and zip.
3. Update `install.sh` here if the app name, launch agent or install paths changed,
   and commit.
4. Verify: `curl -fsSL https://vicaro.creativeducks.com/install.sh | sh -s -- --dry-run`
   (`sh --dry-run` passes the flag to the shell, not the script).

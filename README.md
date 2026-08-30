# lifeos_alpha_builds

Alpha builds of Life OS for Windows, Linux and Android (iOS later). Expect rough
edges, and expect them to change under you.

## Download

These links never change. Each one always serves the newest alpha.

| Platform | Download |
| --- | --- |
| **Android** | [LifeOS-android.apk](https://github.com/AmanGusain2003/lifeos_alpha_builds/releases/latest/download/LifeOS-android.apk) |
| **Linux** (x86_64) | [LifeOSCapture-linux-x86_64.AppImage](https://github.com/AmanGusain2003/lifeos_alpha_builds/releases/latest/download/LifeOSCapture-linux-x86_64.AppImage) |
| **Windows** (x64) | [LifeOSCapture-windows-x64.exe](https://github.com/AmanGusain2003/lifeos_alpha_builds/releases/latest/download/LifeOSCapture-windows-x64.exe) |

`releases/latest/download/<name>` is a GitHub redirect to whichever release is
newest, so a link handed to someone in March still gives them the build from
December. Nothing has to be edited to keep it current.

### Installing

- **Android** — allow install from unknown sources, then open the APK. The
  published build is `arm64-v8a`, which is every phone since roughly 2017. A
  32-bit device needs the `armeabi-v7a` APK from the same build command.
- **Linux** — `chmod +x LifeOSCapture-linux-x86_64.AppImage` and run it.
- **Windows** — SmartScreen will warn about an unrecognised publisher; these
  builds are unsigned. *More info → Run anyway*.

## For updaters: `latest.json`

A machine-readable manifest of the current release, with sizes and SHA-256 sums:

```
https://cdn.jsdelivr.net/gh/AmanGusain2003/lifeos_alpha_builds@latest/latest.json
```

Served by [jsDelivr](https://www.jsdelivr.com/) from the newest tag, so it is
CDN-cached and cheap to poll.

Worth knowing what jsDelivr can and cannot do here. Its GitHub endpoint serves
files **committed in this repository**, addressed by tag or branch — it has no
notion of release assets, and it will not serve files the size of these
binaries. So the manifest goes through jsDelivr and the binaries do not; the
`url` field in the manifest points at GitHub's own permanent link above.

```json
{
  "downloads": {
    "android": { "url": "…/releases/latest/download/LifeOS-android.apk", "sha256": "…" }
  }
}
```

`pinned_url` sits alongside it and addresses that exact release, for anyone who
needs a build to stay put.

## Cutting a release

Everything is in one script. It uploads the binaries, regenerates the manifest
and pushes — see [`scripts/release.sh`](scripts/release.sh).

Build the APK split per ABI rather than as one universal file — a universal APK
carries native libraries for every CPU and is three times the size for no
benefit to anyone:

```bash
flutter build apk --release --split-per-abi \
  --obfuscate --split-debug-info=build/symbols
# 21 MB arm64-v8a, against 61 MB universal
```

```bash
./scripts/release.sh \
  --android build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --linux   ~/path/to/LifeOSCapture-x86_64.AppImage \
  --windows ~/path/to/LifeOSCapture.exe
```

Pass only what you rebuilt. Anything left out is **carried forward** from the
current release, because a release missing a platform would break that
platform's permanent link: `latest` moves to the new release, and the old asset
is not there to redirect to. `--no-carry-forward` opts out, deliberately.

The tag defaults to `alpha-<today>`, with a counter if there is already one for
today. `--version` overrides it, `--notes` sets the release body, and
`--dry-run` prints the plan without touching GitHub.

Releases made by hand through the GitHub UI are fine too: a workflow regenerates
`latest.json` whenever a release is published.

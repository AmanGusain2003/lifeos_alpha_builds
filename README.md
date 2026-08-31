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

**Two version strings have to agree, and nothing enforces it.** The Android app
decides whether to show its "update available" banner by comparing the version
it was built with against the one the backend announces:

- `pubspec.yaml` in `lifeOs-mobile` — `version: <name>+<build>`. The build
  number only has to keep rising; Android treats the name as cosmetic.
- `backend/app/assets/app_releases.json` in `lifeOs` — the `version` of the
  newest `android` entry, which must be **exactly** that same name.

They drift easily, because the two ship on different schedules — the APK from
here, the manifest with a backend deploy — and the `alpha-<date>` tag this
script generates is a third thing neither of them reads. When they drift,
someone on a build newer than the manifest gets one dismissible "update
available" sheet whose Download hands them what they already have. Dismissal is
remembered per version, so it is an annoyance rather than a fault — but bump
both files together and it never happens.

Build the APK split per ABI rather than as one universal file — a universal APK
carries native libraries for every CPU and is three times the size for no
benefit to anyone:

```bash
flutter build apk --release --split-per-abi \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=LIFE_OS_GOOGLE_SERVER_CLIENT_ID=332306488841-venoccdufprdc4lms8qdj01ldi6lgc8a.apps.googleusercontent.com
# 21 MB arm64-v8a, against 61 MB universal
```

The `--dart-define` is not optional. Without it the app reads Google Sign-In as
unconfigured and hides the button on both the login and register screens — so a
build missing the flag looks like a release that dropped a feature rather than
one that lost a define. The value is an OAuth client ID: an identifier, not a
secret.

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

That workflow lands one `chore: point latest.json at …` commit per release even
when the script already wrote the same file, because it stamps `released_at`
from GitHub's own publish time rather than from whenever the manifest happened
to be generated. That is the authoritative value, so the extra commit is the
point rather than a loop.

Releases are published as ordinary releases, never as prereleases: GitHub's
`releases/latest` skips prereleases, which would 404 every link above.

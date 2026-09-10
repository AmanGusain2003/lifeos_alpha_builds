#!/usr/bin/env bash
#
# Cut an alpha release.
#
# Uploads whichever binaries you pass, carries the rest forward from the current
# release, regenerates latest.json and pushes it. One command, so that shipping
# a build is not a checklist anyone has to remember.
#
#   ./scripts/release.sh --android build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#   ./scripts/release.sh --linux LifeOSCapture-x86_64.AppImage --windows LifeOSCapture.exe
#   ./scripts/release.sh --version alpha-2026.09.01 --notes "Reminder buttons." --dry-run
#
set -euo pipefail

REPO="AmanGusain2003/lifeos_alpha_builds"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/latest.json"

# Constant across every release, and that is the whole point: the permanent
# download link is releases/latest/download/<name>, so the name may never drift.
#
# Releases are published as normal releases, not prereleases. GitHub's idea of
# the latest release skips prereleases entirely, so marking these -- every one
# of which is an alpha, in a repository named for it -- would 404 the only link
# any of this exists to provide.
ANDROID_ASSET="LifeOS-android.apk"
LINUX_ASSET="LifeOSCapture-linux-x86_64.AppImage"
WINDOWS_ASSET="LifeOSCapture-windows-x64.exe"
# Two of them, because a .app built for one architecture will not run on the
# other: PyInstaller freezes whichever interpreter it is running under, so
# there is no universal build to hand out instead.
MACOS_ARM64_ASSET="LifeOSCapture-macos-arm64.zip"
MACOS_X86_64_ASSET="LifeOSCapture-macos-x86_64.zip"

android_src="" linux_src="" windows_src="" macos_arm64_src="" macos_x86_64_src=""
version="" notes="" dry_run=false carry_forward=true

die() { printf 'release: %s\n' "$1" >&2; exit 1; }
say() { printf '  %s\n' "$1"; }

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

  --android PATH   APK to publish -- the arm64-v8a one from
                   `flutter build apk --release --split-per-abi`, not the
                   universal build, which is three times the size because it
                   carries native libraries for CPUs the device does not have
  --linux PATH     AppImage to publish
  --windows PATH   .exe to publish
  --macos-arm64 PATH    zipped .app for Apple Silicon
  --macos-x86_64 PATH   zipped .app for Intel
  --version TAG    release tag (default: alpha-<today>, counted if taken)
  --notes TEXT     release body
  --no-carry-forward   publish only what was passed, leaving the other
                       platforms' permanent links pointing at nothing
  --dry-run        print the plan, touch nothing
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --android) android_src="${2:-}"; shift 2 ;;
    --linux)   linux_src="${2:-}";   shift 2 ;;
    --windows) windows_src="${2:-}"; shift 2 ;;
    --macos-arm64)  macos_arm64_src="${2:-}";  shift 2 ;;
    --macos-x86_64) macos_x86_64_src="${2:-}"; shift 2 ;;
    --version) version="${2:-}";     shift 2 ;;
    --notes)   notes="${2:-}";       shift 2 ;;
    --no-carry-forward) carry_forward=false; shift ;;
    --dry-run) dry_run=true;         shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

command -v gh >/dev/null || die "gh is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not logged in -- run: gh auth login"
[[ -n "$android_src$linux_src$windows_src$macos_arm64_src$macos_x86_64_src" ]] \
  || { usage; die "nothing to publish"; }

for src in "$android_src" "$linux_src" "$windows_src" "$macos_arm64_src" "$macos_x86_64_src"; do
  [[ -z "$src" ]] && continue
  [[ -f "$src" ]] || die "no such file: $src"
  [[ -s "$src" ]] || die "empty file: $src"
done

# An APK built without the Google client id define hides the sign-in button
# entirely rather than failing at it: AppConfig.googleServerClientId defaults to
# '', which makes NativeGoogleIdentityService.isConfigured false, and both the
# login and register screens then render with no Google button at all. That
# reads as a plain screen rather than a misconfiguration, so nobody notices
# until someone tries to sign in. alpha-2026.09.10 shipped that way.
#
# Checked against the Dart snapshot, because the APK as a whole is not
# evidence: the id string is in there either way, carried by the bundled
# google-services.json that the app never reads.
GOOGLE_CLIENT_ID_PREFIX="332306488841-venocc"
if [[ -n "$android_src" ]] && command -v unzip >/dev/null && command -v strings >/dev/null; then
  snapshot_hits=0
  for abi in arm64-v8a armeabi-v7a x86_64; do
    # grep -c rather than -q, deliberately: -q exits on the first match, which
    # hands unzip a SIGPIPE, and under `set -o pipefail` that fails the whole
    # pipeline on exactly the builds that pass. -c reads to the end.
    found="$(unzip -p "$android_src" "lib/$abi/libapp.so" 2>/dev/null \
      | strings 2>/dev/null | grep -c "$GOOGLE_CLIENT_ID_PREFIX" || true)"
    [[ "${found:-0}" -gt 0 ]] && snapshot_hits=$((snapshot_hits + 1))
  done
  [[ "$snapshot_hits" -gt 0 ]] || die "this APK has no Google sign-in button -- rebuild with
  flutter build apk --release --split-per-abi \\
    --dart-define=LIFE_OS_GOOGLE_SERVER_CLIENT_ID=332306488841-venoccdufprdc4lms8qdj01ldi6lgc8a.apps.googleusercontent.com"
fi

# A tag per day, counted if the day already has one. Alpha builds come in
# bursts, and a date alone would collide by the second build of an afternoon.
if [[ -z "$version" ]]; then
  # Local date, not UTC: the tag is read by whoever cut the build, and a
  # build made at midnight should not be dated yesterday on their own clock.
  base="alpha-$(date +%Y.%m.%d)"
  version="$base"
  n=2
  while gh release view "$version" --repo "$REPO" >/dev/null 2>&1; do
    version="$base.$n"
    n=$((n + 1))
  done
fi

previous="$(gh release view --repo "$REPO" --json tagName --jq .tagName 2>/dev/null || true)"

# Staged where the uploads are assembled, so a carried-forward asset and a fresh
# one are handled identically from here on.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

stage() { # stage <source-path> <asset-name>
  cp "$1" "$staging/$2"
}

carry() { # carry <asset-name>
  [[ -n "$previous" ]] || return 1
  gh release download "$previous" --repo "$REPO" --pattern "$1" --dir "$staging" >/dev/null 2>&1
}

echo "Release $version${previous:+  (previous: $previous)}"

for pair in "android:$android_src:$ANDROID_ASSET" \
            "linux:$linux_src:$LINUX_ASSET" \
            "windows:$windows_src:$WINDOWS_ASSET" \
            "macos-arm64:$macos_arm64_src:$MACOS_ARM64_ASSET" \
            "macos-x86_64:$macos_x86_64_src:$MACOS_X86_64_ASSET"; do
  platform="${pair%%:*}"; rest="${pair#*:}"
  src="${rest%%:*}"; asset="${rest#*:}"

  if [[ -n "$src" ]]; then
    stage "$src" "$asset"
    say "$platform: new  <- $src"
  elif $carry_forward && carry "$asset"; then
    say "$platform: carried forward from $previous"
  else
    # Said plainly, because the consequence is a download link that 404s for
    # everyone on that platform until the next release puts it back.
    say "$platform: MISSING -- its permanent link will break"
  fi
done

if $dry_run; then
  echo
  echo "Dry run. Would upload:"
  ls -1sh "$staging" | tail -n +2 | sed 's/^/  /'
  exit 0
fi

# The manifest is committed before the tag exists, so that the tag -- and with
# it the jsDelivr @latest URL -- resolves to a tree that already describes this
# release rather than the one before it.
python3 "$ROOT/scripts/write_manifest.py" \
  --repo "$REPO" --version "$version" --staging "$staging" --out "$MANIFEST" \
  --android-asset "$ANDROID_ASSET" --linux-asset "$LINUX_ASSET" --windows-asset "$WINDOWS_ASSET" \
  --macos-arm64-asset "$MACOS_ARM64_ASSET" --macos-x86-64-asset "$MACOS_X86_64_ASSET"

git -C "$ROOT" add latest.json
if ! git -C "$ROOT" diff --cached --quiet; then
  git -C "$ROOT" commit -q -m "chore: point latest.json at $version"
fi
git -C "$ROOT" push -q origin HEAD

gh release create "$version" \
  --repo "$REPO" \
  --title "$version" \
  --notes "${notes:-Alpha build $version.}" \
  --latest \
  "$staging"/*

echo
echo "Published $version"
echo "  https://github.com/$REPO/releases/tag/$version"
echo
echo "Permanent links (unchanged, always newest):"
echo "  https://github.com/$REPO/releases/latest/download/$ANDROID_ASSET"
echo "  https://github.com/$REPO/releases/latest/download/$LINUX_ASSET"
echo "  https://github.com/$REPO/releases/latest/download/$WINDOWS_ASSET"
echo "  https://github.com/$REPO/releases/latest/download/$MACOS_ARM64_ASSET"
echo "  https://github.com/$REPO/releases/latest/download/$MACOS_X86_64_ASSET"
echo "  https://cdn.jsdelivr.net/gh/$REPO@latest/latest.json"

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
ANDROID_ASSET="LifeOS-android.apk"
LINUX_ASSET="LifeOSCapture-linux-x86_64.AppImage"
WINDOWS_ASSET="LifeOSCapture-windows-x64.exe"

android_src="" linux_src="" windows_src=""
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
[[ -n "$android_src$linux_src$windows_src" ]] || { usage; die "nothing to publish"; }

for src in "$android_src" "$linux_src" "$windows_src"; do
  [[ -z "$src" ]] && continue
  [[ -f "$src" ]] || die "no such file: $src"
  [[ -s "$src" ]] || die "empty file: $src"
done

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
            "windows:$windows_src:$WINDOWS_ASSET"; do
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
  --android-asset "$ANDROID_ASSET" --linux-asset "$LINUX_ASSET" --windows-asset "$WINDOWS_ASSET"

git -C "$ROOT" add latest.json
if ! git -C "$ROOT" diff --cached --quiet; then
  git -C "$ROOT" commit -q -m "chore: point latest.json at $version"
fi
git -C "$ROOT" push -q origin HEAD

gh release create "$version" \
  --repo "$REPO" \
  --title "$version" \
  --notes "${notes:-Alpha build $version.}" \
  --prerelease \
  "$staging"/*

echo
echo "Published $version"
echo "  https://github.com/$REPO/releases/tag/$version"
echo
echo "Permanent links (unchanged, always newest):"
echo "  https://github.com/$REPO/releases/latest/download/$ANDROID_ASSET"
echo "  https://github.com/$REPO/releases/latest/download/$LINUX_ASSET"
echo "  https://github.com/$REPO/releases/latest/download/$WINDOWS_ASSET"
echo "  https://cdn.jsdelivr.net/gh/$REPO@latest/latest.json"

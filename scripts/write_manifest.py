#!/usr/bin/env python3
"""Describe a release in latest.json.

Kept separate from release.sh because the GitHub workflow needs the same thing
for releases cut by hand through the web UI, and two implementations of the same
manifest is how the two quietly stop agreeing.

Sizes and hashes are read from the files actually being uploaded, never from the
release metadata: the point of publishing a SHA-256 is that someone can check
the bytes they downloaded, and a hash copied from the same place as the file
proves nothing about it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        # These run to a couple of hundred megabytes; reading one whole into
        # memory to hash it would be careless on a laptop mid-build.
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def entry(repo: str, version: str, staging: Path, asset: str) -> dict | None:
    path = staging / asset
    if not path.is_file():
        # The platform was not in this release. Saying nothing about it is
        # honest; an entry pointing at a download that 404s is not.
        return None
    return {
        "name": asset,
        # Never changes, and always resolves to the newest release.
        "url": f"https://github.com/{repo}/releases/latest/download/{asset}",
        # This exact build, for anyone who needs it to stay put.
        "pinned_url": f"https://github.com/{repo}/releases/download/{version}/{asset}",
        "size": path.stat().st_size,
        "sha256": sha256(path),
    }


def released_at(out: Path, version: str, given: str) -> str:
    """A manifest already describing this exact version keeps the timestamp it
    has.

    Everything else in here is derived from the release's own bytes, so
    regenerating a manifest for the same version reproduces it exactly --
    except this, which used to be datetime.now() and so came out different
    every run. That was enough to make the refresh workflow believe every
    release.sh release had changed something, and try to push a commit to a
    protected branch it can't push to. Same version, same release: same
    timestamp, and the workflow correctly finds nothing to do.
    """
    existing_at = ""
    try:
        existing = json.loads(out.read_text())
        if existing.get("version") == version:
            existing_at = str(existing.get("released_at") or "")
    except (OSError, ValueError, AttributeError):
        pass  # No manifest yet, or an unreadable one -- treat it as new.
    return existing_at or given.strip() or datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--staging", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--android-asset", required=True)
    parser.add_argument("--linux-asset", required=True)
    parser.add_argument("--windows-asset", required=True)
    # macOS ships two, because a .app built for one architecture does not run
    # on the other and PyInstaller cannot produce a universal binary from a
    # single-architecture build. Required like the rest on purpose: a caller
    # that hasn't been taught about macOS should fail loudly here rather than
    # quietly write a manifest that omits it.
    parser.add_argument("--macos-arm64-asset", required=True)
    parser.add_argument("--macos-x86-64-asset", required=True)
    parser.add_argument(
        "--released-at",
        default="",
        help="when the release went out (default: now). The workflow passes the "
        "release's own published_at so a rerun doesn't invent a new time.",
    )
    args = parser.parse_args()

    downloads = {}
    for platform, asset in (
        ("android", args.android_asset),
        ("linux", args.linux_asset),
        ("windows", args.windows_asset),
        ("macos_arm64", args.macos_arm64_asset),
        ("macos_x86_64", args.macos_x86_64_asset),
    ):
        found = entry(args.repo, args.version, args.staging, asset)
        if found is not None:
            downloads[platform] = found

    manifest = {
        "channel": "alpha",
        "version": args.version,
        "released_at": released_at(args.out, args.version, args.released_at),
        "notes_url": f"https://github.com/{args.repo}/releases/tag/{args.version}",
        "downloads": downloads,
    }

    # Trailing newline and sorted keys so a release that changes nothing but the
    # version produces a one-line diff rather than a reshuffled file.
    args.out.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"latest.json -> {args.version} ({', '.join(downloads) or 'nothing'})")


if __name__ == "__main__":
    main()

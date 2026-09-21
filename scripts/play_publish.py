#!/usr/bin/env python3
"""Publish the NAS app to Google Play from the command line.

Wraps the Google Play Android Publisher API v3. Chosen over fastlane because that
would pull in a whole Ruby toolchain for one task, and over Gradle Play Publisher
because the release flow here is driven from Flutter, not Gradle.

Subcommands
-----------
  check     Verify credentials and print what is live on each track. Uploads nothing.
  bump      Increment the versionCode in pubspec.yaml (the +N after the version).
  build     flutter build appbundle --release
  upload    Upload an .aab and assign it to a track.
  release   bump -> build -> upload, the whole thing.

Safety
------
* The default track is **internal**. Reaching production needs an explicit
  `--track production` *and* `--yes`, because a production push is visible to
  everyone within minutes and cannot be unpublished, only superseded.
* A versionCode already present on Play is refused before anything is uploaded --
  Play rejects duplicates anyway, but it does so after a multi-minute upload.
* The service-account JSON is never printed, and the filename patterns are
  gitignored.

First-time setup is manual and cannot be scripted -- see `check` output or
README.md.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PUBSPEC = REPO / "pubspec.yaml"
DEFAULT_AAB = REPO / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"
PACKAGE_NAME = "mattyzem.nas"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
TRACKS = ("internal", "alpha", "beta", "production")

SETUP_HELP = f"""
Google Play API access is not set up yet. These steps are manual -- Google gives no
API for granting API access, so nothing here can do them for you.

Note: Play Console's old "Setup -> API access" page is GONE. Google removed it; you
no longer link a Cloud project to the developer account. Access is granted purely by
inviting the service account as a Play Console user (step 4).

 1. console.cloud.google.com -> create a project (or pick one). It can be empty and
    free; it exists only to own the service account.

 2. In that project, enable the API -- without this every call 403s:
      console.cloud.google.com/apis/library/androidpublisher.googleapis.com
    Check the project name in the top bar first, then Enable.

 3. IAM & Admin -> Service Accounts -> Create. Name it e.g. "play-publisher".
    Skip the "grant this service account access to the project" step -- no Cloud
    roles are needed, permissions come from Play, not from GCP.
    Then on it: Keys -> Add key -> Create new key -> JSON. Download it.

 4. Play Console -> Users and permissions -> Invite new users, paste the service
    account's email (...@....iam.gserviceaccount.com). Under App permissions add
    {PACKAGE_NAME} and grant:
      - Release to testing tracks
      - Release to production  (only if you want this tool to reach production)
      - View app information and download bulk reports
    Permission changes take a few minutes to propagate.

 5. Save the JSON outside the repo, e.g. ~/.config/play/nas-app.json, chmod 600, and
    point this tool at it:
      export PLAY_SERVICE_ACCOUNT_JSON=~/.config/play/nas-app.json

 6. Re-run:  scripts/play_publish.py check

Note: the app must already exist on Play with at least one manual upload. The API
can push new releases but cannot create the listing.
""".strip()


# ── pubspec ──────────────────────────────────────────────────────────────────

# [ \t] rather than \s for the trailing run: \s matches newlines too, and with re.M
# the substitution then swallows the blank line after `version:` -- silently reflowing
# pubspec.yaml on every bump. Caught by test_bump_leaves_the_rest_of_pubspec_alone.
_VERSION_RE = re.compile(r"^version:[ \t]*(\d+\.\d+\.\d+)\+(\d+)[ \t]*$", re.M)


def read_version(pubspec: Path = PUBSPEC) -> tuple[str, int]:
    """Return (semver, versionCode) from pubspec.yaml."""
    m = _VERSION_RE.search(pubspec.read_text())
    if not m:
        sys.exit(f"could not find a 'version: x.y.z+N' line in {pubspec}")
    return m.group(1), int(m.group(2))


def bump_version(by: int = 1, pubspec: Path = PUBSPEC) -> tuple[str, int]:
    """Increment the versionCode and write pubspec.yaml back."""
    if by < 1:
        sys.exit("--by must be at least 1; versionCode may never go backwards")
    name, code = read_version(pubspec)
    new = code + by
    pubspec.write_text(_VERSION_RE.sub(f"version: {name}+{new}", pubspec.read_text(), count=1))
    return name, new


# ── Play API ─────────────────────────────────────────────────────────────────

def _credentials_path() -> Path:
    raw = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", "").strip()
    if not raw:
        print(SETUP_HELP)
        sys.exit("\nPLAY_SERVICE_ACCOUNT_JSON is not set.")
    path = Path(raw).expanduser()
    if not path.is_file():
        print(SETUP_HELP)
        sys.exit(f"\nPLAY_SERVICE_ACCOUNT_JSON points at {path}, which does not exist.")
    return path


def play_service():
    """Authenticated androidpublisher client."""
    from google.oauth2 import service_account          # imported late: `bump` needs no deps
    from googleapiclient.discovery import build

    creds = service_account.Credentials.from_service_account_file(
        str(_credentials_path()), scopes=[SCOPE])
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def live_version_codes(service, package: str = PACKAGE_NAME) -> dict[str, list[int]]:
    """{track: [versionCode, ...]} for every track that has a release.

    Opens a throwaway edit and deletes it, so it changes nothing.
    """
    edit = service.edits().insert(body={}, packageName=package).execute()
    try:
        tracks = service.edits().tracks().list(
            editId=edit["id"], packageName=package).execute().get("tracks", [])
    finally:
        try:
            service.edits().delete(editId=edit["id"], packageName=package).execute()
        except Exception:
            pass  # abandoned edits expire on their own
    out: dict[str, list[int]] = {}
    for t in tracks:
        codes = [int(c) for r in t.get("releases", []) for c in r.get("versionCodes", [])]
        if codes:
            out[t["track"]] = sorted(codes)
    return out


# ── commands ─────────────────────────────────────────────────────────────────

def cmd_check(args) -> int:
    name, code = read_version()
    print(f"app            : {PACKAGE_NAME}")
    print(f"local version  : {name}+{code}  (pubspec.yaml)")
    aab = Path(args.aab)
    print(f"local bundle   : {'present' if aab.is_file() else 'NOT BUILT'} "
          f"{f'({aab.stat().st_size / 2**20:.0f} MB)' if aab.is_file() else ''}")
    service = play_service()
    try:
        live = live_version_codes(service)
    except Exception as e:
        print(SETUP_HELP)
        return _explain_api_error(e)
    print("\ncredentials    : OK")
    if not live:
        print("tracks         : none have a release yet")
    for track in TRACKS:
        codes = live.get(track)
        print(f"  {track:<11} {', '.join(map(str, codes)) if codes else '—'}")
    highest = max((c for cs in live.values() for c in cs), default=0)
    if code <= highest:
        print(f"\n⚠ local versionCode {code} is not above the highest on Play ({highest}). "
              f"Run:  {Path(__file__).name} bump")
    else:
        print(f"\nversionCode {code} is free — ready to upload.")
    return 0


def _explain_api_error(e: Exception) -> int:
    msg = str(e)
    if "403" in msg or "permission" in msg.lower():
        print("\nThe credentials are valid but Play refused them. Usually step 4: the "
              "service account has not been invited in Play Console, or the grant has "
              "not propagated yet (give it a few minutes).")
    elif "404" in msg:
        print(f"\nPlay does not know {PACKAGE_NAME}. The app must exist with at least "
              f"one manual upload before the API can publish to it.")
    else:
        print(f"\nAPI error: {msg[:300]}")
    return 1


def cmd_bump(args) -> int:
    name, new = bump_version(args.by)
    print(f"pubspec.yaml -> {name}+{new}")
    return 0


def cmd_build(args) -> int:
    name, code = read_version()
    print(f"building {name}+{code} …")
    r = subprocess.run(["/home/matty/flutter/bin/flutter", "build", "appbundle", "--release"],
                       cwd=REPO)
    if r.returncode != 0:
        return r.returncode
    aab = Path(args.aab)
    print(f"built {aab} ({aab.stat().st_size / 2**20:.0f} MB)" if aab.is_file()
          else f"build reported success but {aab} is missing")
    return 0 if aab.is_file() else 1


def cmd_upload(args) -> int:
    from googleapiclient.http import MediaFileUpload

    aab = Path(args.aab)
    if not aab.is_file():
        sys.exit(f"{aab} does not exist — run `build` first")
    if args.track not in TRACKS:
        sys.exit(f"--track must be one of {', '.join(TRACKS)}")
    if args.track == "production" and not args.yes:
        sys.exit("refusing to publish to production without --yes: a production release "
                 "is visible to everyone within minutes and can only be superseded, "
                 "never withdrawn")

    name, code = read_version()
    service = play_service()
    try:
        live = live_version_codes(service)
    except Exception as e:
        return _explain_api_error(e)
    all_codes = {c for cs in live.values() for c in cs}
    if code in all_codes:
        sys.exit(f"versionCode {code} is already on Play. Run `bump` and rebuild — "
                 f"Play would reject this, but only after uploading {aab.stat().st_size / 2**20:.0f} MB.")

    print(f"uploading {name}+{code} to '{args.track}' …")
    if args.dry_run:
        print("dry run — nothing sent")
        return 0

    edit = service.edits().insert(body={}, packageName=PACKAGE_NAME).execute()
    edit_id = edit["id"]
    try:
        media = MediaFileUpload(str(aab), mimetype="application/octet-stream", resumable=True)
        bundle = service.edits().bundles().upload(
            editId=edit_id, packageName=PACKAGE_NAME, media_body=media).execute()
        uploaded = int(bundle["versionCode"])
        if uploaded != code:
            print(f"note: the bundle's versionCode is {uploaded}, pubspec says {code} — "
                  f"the bundle is older than pubspec.yaml. Using {uploaded}.")

        release: dict = {"versionCodes": [str(uploaded)]}
        if args.notes:
            release["releaseNotes"] = [{"language": "en-GB", "text": args.notes}]
        if args.rollout is not None:
            release["status"] = "inProgress"
            release["userFraction"] = args.rollout
        else:
            release["status"] = "completed"

        service.edits().tracks().update(
            editId=edit_id, track=args.track, packageName=PACKAGE_NAME,
            body={"releases": [release]}).execute()
        service.edits().commit(editId=edit_id, packageName=PACKAGE_NAME).execute()
    except Exception as e:
        try:
            service.edits().delete(editId=edit_id, packageName=PACKAGE_NAME).execute()
        except Exception:
            pass
        return _explain_api_error(e)

    rollout = f" at {args.rollout:.0%} rollout" if args.rollout is not None else ""
    print(f"done — {name}+{uploaded} is on '{args.track}'{rollout}")
    return 0


def cmd_release(args) -> int:
    if (rc := cmd_bump(args)) != 0:
        return rc
    if (rc := cmd_build(args)) != 0:
        return rc
    return cmd_upload(args)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--aab", default=str(DEFAULT_AAB), help="path to the app bundle")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("check", help="verify credentials and show what is live").set_defaults(fn=cmd_check)

    b = sub.add_parser("bump", help="increment the versionCode in pubspec.yaml")
    b.add_argument("--by", type=int, default=1)
    b.set_defaults(fn=cmd_bump)

    sub.add_parser("build", help="flutter build appbundle --release").set_defaults(fn=cmd_build)

    def _upload_args(sp):
        sp.add_argument("--track", default="internal", choices=TRACKS)
        sp.add_argument("--notes", default="", help="release notes (en-GB)")
        sp.add_argument("--rollout", type=float, default=None,
                        help="staged rollout fraction, e.g. 0.1 for 10%%")
        sp.add_argument("--yes", action="store_true", help="required for production")
        sp.add_argument("--dry-run", action="store_true")

    u = sub.add_parser("upload", help="upload an .aab and assign it to a track")
    _upload_args(u)
    u.set_defaults(fn=cmd_upload)

    r = sub.add_parser("release", help="bump + build + upload")
    _upload_args(r)
    r.add_argument("--by", type=int, default=1)
    r.set_defaults(fn=cmd_release)

    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())

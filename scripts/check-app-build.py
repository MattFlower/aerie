#!/usr/bin/env python3
"""Verify a launchable bundle against this checkout without launching or configuring it."""
import argparse
import hashlib
import json
import plistlib
import re
import subprocess
from pathlib import Path


class BuildMismatch(ValueError):
    pass


def binary_hash(app):
    result = hashlib.sha256()
    with (app / "Contents/MacOS/Aerie").open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def receipt_path(app):
    return Path(str(app) + ".build.json")


def bundle_info(app):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != "app.aerie.monitor":
        raise BuildMismatch("The selected bundle is not Aerie.")
    revision = info.get("AerieSourceRevision")
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}|unversioned", revision):
        raise BuildMismatch("This app lacks a recorded build revision; rebuild it before launch.")
    if type(info.get("AerieSourceModified")) is not bool:
        raise BuildMismatch("The app lacks a recorded source modification state.")
    return info


def write_receipt(app, revision, modified):
    info = bundle_info(app)
    if info["AerieSourceRevision"] != revision or info["AerieSourceModified"] != modified:
        raise BuildMismatch("Bundle metadata differs from the build's source state.")
    record = {"format": 1, "sourceRevision": revision, "sourceModified": modified,
              "binarySHA256": binary_hash(app)}
    path = receipt_path(app)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)
    return record


def verify_metadata(app, expected_revision, current_modified=False):
    info = bundle_info(app)
    path = receipt_path(app)
    if not path.is_file() or path.stat().st_size > 8192:
        raise BuildMismatch("The app's build receipt is missing or invalid; rebuild it before launch.")
    record = json.loads(path.read_text())
    if (not isinstance(record, dict) or type(record.get("format")) is not int
            or record.get("format") != 1 or type(record.get("sourceModified")) is not bool):
        raise BuildMismatch("The build receipt has an invalid format.")
    if record.get("sourceRevision") != info["AerieSourceRevision"]:
        raise BuildMismatch("The app and its build receipt disagree.")
    if record.get("sourceModified") != info["AerieSourceModified"]:
        raise BuildMismatch("The app and receipt disagree about modified sources.")
    if info["AerieSourceRevision"] != expected_revision:
        raise BuildMismatch("This app was built from another revision; rebuild or select the current build.")
    if info["AerieSourceModified"] or current_modified:
        raise BuildMismatch("Sources were modified; commit and rebuild before verifying an exact revision.")
    if record.get("binarySHA256") != binary_hash(app):
        raise BuildMismatch("The executable differs from its recorded build; rebuild it before launch.")
    return record


def source_state(repository):
    revision = subprocess.run(["git", "-C", str(repository), "rev-parse", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
    modified = bool(subprocess.run(["git", "-C", str(repository), "status", "--porcelain"],
                                   capture_output=True, text=True, check=True).stdout.strip())
    return revision, modified


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", nargs="?", default="dist/Aerie.app", type=Path)
    parser.add_argument("--write-receipt", action="store_true")
    parser.add_argument("--revision")
    parser.add_argument("--modified", choices=["true", "false"])
    args = parser.parse_args()
    try:
        if args.write_receipt:
            if args.revision is None or args.modified is None:
                parser.error("--write-receipt requires --revision and --modified")
            write_receipt(args.app, args.revision, args.modified == "true")
        else:
            revision, modified = source_state(Path(__file__).resolve().parent.parent)
            record = verify_metadata(args.app, revision, modified)
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.app)], check=True)
            print("Verified Aerie build " + record["sourceRevision"][:12] + "; no app launched.")
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.CalledProcessError):
        # No configuration, path, or receipt contents are echoed on a failed check.
        print("Aerie build verification failed. Rebuild this checkout and select the app just built.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

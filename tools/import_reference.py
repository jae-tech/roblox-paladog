"""Import pinned research Markdown into data/reference + data/normalized (ASSET_PIPELINE §2)."""
import argparse
import sys

from balance_lib import REFERENCE_DIRS, DataError, load_sources, reference_outputs, write_or_check


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="docs", help="fixed to docs/; hashes pinned in tools/reference-hashes.json")
    parser.add_argument("--manifest", default="data/reference/manifest.json")
    parser.add_argument("--check", action="store_true", help="fail if committed outputs differ from regeneration")
    args = parser.parse_args()
    if args.source != "docs" or args.manifest != "data/reference/manifest.json":
        raise SystemExit("FAIL: only the pinned docs/ source and data/reference/manifest.json are supported")
    try:
        files = reference_outputs(load_sources())[2]
    except DataError as error:
        print("FAIL:", error, file=sys.stderr)
        return 1
    stale = write_or_check(files, args.check, REFERENCE_DIRS)
    for path in stale:
        print("STALE:", path, file=sys.stderr)
    print(("checked " if args.check else "wrote ") + str(len(files)) + " reference files")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())

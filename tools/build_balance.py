"""Build data/balance/<version>.* and generated Luau from normalized reference + overlay."""
import argparse
import sys

from balance_lib import BALANCE_DIRS, BALANCE_VERSION, DataError, load_sources, outputs, overlay_bytes, write_or_check

PREFIXES = ("data/balance/", "src/server/Config/Generated/", "src/shared/PublicCatalog.luau")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--check", action="store_true", help="fail if committed outputs differ from regeneration")
    args = parser.parse_args()
    if args.version != BALANCE_VERSION:
        raise SystemExit("FAIL: unknown balance version " + args.version)
    try:
        files = {k: v for k, v in outputs(load_sources(), overlay_bytes()).items() if k.startswith(PREFIXES)}
    except DataError as error:
        print("FAIL:", error, file=sys.stderr)
        return 1
    stale = write_or_check(files, args.check, BALANCE_DIRS)
    for path in stale:
        print("STALE:", path, file=sys.stderr)
    print(("checked " if args.check else "wrote ") + str(len(files)) + " balance files")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())

"""Validate committed balance: schema/cross-reference/range/provenance rules.

Without --strict this trusts the committed provenance and only re-checks rules; the P1 gate always uses --strict,
which also requires every generated file (and no orphan) to equal a fresh regeneration.
"""
import argparse
from decimal import Decimal
import json
import sys

from balance_lib import (BALANCE_DIRS, BALANCE_VERSION, REFERENCE_DIRS, ROOT, DataError, deep_dec, import_reference,
                         load_sources, outputs, overlay_bytes, validate, write_or_check)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="also require committed files to equal regeneration")
    args = parser.parse_args()
    try:
        sources = load_sources()
        records = import_reference(sources).items
        balance = json.loads((ROOT / f"data/balance/{BALANCE_VERSION}.json").read_text(encoding="utf-8"), parse_float=Decimal)
        provenance = json.loads((ROOT / f"data/balance/{BALANCE_VERSION}.provenance.json").read_text(encoding="utf-8"))
        for key in ("balanceHash", "overlayFileSha256"):
            balance.pop(key, None)
        errors = validate(deep_dec(balance), provenance, records)
        stale = write_or_check(outputs(sources, overlay_bytes()), True, REFERENCE_DIRS + BALANCE_DIRS) if args.strict else []
    except (DataError, OSError, ValueError, TypeError, KeyError) as error:
        print("FAIL:", error, file=sys.stderr)
        return 1
    for message in errors + ["stale generated file: " + path for path in stale]:
        print("FAIL:", message, file=sys.stderr)
    print("PASS" if not errors and not stale else "FAIL")
    return 0 if not errors and not stale else 1


if __name__ == "__main__":
    sys.exit(main())

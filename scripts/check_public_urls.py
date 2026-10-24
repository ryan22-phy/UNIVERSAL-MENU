"""Check public Raw text without executing it. No token or account required."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="v1.0.1")
    parser.add_argument("--report", type=Path, default=ROOT / "docs/github-check.json")
    args = parser.parse_args()
    if not args.ref or ".." in args.ref or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-" for char in args.ref):
        raise SystemExit("Invalid Git reference")
    results = []
    for relative in ("loader.luau", "dist/VWMenu.luau", "dist/manifest.json", "version.json", "smoke-test.luau"):
        url = "https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/" + quote(args.ref, safe="/") + "/" + relative
        record = {"path": relative, "url": url, "passed": False}
        try:
            with urlopen(Request(url, headers={"User-Agent": "VW-Menu-Public-Verification/1.0.1", "Cache-Control": "no-cache"}), timeout=25) as response:
                body = response.read(2 * 1024 * 1024 + 1)
                record["status"] = response.status
                if len(body) > 2 * 1024 * 1024:
                    raise ValueError("Response exceeded size limit")
                expected = (ROOT / relative).read_bytes()
                record["sha256"] = hashlib.sha256(body).hexdigest()
                record["bytes"] = len(body)
                record["exactContentMatch"] = body == expected
                record["passed"] = response.status == 200 and body == expected
        except (HTTPError, URLError, OSError, ValueError) as error:
            record["error"] = str(error)
        results.append(record)
        print(("PASS " if record["passed"] else "FAIL ") + url)
    report = {"timestampUTC": datetime.now(timezone.utc).isoformat(), "reference": args.ref,
              "scope": "Public HTTP status and exact local/remote file comparison; no code execution",
              "results": results, "passed": all(item["passed"] for item in results)}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

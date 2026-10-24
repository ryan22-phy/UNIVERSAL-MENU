"""Execute the real public loader and independent smoke test at Roblox boundaries.

Usage: python tests/run_loader_tests.py /path/to/luau[.exe]
These tests do not prove live Roblox rendering, HTTP access, or executor support.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    suite = (root / "tests/loader.spec.luau").read_text(encoding="utf-8")
    suite = suite.replace("-- @LOADER_SOURCE@", (root / "loader.luau").read_text(encoding="utf-8"))
    smoke = root / "smoke-test.luau"
    suite = suite.replace("-- @SMOKE_SOURCE@", smoke.read_text(encoding="utf-8") if smoke.exists() else 'error("smoke-test.luau missing")')
    executable = sys.argv[2] if len(sys.argv)>2 and sys.argv[1]=="--luau" else (sys.argv[1] if len(sys.argv)>1 else "luau")
    work = Path(os.environ.get("VW_LAB_TEST_WORK", str(root / "work"))).resolve()
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="vw-loader-tests-", dir=work) as directory:
        path = Path(directory) / "loader.generated.luau"
        path.write_text(suite, encoding="utf-8")
        return subprocess.run([executable, str(path)], check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())

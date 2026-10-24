"""Run combat/visual lifecycle tests with Roblox boundary doubles.

Usage: python tests/run_combat_tests.py /path/to/luau[.exe]
This validates client module behavior, not Roblox rendering or executor support.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    suite = (root / "tests/combat_visuals.spec.luau").read_text(encoding="utf-8")
    for marker, filename in (("AIM", "AimAssist.luau"), ("ESP", "ESPManager.luau")):
        source = (root / "src/client" / filename).read_text(encoding="utf-8")
        suite = suite.replace(f"-- @{marker}_SOURCE@", source)
    executable = sys.argv[1] if len(sys.argv) > 1 else "luau"
    work = Path(os.environ.get("VW_LAB_TEST_WORK", str(root / "work"))).resolve()
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="vw-combat-tests-", dir=work) as directory:
        path = Path(directory) / "combat_visuals.generated.luau"
        path.write_text(suite, encoding="utf-8")
        return subprocess.run([executable, str(path)], check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())

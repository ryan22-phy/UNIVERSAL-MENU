"""Compile and run local logic tests. Does not start Roblox Studio or an executor."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", required=True, help="Official luau CLI executable")
    parser.add_argument("--compiler", required=True, help="Official luau-compile executable")
    parser.add_argument("--work-dir", type=Path, default=ROOT / "work", help="Writable intermediate directory")
    args = parser.parse_args()
    luau, compiler = str(Path(args.luau).resolve()), str(Path(args.compiler).resolve())
    results = []
    work_dir=args.work_dir.resolve()
    work_dir.mkdir(parents=True, exist_ok=True)
    test_env=os.environ.copy()
    test_env["VW_LAB_TEST_WORK"]=str(work_dir)
    test_env["PYTHONDONTWRITEBYTECODE"]="1"

    def run(name: str, command: list[str]) -> bool:
        try:
            process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                     encoding="utf-8", errors="replace", timeout=90, env=test_env)
            output = (process.stdout + process.stderr).strip()
            passed = process.returncode == 0
            results.append({"name": name, "passed": passed, "exitCode": process.returncode, "output": output})
        except (OSError, subprocess.TimeoutExpired) as error:
            output, passed = str(error), False
            results.append({"name": name, "passed": False, "exitCode": None, "output": output})
        print(f'{"PASS" if passed else "FAIL"} {name}')
        if output and (not passed or not name.startswith("compile:")):
            print(output)
        return passed

    run("build", [sys.executable, str(ROOT / "scripts/build.py")])
    sources = sorted(ROOT.rglob("*.luau"))
    run(f"compile:all {len(sources)} Luau files", [compiler, "--null", *map(str, sources)])
    # combat_visuals is a lexical-injection fixture, run by its Python harness.
    standalone = [path for path in sorted((ROOT / "tests").glob("*.spec.luau"))
                  if path.name not in {"combat_visuals.spec.luau", "movement.spec.luau"}]
    run("logic:standalone suites", [luau, *map(str, standalone)])
    run("logic:combat_visuals", [sys.executable, str(ROOT / "tests/run_combat_tests.py"), luau])
    movement_runner = ROOT / "tests/run_movement_tests.py"
    if movement_runner.exists():
        run("logic:movement", [sys.executable, str(movement_runner), "--luau", luau])
    run("python:unittest", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py", "-v"])
    report = {"timestampUTC": datetime.now(timezone.utc).isoformat(),
              "scope": "Luau syntax and local logic with boundary doubles; Python build integrity",
              "robloxStudio": "NOT_CONNECTED_NOT_EXECUTED", "xeno": "NOT_EXECUTED",
              "serverReplication": "NOT_EXECUTED", "results": results,
              "sourceHashes": {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                               for path in sources},
              "passed": all(result["passed"] for result in results)}
    (ROOT / "docs/verification-results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f'{sum(r["passed"] for r in results)}/{len(results)} local verification steps passed')
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

"""Run real movement modules against explicit boundary doubles, never a physics emulator."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", help="Path to the standalone Luau CLI")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    runtime = args.luau or shutil.which("luau")
    if not runtime:
        parser.error("Provide --luau PATH or install luau on PATH")
    spec = (root / "tests/movement.spec.luau").read_text(encoding="utf-8")
    marker = "-- @PRODUCTION_MODULES@"
    if spec.count(marker) != 1:
        raise RuntimeError("Expected one lexical production-module insertion marker")
    blocks = []
    for name in ("SpeedController", "HealthDiagnostics", "FlightController"):
        source = (root / f"src/client/{name}.luau").read_text(encoding="utf-8")
        blocks.append(f"__Modules.{name} = (function()\n{source}\nend)()(nil)\n")
    # Source text is inserted verbatim. These are the real production factories;
    # only Roblox engine boundaries are doubled by locals declared in the spec.
    combined = spec.replace(marker, "\n".join(blocks))
    scratch_root = Path(os.environ.get("VW_LAB_TEST_WORK", str(root / "work")))
    scratch_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="vwmenu-movement-", dir=str(scratch_root)) as scratch:
        generated = Path(scratch) / "movement.generated.luau"
        generated.write_text(combined, encoding="utf-8")
        result = subprocess.run([runtime, str(generated)], cwd=str(root), check=False)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())

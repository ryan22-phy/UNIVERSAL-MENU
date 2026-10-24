"""Execute real bootstrap/shared sources with explicit Roblox service doubles."""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau",required=True)
    args=parser.parse_args()
    suite=(ROOT / "tests/bootstrap.spec.luau").read_text(encoding="utf-8")
    for marker,relative in {"CLEANUP":"src/shared/CleanupManager.luau", "CONFIG":"src/shared/ConfigManager.luau",
                            "DIAGNOSTICS":"src/shared/Diagnostics.luau", "BOOTSTRAP":"src/client/ClientController.luau"}.items():
        suite=suite.replace("-- @"+marker+"_SOURCE@",(ROOT / relative).read_text(encoding="utf-8"))
    work=Path(os.environ.get("VW_LAB_TEST_WORK",str(ROOT / "work"))).resolve()
    work.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="vw-bootstrap-",dir=work) as directory:
        path=Path(directory) / "bootstrap.generated.luau"
        path.write_text(suite,encoding="utf-8")
        return subprocess.run([args.luau,str(path)],check=False).returncode


if __name__=="__main__":
    raise SystemExit(main())

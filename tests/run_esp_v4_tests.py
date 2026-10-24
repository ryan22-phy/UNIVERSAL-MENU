"""Run the actual ESP source with standalone Roblox boundary doubles."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LUAU = Path(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("LUAU_BIN", ROOT.parent / "luau" / "luau.exe"))
template = (ROOT / "tests" / "esp_v4.spec.luau").read_text(encoding="utf-8")
source = (ROOT / "src" / "client" / "ESPManager.luau").read_text(encoding="utf-8")
assert template.count("-- @ESP_SOURCE@") == 1
generated = template.replace("-- @ESP_SOURCE@", source)
scratch = Path(os.environ.get("VW_LAB_TEST_WORK", ROOT / "work"))
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="esp-v4-", dir=scratch) as temporary:
    spec = Path(temporary) / "esp_v4.generated.luau"
    spec.write_text(generated, encoding="utf-8")
    result = subprocess.run([str(LUAU), str(spec)], check=False)
    raise SystemExit(result.returncode)

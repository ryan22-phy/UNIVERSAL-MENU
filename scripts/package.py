"""Create a release ZIP next to the project folder, excluding intermediates."""
import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {"__pycache__", ".git", "work", ".test-work"}


def main():
    destination = ROOT.parent / (ROOT.name + ".zip")
    files = sorted(path for path in ROOT.rglob("*") if path.is_file()
                   and not EXCLUDED.intersection(path.relative_to(ROOT).parts)
                   and path.suffix != ".pyc")
    report = ROOT / "docs/verification-results.json"
    if not report.exists():
        raise SystemExit("Run scripts/verify.py before packaging")
    import json
    evidence = json.loads(report.read_text(encoding="utf-8"))
    if not evidence["passed"]:
        raise SystemExit("Verification report contains failures; refusing release package")
    for relative, expected in evidence.get("sourceHashes", {}).items():
        if hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() != expected:
            raise SystemExit("Source changed since verification: " + relative)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            info = zipfile.ZipInfo((Path(ROOT.name) / path.relative_to(ROOT)).as_posix(), (2026, 10, 24, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, path.read_bytes())
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert len(archive.infolist()) == len(files)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    print(f"Packaged {len(files)} files: {destination.name} ({destination.stat().st_size} bytes)")
    print(f"SHA256 {digest}")


if __name__ == "__main__":
    main()

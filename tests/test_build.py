"""Build integrity tests; these do not simulate the Roblox engine."""
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("vw_build", ROOT / "scripts" / "build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class BuildTests(unittest.TestCase):
    def test_deterministic_bundle(self):
        first = build.build()
        content = (ROOT / first["bundle"]).read_bytes()
        second = build.build()
        self.assertEqual(first, second)
        self.assertEqual(content, (ROOT / second["bundle"]).read_bytes())
        self.assertEqual(hashlib.sha256(content).hexdigest(), second["sha256"])

    def test_no_server_policy_in_client(self):
        modules = build.sources()
        self.assertNotIn("config/ServerPolicy", modules)
        self.assertFalse(any(name.startswith("server/") for name in modules))
        self.assertNotIn(".client", " ".join(modules))

    def test_module_graph_is_closed(self):
        modules = build.sources()
        self.assertGreaterEqual(len(modules), 13)
        self.assertIn("client/ClientController", modules)
        self.assertEqual(build.bundle(modules).count('return import("client/ClientController").Start()'), 1)

    def test_json_artifacts(self):
        for path in [ROOT / "version.json", ROOT / "config.example.json", ROOT / "default.project.json"]:
            with self.subTest(path=path.name):
                self.assertIsInstance(json.loads(path.read_text(encoding="utf-8-sig")), dict)

    def test_rojo_paths_exist_and_server_policy_is_private(self):
        project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
        def paths(node):
            found = []
            for key, value in node.items():
                if key == "$path":
                    self.assertTrue((ROOT / value).exists(), value)
                    found.append(value)
                elif isinstance(value, dict):
                    found.extend(paths(value))
            return found
        paths(project["tree"])
        replicated = paths(project["tree"]["ReplicatedStorage"])
        self.assertFalse(any(value.startswith("src/server/") or value == "src/server"
                             or value == "src/config/ServerPolicy.luau" for value in replicated))


if __name__ == "__main__":
    unittest.main(verbosity=2)

"""The helper scripts read the model catalog the shell reads: the package's
file, or the copy bundled with the shell when that one cannot be used."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

import catalog_loader  # noqa: E402


def catalog(model, version=1):
    return {"schemaVersion": version, "scripts": {"translate": {"model": model, "thinkingLevel": ""}}}


class CatalogLoaderTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.system = Path(folder.name, "system.json")
        self.bundled = Path(folder.name, "bundled.json")
        self.bundled.write_text(json.dumps(catalog("bundled-model")))
        for name, path in (("SYSTEM_CATALOG_PATH", self.system), ("BUNDLED_CATALOG_PATH", self.bundled)):
            patch = mock.patch.object(catalog_loader, name, str(path))
            patch.start()
            self.addCleanup(patch.stop)
        patch = mock.patch.dict(os.environ)
        patch.start()
        self.addCleanup(patch.stop)
        os.environ.pop("MAINSTREAM_AI_CATALOG_PATH", None)

    def model(self):
        return catalog_loader.get_string("scripts.translate.model", "inline-default")

    def test_the_package_catalog_is_read_before_the_bundled_copy(self):
        self.system.write_text(json.dumps(catalog("package-model")))
        self.assertEqual(self.model(), "package-model")

    def test_a_package_catalog_that_cannot_be_used_leaves_the_bundled_copy(self):
        cases = {
            "missing": None,
            "not JSON": "{broken",
            "not an object": "[]",
            "a newer schema": json.dumps(catalog("newer", version=2)),
            "a schema given as text": json.dumps(catalog("text", version="1")),
            "a schema given as true": json.dumps(catalog("true", version=True)),
        }
        for name, text in cases.items():
            with self.subTest(name):
                self.system.unlink(missing_ok=True)
                if text is not None:
                    self.system.write_text(text)
                self.assertEqual(self.model(), "bundled-model")

    def test_the_override_path_stands_in_for_the_package_catalog(self):
        self.system.write_text(json.dumps(catalog("package-model")))
        override = self.system.with_name("override.json")
        os.environ["MAINSTREAM_AI_CATALOG_PATH"] = str(override)
        self.assertEqual(self.model(), "bundled-model")
        override.write_text(json.dumps(catalog("override-model")))
        self.assertEqual(self.model(), "override-model")

    def test_a_value_the_package_catalog_lacks_comes_from_the_bundled_copy(self):
        self.system.write_text(json.dumps({"schemaVersion": 1, "scripts": {"translate": {"model": 7}, "older": {}}}))
        self.bundled.write_text(json.dumps({"schemaVersion": 1, "scripts": {
            "translate": {"model": "bundled-model"}, "newer": {"model": "bundled-newer"}}}))
        self.assertEqual(self.model(), "bundled-model")
        self.assertEqual(catalog_loader.load_script_config("newer"), {"model": "bundled-newer"})
        self.assertEqual(catalog_loader.load_script_config("older"), {})

    def test_a_value_that_is_missing_or_not_text_gives_the_default(self):
        self.system.write_text(json.dumps({"schemaVersion": 1, "scripts": {"translate": {
            "model": "  padded-model \n", "thinkingLevel": "", "limit": 3}}}))
        self.assertEqual(self.model(), "padded-model")
        self.assertEqual(catalog_loader.get_string("scripts.translate.limit", "d"), "d")
        self.assertEqual(catalog_loader.get_string("scripts.translate.model.deeper", "d"), "d")
        self.assertEqual(catalog_loader.get_string("scripts.absent.model", "d"), "d")
        self.assertEqual(catalog_loader.get_string("scripts.translate.thinkingLevel", "d"), "d")
        self.assertEqual(catalog_loader.get_string("scripts.translate.thinkingLevel", "d", allow_empty=True), "")
        self.assertEqual(catalog_loader.load_script_config("absent"), {})

    def test_no_catalog_at_all_gives_the_default(self):
        self.bundled.unlink()
        self.assertEqual(self.model(), "inline-default")
        self.assertEqual(catalog_loader.load_script_config("translate"), {})

    def test_the_command_prints_the_value_for_the_shell_scripts(self):
        override = self.system.with_name("override.json")
        override.write_text(json.dumps(catalog("command-model")))
        env = {**os.environ, "MAINSTREAM_AI_CATALOG_PATH": str(override), "PYTHONDONTWRITEBYTECODE": "1"}
        run = lambda *args: subprocess.run([sys.executable, str(SCRIPTS / "catalog_loader.py"), *args],
                                           env=env, capture_output=True, text=True)
        self.assertEqual(run("get", "scripts.translate.model", "d").stdout, "command-model\n")
        self.assertEqual(run("get", "scripts.translate.thinkingLevel", "low").stdout, "low\n")
        self.assertEqual(run("get", "--allow-empty", "scripts.translate.thinkingLevel", "low").stdout, "\n")
        self.assertEqual(run("get").returncode, 2)

    def test_the_shipped_catalog_holds_every_value_the_scripts_ask_for(self):
        shipped = json.loads((SCRIPTS.parents[1] / "defaults/ai/models.json").read_text())["scripts"]
        self.assertTrue(shipped["translate"]["model"])
        self.assertIn("thinkingLevel", shipped["translate"])
        self.assertTrue(shipped["wallpaperCategorize"]["model"])
        self.assertTrue(shipped["liveTranscribe"]["model"])
        self.assertRegex(shipped["liveTranscribe"]["apiVersion"], r"^[A-Za-z0-9_]+$")
        usage = shipped["geminiUsage"]
        self.assertTrue(usage["userAgent"] and usage["generalFallback"])
        for bucket in usage["buckets"]:
            self.assertTrue(bucket["match"] and bucket["preferred"])


if __name__ == "__main__":
    unittest.main()

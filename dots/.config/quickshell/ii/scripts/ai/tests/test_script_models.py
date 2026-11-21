"""Each helper script takes its model from the catalog, and still works on the
values it shipped with when the catalog cannot be read."""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parents[1]
SHIPPED = SCRIPTS.parents[1] / "defaults/ai/models.json"


def load(script, catalog_path):
    """The script as a module, reading the given catalog while it loads."""
    spec = importlib.util.spec_from_file_location(script.replace("-", "_").removesuffix(".py"), SCRIPTS / script)
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(os.environ, {"MAINSTREAM_AI_CATALOG_PATH": str(catalog_path)}):
        spec.loader.exec_module(module)
        if hasattr(module, "load_usage_config"):
            module.config = module.load_usage_config()
    return module


class CatalogCase(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)

    def catalog(self, scripts):
        path = self.root / "catalog.json"
        path.write_text(json.dumps({"schemaVersion": 1, "scripts": scripts}))
        return path


class UsageTests(CatalogCase):
    def quota(self, used):
        return {"quotaInfo": {"remainingFraction": 1 - used, "resetTime": "2026-11-20T03:00:00Z"}}

    def test_a_model_without_its_own_quota_reads_as_spent_or_falls_back_as_the_catalog_says(self):
        usage = load("gemini-usage.py", SHIPPED)
        models = {"gemini-4-hydrogen-sonar": self.quota(0.2)}
        for model in ("gemini-4-argon", "gemini-4-carbon"):
            with self.subTest(model):
                self.assertEqual(usage.select_quota(models, model, usage.config)["session"],
                                 {"utilization": 100.0, "resets_at": None})
        self.assertEqual(usage.select_quota(models, "gemini-4-neon", usage.config)["session"]["utilization"], 20.0)
        self.assertEqual(usage.select_quota(models, "", usage.config)["session"]["utilization"], 20.0)

    def user_agent_sent(self, usage):
        sent = []

        class Reply:
            def __enter__(self): return self
            def __exit__(self, *exc): return False
            def read(self): return b'{"models": {}}'

        def urlopen(request, timeout=None):
            sent.append(request.get_header("User-agent"))
            return Reply()

        with mock.patch.object(usage, "get_credentials", return_value=("token", "")), \
                mock.patch.object(usage.urllib.request, "urlopen", urlopen), \
                mock.patch.dict(os.environ, {"MAINSTREAM_AI_CATALOG_PATH": str(self.root / "catalog.json")}):
            usage.usage("gemini-4-neon")
        return sent

    def test_the_quota_request_names_the_agent_the_catalog_gives(self):
        usage = load("gemini-usage.py", self.catalog({"geminiUsage": {"userAgent": "agent/9"}}))
        self.assertEqual(self.user_agent_sent(usage), ["agent/9"])

    def test_without_a_usable_catalog_entry_the_shipped_agent_is_named_and_every_model_shares_one_quota(self):
        usage = load("gemini-usage.py", self.catalog({"geminiUsage": {"buckets": "not a list", "generalFallback": 4}}))
        self.assertEqual(self.user_agent_sent(usage), [usage.USER_AGENT])
        self.assertEqual(usage.config["buckets"], [])
        models = {"anything": self.quota(0.4)}
        self.assertEqual(usage.select_quota(models, "gemini-4-argon", usage.config)["session"]["utilization"], 40.0)

    def test_an_entry_the_catalog_gets_wrong_is_left_out_and_the_rest_answer(self):
        usage = load("gemini-usage.py", self.catalog({"geminiUsage": {"generalFallback": ["general"], "buckets": [
            {"preferred": ["no-match-key"]}, "not an entry", {"match": "flash", "preferred": None},
            {"match": "flash", "preferred": ["flash-quota"]}]}}))
        self.assertEqual(len(usage.config["buckets"]), 1)
        models = {"general": self.quota(0.5), "flash-quota": self.quota(0.1)}
        self.assertEqual(usage.select_quota(models, "gemini-3.8-flash", usage.config)["session"]["utilization"], 10.0)

    def test_a_model_family_only_the_catalog_knows_finds_its_quota(self):
        usage = load("gemini-usage.py", self.catalog({"geminiUsage": {
            "userAgent": "agent/9",
            "generalFallback": ["general"],
            "buckets": [{"match": "Nova", "preferred": ["gemini-5-nova"], "substrKey": "nova", "missingMeansExhausted": True}],
        }}))
        self.assertEqual(usage.config["userAgent"], "agent/9")
        models = {"general": self.quota(0.5), "gemini-5-nova": self.quota(0.25), "gemini-5-nova-high": self.quota(0.75)}
        self.assertEqual(usage.select_quota(models, "gemini-5-nova", usage.config)["session"]["utilization"], 25.0)
        del models["gemini-5-nova"]
        self.assertEqual(usage.select_quota(models, "gemini-5-nova", usage.config)["session"]["utilization"], 75.0)
        del models["gemini-5-nova-high"]
        self.assertEqual(usage.select_quota(models, "gemini-5-nova", usage.config)["session"]["utilization"], 100.0)
        self.assertEqual(usage.select_quota(models, "gemini-9-other", usage.config)["session"]["utilization"], 50.0)


class TranscribeTests(CatalogCase):
    def test_the_catalog_names_the_model_and_api_version(self):
        dictation = load("live-transcribe.py", self.catalog({"liveTranscribe": {"model": "models/next-live", "apiVersion": "v1beta"}}))
        self.assertEqual(dictation.SETUP["setup"]["model"], "models/next-live")
        self.assertIn(".v1beta.GenerativeService.", dictation.ENDPOINT)

    def test_a_value_the_catalog_gets_wrong_leaves_the_shipped_one(self):
        shipped = load("live-transcribe.py", self.root / "absent.json")
        for name, entry in {
            "an API version that would change the address": {"apiVersion": "v1/../x"},
            "an API version ending in a line break": {"apiVersion": "v1beta\n"},
            "values that are not text": {"apiVersion": 2, "model": ["x"]},
            "an empty model": {"model": ""},
        }.items():
            with self.subTest(name):
                dictation = load("live-transcribe.py", self.catalog({"liveTranscribe": entry}))
                self.assertEqual(dictation.ENDPOINT, shipped.ENDPOINT)
                self.assertEqual(dictation.SETUP, shipped.SETUP)
        self.assertIn(".v1alpha.GenerativeService.", shipped.ENDPOINT)


@unittest.skipUnless(shutil.which("jq"), "needs jq")
class TranslateTests(CatalogCase):
    def setUp(self):
        super().setUp()
        self.script = self.root / "ii/scripts/ai/gemini-translate.sh"
        self.script.parent.mkdir(parents=True)
        self.script.write_bytes((SCRIPTS / "gemini-translate.sh").read_bytes())
        tools = self.root / "ii/translations/tools"
        tools.mkdir(parents=True)
        (tools.parent / "en_US.json").write_text('{"Hello": "Hello"}')
        self.tool(tools / "manage-translations.sh", "#!/bin/sh\nexit 0\n")
        config = self.root / "config/illogical-impulse"
        config.mkdir(parents=True)
        (config / "config.json").write_text('{"language": {"ui": "en_US"}}')
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.tool(self.bin / "secret-tool", "#!/bin/sh\necho '{\"apiKeys\":{\"gemini\":\"test-key\"}}'\n")
        self.tool(self.bin / "notify-send", "#!/bin/sh\nexit 0\n")
        self.request = self.root / "request"
        self.tool(self.bin / "curl", '#!/bin/sh\nprintf \'%s\\n\' "$1" > "$REQUEST"\n'
                  'while [ $# -gt 0 ]; do [ "$1" = -d ] && printf \'%s\\n\' "$2" >> "$REQUEST"; shift; done\n'
                  'printf \'%s\' \'{"candidates":[{"content":{"parts":[{"text":"{\\"Hello\\": \\"Hola\\"}"}]}}]}\'\n')

    def tool(self, path, text):
        path.write_text(text)
        path.chmod(0o755)

    def translate(self, *model, catalog=None, loader=True, env_model=None):
        if loader:
            shutil.copy(SCRIPTS / "catalog_loader.py", self.script.parent)
        env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "REQUEST": str(self.request),
               "XDG_CONFIG_HOME": str(self.root / "config"), "PYTHONDONTWRITEBYTECODE": "1",
               "MAINSTREAM_AI_CATALOG_PATH": str(catalog or self.root / "absent.json")}
        env.pop("GEMINI_MODEL", None)
        if env_model:
            env["GEMINI_MODEL"] = env_model
        subprocess.run(["bash", str(self.script), "es_MX", *model], env=env, cwd="/", check=True, capture_output=True)
        url, payload = self.request.read_text().split("\n", 1)
        thinking = json.loads(payload)["generationConfig"].get("thinkingConfig", {}).get("thinkingLevel")
        return url.rsplit("/", 1)[1].removesuffix(":generateContent"), thinking

    def test_the_catalog_names_the_model_and_its_thinking_level(self):
        catalog = self.catalog({"translate": {"model": "gemini-5-flash", "thinkingLevel": "medium"}})
        self.assertEqual(self.translate(catalog=catalog), ("gemini-5-flash", "medium"))
        catalog = self.catalog({"translate": {"model": "gemini-5-flash", "thinkingLevel": ""}})
        self.assertEqual(self.translate(catalog=catalog), ("gemini-5-flash", None))

    def test_a_model_passed_in_stands_over_the_catalog(self):
        catalog = self.catalog({"translate": {"model": "gemini-5-flash", "thinkingLevel": "medium"}})
        self.assertEqual(self.translate("gemini-4-neon", catalog=catalog), ("gemini-4-neon", "low"))
        self.assertEqual(self.translate("gemini-3.1-pro", catalog=catalog), ("gemini-3.1-pro", "low"))
        self.assertEqual(self.translate("gemini-2.5-flash", catalog=catalog), ("gemini-2.5-flash", None))
        self.assertEqual(self.translate(catalog=catalog, env_model="gemini-2.5-pro"), ("gemini-2.5-pro", None))
        self.assertEqual(self.translate("gemini-4-neon", catalog=catalog, env_model="gemini-2.5-pro"), ("gemini-4-neon", "low"))

    def test_without_a_catalog_or_its_reader_the_shipped_model_is_used(self):
        self.assertEqual(self.translate(loader=False), ("gemini-3.8-flash", "low"))
        self.assertEqual(json.loads((self.root / "config/illogical-impulse/translations/es_MX.json").read_text()),
                         {"Hello": "Hola"})


@unittest.skipUnless(shutil.which("jq"), "needs jq")
class WallpaperTests(CatalogCase):
    def setUp(self):
        super().setUp()
        self.script = self.root / "ii/scripts/ai/gemini-categorize-wallpaper.sh"
        self.script.parent.mkdir(parents=True)
        self.script.write_bytes((SCRIPTS / "gemini-categorize-wallpaper.sh").read_bytes())
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.request = self.root / "request"
        # The script resizes into a fixed path under /tmp that the running shell
        # shares, so the tools that would write there do nothing here.
        for name, text in {
            "secret-tool": "echo '{\"apiKeys\":{\"gemini\":\"test-key\"}}'",
            "mkdir": "exit 0", "magick": "exit 0", "base64": "echo aW1hZ2U=",
            "curl": 'printf \'%s\' "$1" > "$REQUEST"\n'
                    'printf \'%s\' \'{"candidates":[{"content":{"parts":[{"text":"\\"city\\""}]}}]}\'',
        }.items():
            (self.bin / name).write_text(f"#!/bin/sh\n{text}\n")
            (self.bin / name).chmod(0o755)

    def categorize(self, *model, catalog=None, loader=True):
        if loader:
            shutil.copy(SCRIPTS / "catalog_loader.py", self.script.parent)
        env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "REQUEST": str(self.request),
               "PYTHONDONTWRITEBYTECODE": "1", "MAINSTREAM_AI_CATALOG_PATH": str(catalog or self.root / "absent.json")}
        env.pop("GEMINI_WALLPAPER_MODEL", None)
        run = subprocess.run(["bash", str(self.script), "wallpaper.png", *model], env=env, cwd="/",
                             check=True, capture_output=True, text=True)
        self.assertEqual(run.stdout, "city\n")
        return self.request.read_text().rsplit("/", 1)[1].removesuffix(":generateContent")

    def test_the_catalog_names_the_model_unless_one_is_passed_in(self):
        catalog = self.catalog({"wallpaperCategorize": {"model": "gemini-5-lite"}})
        self.assertEqual(self.categorize(catalog=catalog), "gemini-5-lite")
        self.assertEqual(self.categorize("gemini-2.5-flash", catalog=catalog), "gemini-2.5-flash")

    def test_without_a_catalog_or_its_reader_the_shipped_model_is_used(self):
        self.assertEqual(self.categorize(), "gemini-3.5-flash-lite")
        (self.script.parent / "catalog_loader.py").unlink()
        self.assertEqual(self.categorize(loader=False), "gemini-3.5-flash-lite")


if __name__ == "__main__":
    unittest.main()

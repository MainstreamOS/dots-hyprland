"""Regression tests for catalog checks; never modify any catalog."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("catalog_qa", Path(__file__).with_name("catalog-qa.py"))
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)


class CatalogChecks(unittest.TestCase):
    def errors(self, key, value):
        return [error for _, error in qa.check({key: key}, {key: value})]

    def test_key_drift_report_is_deterministic(self):
        self.assertEqual(qa.check({'Z': 'Z', 'B': 'B', 'A': 'A'}, {'D': 'D', 'C': 'C'}),
                         [('A', 'missing key'), ('B', 'missing key'), ('Z', 'missing key'),
                          ('C', 'extra key'), ('D', 'extra key')])

    def test_qt_arguments_can_move_but_not_disappear(self):
        self.assertEqual(self.errors("Send %1 files to %2", "Archivos enviados a %2: %1"), [])
        self.assertIn("placeholders", self.errors("Send %1 files to %2", "Enviar a %2"))

    def test_printf_argument_types_keep_their_order(self):
        self.assertIn("printf argument order", self.errors("%s: %d files", "%d archivos: %s"))

    def test_real_newlines_are_not_literal_escape_text(self):
        self.assertIn("newline count", self.errors("Line 1\nLine 2", "Línea 1\\nLínea 2"))
        self.assertIn("joining whitespace", self.errors("You: ", "Tú:"))

    def test_markup_and_executable_examples_are_preserved(self):
        self.assertIn("markup order", self.errors("<b><i>Delete</i></b>", "<i><b>Eliminar</b></i>"))
        self.assertIn("code", self.errors("Run `pacman -Syu`", "Ejecuta `pacman -Sy`"))
        self.assertIn("command flags", self.errors("Use --skip-system", "Usa --omitir-sistema"))

    def test_urls_do_not_include_following_punctuation(self):
        self.assertEqual(self.errors("See [docs](https://example.com) for help", "Consulta [docs](https://example.com), para ayuda"), [])

    def test_protected_names_work_next_to_cjk_text(self):
        self.assertEqual(self.errors("Enable Wi-Fi", "啟用Wi-Fi"), [])
        self.assertIn("protected name: Wi-Fi", self.errors("Enable Wi-Fi", "啟用網路"))

    def test_paths_and_urls_end_at_cjk_punctuation(self):
        self.assertEqual(self.errors("Path (~/Pictures/Screenshots)", "路径（~/Pictures/Screenshots）"), [])
        self.assertEqual(self.errors("Read /etc/fstab.", "读取「/etc/fstab」。"), [])
        self.assertEqual(self.errors("Refreshing /etc/skel...", "正在刷新 /etc/skel…"), [])
        self.assertEqual(self.errors("See https://example.com.", "参见 https://example.com。"), [])
        self.assertEqual(self.errors("See www.example.com", "参见【www.example.com】"), [])
        self.assertIn("paths", self.errors("Path (~/Pictures/Screenshots)", "路径（~/Pictures/Other）"))
        self.assertIn("URLs", self.errors("See https://example.com", "参见 https://other.com。"))

    def test_german_compounds_and_key_names_are_valid(self):
        self.assertEqual(self.errors("API key", "API-Schlüssel"), [])
        self.assertEqual(self.errors("Google's model", "Googles Modell"), [])
        self.assertEqual(self.errors('"Locked" text', '"Gesperrt"-Text'), [])
        self.assertEqual(self.errors("10 % window", "10-%-Fenster"), [])
        self.assertEqual(self.errors("[mainstream] key", "[mainstream]-Schlüssel"), [])
        self.assertEqual(self.errors("Ctrl+Shift+Delete", "Strg+Umschalt+Entf"), [])
        self.assertIn("shortcuts", self.errors("Ctrl+O", "Strg+P"))
        self.assertEqual(self.errors("Press Ctrl+L.", "Ctrl+L drücken."), [])
        self.assertIn("shortcuts", self.errors("Super+.", "Super+P"))
        self.assertIn("protected name: Steam", self.errors("Open Steam", "SteamVR öffnen"))
        self.assertIn("protected name: MODEL", self.errors("Use /model MODEL", "Nutze /model MODELs"))
        self.assertIn("command flags", self.errors("Use -Syu", "Nutze -Sy"))

    def test_paths_and_numbers_cannot_change(self):
        self.assertIn("paths", self.errors("Read /etc/fstab", "Leer /etc/otro"))
        self.assertIn("numeric values", self.errors("Limit 128", "Límite 256"))
        self.assertEqual(self.errors("Use 15MB", "Usa 15 MB"), [])

    def test_decimal_and_grouping_punctuation_can_be_localized(self):
        self.assertEqual(self.errors("1.0 and 50,000", "1,0 e 50.000"), [])
        self.assertEqual(self.errors("0.003 and 3", "3 e 0,003"), [])
        self.assertEqual(self.errors("50,000 characters", "50\u202f000 caractères"), [])
        self.assertEqual(self.errors("Address 1.1.1.1", "Adresse 1.1.1.1"), [])
        self.assertIn("numeric values", self.errors("0.003 and 3", "3 e 3"))

    def test_numbers_can_touch_japanese_text(self):
        self.assertEqual(self.errors("0 to 2, default 0.5", "範囲は0〜2、既定値は0.5です"), [])
        self.assertEqual(self.errors("50,000 characters", "50,000文字"), [])
        self.assertIn("numeric values", self.errors("Limit 128", "上限は256文字"))

    def test_empty_values_and_key_drift_fail(self):
        self.assertIn("empty or non-string value", self.errors("Hello", ""))
        self.assertEqual({error for _, error in qa.check({"Hello": "Hello"}, {"Other": "Otro"})}, {"missing key", "extra key"})

    def test_duplicate_keys_fail_before_validation(self):
        with self.assertRaises(ValueError):
            qa.unique_object([("Hello", "Hola"), ("Hello", "Otro")])


if __name__ == "__main__":
    unittest.main()

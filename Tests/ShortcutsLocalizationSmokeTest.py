#!/usr/bin/env python3
"""Check Shortcuts' dedicated English and Spanish localization contracts."""

from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parent.parent
QUOTED = r'"(?:[^"\\]|\\.)*"'
PLACEHOLDER = re.compile(r"\$\{[A-Za-z_]\w*\}")
INTENT_NAMES = {
    "OpenMovieIntent",
    "SendMovieToAppleTVIntent",
    "AddMovieToPlaylistIntent",
    "PauseAirCillerIntent",
    "ResumeAirCillerIntent",
    "StopAirCillerIntent",
}


def load_table(language):
    path = ROOT / "Resources" / f"{language}.lproj" / "Shortcuts.strings"
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    table = json.loads(result.stdout)
    source = path.read_text(encoding="utf-8")
    declared_keys = [
        json.loads(value)
        for value in re.findall(rf"^\s*({QUOTED})\s*=", source, re.MULTILINE)
    ]
    if len(declared_keys) != len(set(declared_keys)):
        raise ValueError(f"Duplicate keys in {language} Shortcuts.strings")
    if set(declared_keys) != set(table):
        raise ValueError(f"Unrecognized string declarations in {language} Shortcuts.strings")
    return table


class ShortcutsLocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tables = {language: load_table(language) for language in ("en", "es")}
        cls.intents = (ROOT / "Sources" / "ShortcutsIntents.swift").read_text(encoding="utf-8")
        cls.controller = (ROOT / "Sources" / "ShortcutsController.swift").read_text(encoding="utf-8")

    def assert_localized(self, keys):
        keys = tuple(keys)
        for language, table in self.tables.items():
            for key in keys:
                with self.subTest(language=language, key=key):
                    self.assertIn(key, table)
                    self.assertIsInstance(table[key], str)
                    self.assertTrue(table[key].strip())

    def test_exact_key_parity_and_valid_values(self):
        self.assertEqual(set(self.tables["en"]), set(self.tables["es"]))
        self.assert_localized(self.tables["en"])

    def test_all_six_intents_have_localized_static_titles(self):
        names = set(re.findall(r"struct\s+(\w+)\s*:\s*AppIntent\s*\{", self.intents))
        self.assertEqual(names, INTENT_NAMES)
        titles = re.findall(
            rf"static\s+let\s+title\s*=\s*LocalizedStringResource\(\s*({QUOTED}),\s*table:\s*\"Shortcuts\"\s*\)",
            self.intents,
        )
        self.assertEqual(len(titles), len(INTENT_NAMES))
        self.assertEqual(len(set(titles)), len(INTENT_NAMES))
        self.assert_localized(json.loads(title) for title in titles)

    def test_source_resources_are_present(self):
        literals = re.findall(
            rf"LocalizedStringResource\(\s*({QUOTED}),\s*table:\s*\"Shortcuts\"\s*\)",
            self.intents,
        )
        self.assertGreater(len(literals), len(INTENT_NAMES))
        self.assert_localized(json.loads(literal) for literal in literals)

    def test_all_controller_failure_keys_are_present(self):
        match = re.search(
            r"enum\s+ShortcutsFailure\s*:\s*String,\s*LocalizedError\s*\{(.*?)\n\s*var\s+errorDescription",
            self.controller,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "The ShortcutsFailure contract was not found")
        errors = re.findall(rf"\bcase\s+\w+\s*=\s*({QUOTED})", match.group(1))
        cases = re.findall(r"\bcase\s+\w+", match.group(1))
        self.assertGreater(len(errors), 0)
        self.assertEqual(len(errors), len(cases), "Each failure must declare a localizable raw value")
        self.assert_localized(json.loads(error) for error in errors)

    def test_parameter_summaries_preserve_placeholders(self):
        summaries = re.findall(rf"Summary\(\s*({QUOTED}),\s*table:\s*\"Shortcuts\"", self.intents)
        self.assertEqual(len(summaries), 3)
        keys = []
        for literal in summaries:
            translated_interpolation = re.sub(
                r"\\\(\\\.\$([A-Za-z_]\w*)\)",
                lambda match: "${" + match.group(1) + "}",
                literal,
            )
            keys.append(json.loads(translated_interpolation))
        self.assert_localized(keys)
        for key in keys:
            expected = Counter(PLACEHOLDER.findall(key))
            self.assertTrue(expected)
            for language, table in self.tables.items():
                with self.subTest(language=language, key=key):
                    self.assertEqual(Counter(PLACEHOLDER.findall(table[key])), expected)


if __name__ == "__main__":
    unittest.main()

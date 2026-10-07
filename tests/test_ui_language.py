import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "bin" / "taskwarrior-time"


class UiLanguageSettingsTest(unittest.TestCase):
    def test_spanish_language_choice_is_persisted_privately(self):
        with tempfile.TemporaryDirectory() as home:
            env = dict(os.environ, HOME=home)
            result = subprocess.run(
                [str(HELPER), "settings-set", "--ui-language", "es"],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            self.assertEqual(json.loads(result.stdout)["uiLanguage"], "es")
            settings = Path(home) / ".local/share/taskwarrior-time/ui-settings.json"
            self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)
            self.assertEqual(json.loads(settings.read_text())["uiLanguage"], "es")


if __name__ == "__main__":
    unittest.main()

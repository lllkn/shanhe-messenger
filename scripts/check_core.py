"""Run the source-only checks in a temporary, credential-free project copy."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot 4.7.2 executable")
    args = parser.parse_args()
    executable = shutil.which(args.godot)
    if not executable:
        parser.error("Godot executable not found")
    environment = os.environ.copy()
    for name in ("BIGMODEL_API_KEY", "ZHIPU_API_KEY", "LLM_API_KEY"):
        environment.pop(name, None)
    # Unique project identity isolates Godot user:// on every supported OS.
    identity = "shanhe-core-test-" + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="shanhe-core-") as temporary:
        game = Path(temporary) / "game"
        shutil.copytree(ROOT / "game", game, ignore=shutil.ignore_patterns(".godot", "__pycache__", "private", "*.log"))
        config = game / "project.godot"
        text = re.sub(r'^config/name=.*$', 'config/name="' + identity + '"', config.read_text(), flags=re.M)
        config.write_text(text)
        data_path = game / "data/puzzles.json"
        data = json.loads(data_path.read_text())
        # Even an accidentally triggered default request stays on loopback.
        data["dali"]["llm"]["endpoint"] = "http://127.0.0.1:1/offline"
        data_path.write_text(json.dumps(data, ensure_ascii=False))
        environment["XDG_DATA_HOME"] = str(Path(temporary) / "data")
        commands = [
            ("editor import", [executable, "--headless", "--editor", "--path", str(game), "--quit"]),
            ("main menu smoke", [executable, "--headless", "--path", str(game), "--quit-after", "30"]),
            ("offline LLM", [executable, "--headless", "--path", str(game), "res://tests/PatternLlmTest.tscn", "--", "--llm-offline"]),
            ("HTTP failures", [sys.executable, str(game / "tests/pattern_llm_mock.py"), executable]),
            ("SSE failures", [sys.executable, str(game / "tests/pattern_llm_mock.py"), executable, "PatternStreamTest.tscn"]),
        ]
        failures = 0
        try:
            for label, command in commands:
                result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=150)
                output = result.stdout + result.stderr
                invalid = result.returncode != 0 or any(marker in output for marker in ("SCRIPT ERROR:", "Parse Error:", "ERROR:", "FAIL ", "FAIL:"))
                failures += int(invalid)
                print(("FAIL " if invalid else "PASS ") + label, flush=True)
                for line in output.splitlines():
                    if line.startswith(("PASS ", "FAIL", "Pattern ", "MOCK HTTP")) or "ERROR:" in line:
                        print("  " + line)
                if invalid:
                    print(output[-16000:])
        finally:
            # Only remove the uniquely named test directory created by this run.
            if sys.platform == "darwin":
                userdata = Path.home() / "Library/Application Support/Godot/app_userdata" / identity
            elif os.name == "nt":
                userdata = Path(environment.get("APPDATA", "")) / "Godot/app_userdata" / identity
            else:
                userdata = Path(environment["XDG_DATA_HOME"]) / "godot/app_userdata" / identity
            if userdata.exists():
                shutil.rmtree(userdata)
        print(f"Core check groups=5; failed={failures}")
        return bool(failures)


if __name__ == "__main__":
    sys.exit(main())

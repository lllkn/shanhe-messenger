"""Audit publishable text files; never print credential values."""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EXTENSIONS = {".gd", ".gdshader", ".tscn", ".tres", ".uid", ".json", ".md", ".py", ".cfg", ".godot", ".example"}
SPECIAL = {".gitignore", ".gitattributes"}
PRIVATE_DIRS = {"private", "secrets", "credentials", "drafts", "history", "inbox", "tmp", "output", "board", ".openai", ".workbuddy"}
GENERATED = {".git", ".godot", "__pycache__", ".venv"}
PERSONAL_PATH = re.compile(r"/(?:Users|home)/[A-Za-z0-9_\u4e00-\u9fff.-]+/")
PRIVATE_KEY = re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")
TOKEN = re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16})")
ASSIGNMENT = re.compile(r'''(?i)["']?(?:api_key|access_token|client_secret|password)["']?\s*[:=]\s*["']([^"'\n]{8,})["']''')


def public_files():
    if (ROOT / ".git").is_dir():
        result = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT, check=True, capture_output=True)
        return sorted({ROOT / p.decode() for p in result.stdout.split(b"\0") if p})
    return sorted(p for p in ROOT.rglob("*") if p.is_file() and not GENERATED.intersection(p.relative_to(ROOT).parts))


def main():
    errors = []
    files = public_files()
    for path in files:
        relative = path.relative_to(ROOT)
        label = relative.as_posix()
        if path.is_symlink() or not path.is_file():
            errors.append(f"{label}: symlink or missing file")
            continue
        if PRIVATE_DIRS.intersection(relative.parts) or path.name in {"llm.cfg", "export_presets.cfg", "export_credentials.cfg", "project.json", "work.json"} or path.name.startswith(".env"):
            errors.append(f"{label}: private configuration or workspace history")
        if path.suffix == ".cfg" and label != "game/addons/runtime_glb_export/plugin.cfg":
            errors.append(f"{label}: unapproved config file")
        if path.suffix not in EXTENSIONS and path.name not in SPECIAL:
            errors.append(f"{label}: non-allowlisted file type")
        if "assets" in relative.parts and (relative.parts[:3] != ("game", "assets", "shared") or path.suffix not in {".gdshader", ".uid", ".tres"}):
            errors.append(f"{label}: excluded asset")
        raw = path.read_bytes()
        if len(raw) > 2_000_000 or b"\0" in raw:
            errors.append(f"{label}: binary or oversized content")
            continue
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            errors.append(f"{label}: non-UTF-8 content")
            continue
        for name, pattern in [("personal path", PERSONAL_PATH), ("private key", PRIVATE_KEY), ("token", TOKEN)]:
            if pattern.search(content):
                errors.append(f"{label}: possible {name}; review locally")
        for match in ASSIGNMENT.finditer(content):
            if match.group(1) not in {"local-test-key"}:
                errors.append(f"{label}: nonempty credential assignment; review locally")
        if re.search(r"data:image/[^;\s]+;base64,[A-Za-z0-9+/=]{80,}", content) or content.startswith("version https://git-lfs.github.com/spec/"):
            errors.append(f"{label}: embedded media or LFS pointer")
        if path.suffix == ".json":
            try:
                json.loads(content)
            except ValueError:
                errors.append(f"{label}: invalid JSON")
    for error in errors:
        print("FAIL", error)
    print(f"Audited {len(files)} files; findings={len(errors)}")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())

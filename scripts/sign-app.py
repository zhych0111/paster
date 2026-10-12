#!/usr/bin/env python3
"""Prefer a configured developer identity or the project-local development certificate."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
directory = root / ".local" / "signing"
app = sys.argv[1]
identity = os.environ.get("PASTER_SIGN_IDENTITY")
previous_search_list = None
arguments = ["/usr/bin/codesign", "--force", "--timestamp=none"]
if identity:
    arguments += ["--sign", identity]
elif (directory / "identity.json").exists():
    identity = json.loads((directory / "identity.json").read_text())["certificate_sha1"]
    keychain = directory / "paster-development.keychain-db"
    password = (directory / "keychain-password").read_text()
    unlocked = subprocess.run(["security", "unlock-keychain", "-p", password, str(keychain)],
                              capture_output=True)
    if unlocked.returncode:
        print("Unable to unlock Paster project-local signing keychain", file=sys.stderr)
        sys.exit(1)
    previous_search_list = shlex.split(subprocess.check_output(["security", "list-keychains", "-d", "user"], text=True))
    # codesign's identity lookup also consults the user search list on current macOS.
    subprocess.run(["security", "list-keychains", "-d", "user", "-s",
                    *previous_search_list, str(keychain)], check=True)
    requirement = f'=designated => identifier "com.temptrip.paster" and certificate leaf = H"{identity}"'
    arguments += ["--sign", identity, "--keychain", str(keychain), "--requirements", requirement]
else:
    print("Warning: ad-hoc signing changes privacy identity after rebuilds. "
          "Run python3 scripts/setup-local-signing.py for stable local development signing.", file=sys.stderr)
    arguments += ["--sign", "-"]
arguments.append(app)
try:
    result = subprocess.run(arguments).returncode
finally:
    if previous_search_list is not None:
        subprocess.run(["security", "list-keychains", "-d", "user", "-s", *previous_search_list], check=True)
sys.exit(result)

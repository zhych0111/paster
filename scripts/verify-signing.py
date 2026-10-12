#!/usr/bin/env python3
"""Verify that a changed build still satisfies the previous build's code identity."""
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
original = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / "dist/Paster.app"


def signing_info(app):
    result = subprocess.run(["codesign", "-d", "-r-", "--verbose=3", str(app)],
                            capture_output=True, text=True, check=True)
    details = result.stdout + result.stderr
    requirement = re.search(r"designated => (.*)", details).group(1)
    code_hash = re.search(r"CDHash=(.*)", details).group(1)
    return requirement, code_hash


requirement, old_hash = signing_info(original)
if requirement.startswith("cdhash "):
    print("Signing check failed: ad-hoc identity changes with the build", file=sys.stderr)
    sys.exit(1)
with tempfile.TemporaryDirectory(prefix="PasterIdentityCheck-") as temporary:
    changed = Path(temporary) / "Paster.app"
    shutil.copytree(original, changed)
    plist = changed / "Contents/Info.plist"
    contents = plistlib.loads(plist.read_bytes())
    contents["CFBundleVersion"] = "identity-check"
    plist.write_bytes(plistlib.dumps(contents))
    subprocess.run([sys.executable, str(root / "scripts/sign-app.py"), str(changed)], check=True)
    subprocess.run(["codesign", "--verify", "-R", "=" + requirement, str(changed)], check=True)
    new_requirement, new_hash = signing_info(changed)
    if requirement != new_requirement or old_hash == new_hash:
        raise RuntimeError("Changed build did not preserve its signing requirement")
print("Signing check passed: changed build satisfies the previous identity")

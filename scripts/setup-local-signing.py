#!/usr/bin/env python3
"""Create a project-local identity; CodeSigning trust requires an explicit flag."""
import hashlib
import json
import os
from pathlib import Path
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
directory = root / ".local" / "signing"
metadata = directory / "identity.json"
os.umask(0o077)


def run(arguments):
    result = subprocess.run(arguments, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{Path(arguments[0]).name}: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def main():
    if metadata.exists():
        print("Paster project-local signing identity already exists")
        return
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    workspace = Path(tempfile.mkdtemp(prefix="setup-", dir=directory))
    previous_search_list = shlex.split(run(["security", "list-keychains", "-d", "user"]).decode())
    keychain = directory / "paster-development.keychain-db"
    password = secrets.token_urlsafe(36)
    try:
        config = workspace / "certificate.cnf"
        config.write_text("""[req]
distinguished_name = subject
x509_extensions = signing
prompt = no
[subject]
CN = Paster Local Development
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
""")
        key = workspace / "private-key.pem"
        cert = workspace / "certificate.pem"
        run(["/usr/bin/openssl", "req", "-new", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-days", "3650", "-config", str(config), "-keyout", str(key), "-out", str(cert)])
        der = run(["/usr/bin/openssl", "x509", "-in", str(cert), "-outform", "DER"])
        fingerprint = hashlib.sha1(der).hexdigest().upper()
        (directory / "certificate.cer").write_bytes(der)
        archive_password = secrets.token_urlsafe(36)
        password_file = workspace / "archive-password"
        password_file.write_text(archive_password)
        archive = workspace / "identity.p12"
        run(["/usr/bin/openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(cert),
             "-out", str(archive), "-passout", f"file:{password_file}"])
        run(["security", "create-keychain", "-p", password, str(keychain)])
        run(["security", "unlock-keychain", "-p", password, str(keychain)])
        run(["security", "import", str(archive), "-k", str(keychain), "-P", archive_password,
             "-T", "/usr/bin/codesign"])
        run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s",
             "-k", password, str(keychain)])
        (directory / "keychain-password").write_text(password)
        metadata.write_text(json.dumps({"certificate_sha1": fingerprint}, indent=2) + "\n")
        print("Created Paster project-local signing identity")
    finally:
        # create-keychain can add the keychain to the search list; preserve the user's list.
        run(["security", "list-keychains", "-d", "user", "-s", *previous_search_list])
        shutil.rmtree(workspace)


if __name__ == "__main__":
    try:
        main()
        if "--trust-code-signing" in sys.argv:
            run(["security", "add-trusted-cert", "-r", "trustRoot", "-p", "codeSign", "-k",
                 str(directory / "paster-development.keychain-db"), str(directory / "certificate.cer")])
            print("Enabled user CodeSigning trust for Paster's local certificate (not TLS trust)")
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)

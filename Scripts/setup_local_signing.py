#!/usr/bin/env python3
"""Explicit, one-time setup for a local code-signing identity. No trust-store edits."""

import argparse
import datetime
from pathlib import Path
import re
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[1]
LABEL = "AirCiller Local Development"


def run(*arguments, data=None):
    return subprocess.run(arguments, input=data, capture_output=True, check=True, timeout=60)


def configure():
    # Use the project's pinned cryptography package; never install a dependency here.
    sys.path.insert(0, str(PROJECT / "VendorPython"))
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

    keychain = Path.home() / "Library/Keychains/login.keychain-db"
    if not keychain.is_file():
        raise RuntimeError("Login Keychain was not found. No identity was created.")
    configuration = PROJECT / ".local-signing-identity"
    if configuration.is_symlink():
        raise RuntimeError("Refusing a symbolic link for local signing configuration.")
    existing = subprocess.run(
        ["/usr/bin/security", "find-certificate", "-a", "-c", LABEL, "-p", str(keychain)],
        capture_output=True, timeout=15,
    )
    certificates = []
    if existing.returncode == 0 and existing.stdout.strip():
        certificates = x509.load_pem_x509_certificates(existing.stdout)
    elif existing.returncode not in (0, 44):  # errSecItemNotFound, not an inaccessible Keychain
        raise RuntimeError("Cannot inspect signing certificates. No identity was created.")
    if len(certificates) > 1:
        raise RuntimeError("Multiple local signing certificates found; select one explicitly.")
    if not certificates:
        if configuration.exists():
            raise RuntimeError("The configured certificate is missing. Restore it; do not silently rotate it.")
        key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, LABEL)])
        now = datetime.datetime.now(datetime.timezone.utc)
        certificate = (
            x509.CertificateBuilder()
            .subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(minutes=5))
            .not_valid_after(now + datetime.timedelta(days=3650))
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.KeyUsage(
                digital_signature=True, content_commitment=False, key_encipherment=False,
                data_encipherment=False, key_agreement=False, key_cert_sign=False,
                crl_sign=False, encipher_only=False, decipher_only=False,
            ), critical=True)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CODE_SIGNING]), critical=True)
            .sign(key, hashes.SHA256())
        )
        # Private material exists only in process memory and this pipe, never in
        # a repository/temp file, argument, environment variable or tool output.
        bundle = key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption(),
        ) + certificate.public_bytes(serialization.Encoding.PEM)
        run(
            "/usr/bin/security", "import", "/dev/stdin", "-k", str(keychain),
            "-f", "pemseq", "-t", "agg", "-T", "/usr/bin/codesign", data=bundle,
        )
        del bundle, key
        print("Created local signing identity in login Keychain; codesign is the allowed signing tool.")
    else:
        certificate = certificates[0]
    fingerprint = certificate.fingerprint(hashes.SHA1()).hex().upper()
    identities = run("/usr/bin/security", "find-identity", "-p", "codesigning", str(keychain)).stdout.decode()
    if not re.search(rf"\b{fingerprint}\b", identities, flags=re.IGNORECASE):
        raise RuntimeError("Certificate has no usable private key. Local signing was not configured.")
    if configuration.exists():
        if configuration.read_text().strip().upper() != fingerprint:
            raise RuntimeError("Existing configuration names another identity; it was preserved.")
    else:
        with configuration.open("x") as output:
            output.write(fingerprint + "\n")
        configuration.chmod(0o600)
    print("Local builds now use the existing stable identity. No system trust settings were changed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--create-or-reuse", action="store_true", required=True)
    parser.parse_args()
    try:
        configure()
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        # subprocess exceptions must never print the private-key input.
        print(str(error) if isinstance(error, RuntimeError) else "Local signing setup failed; no fallback was configured.", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(f"System tool exited with status {error.returncode}: {error.stderr.decode(errors='replace')[:400]}", file=sys.stderr)
        sys.exit(1)

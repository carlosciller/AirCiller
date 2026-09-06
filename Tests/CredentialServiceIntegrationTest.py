"""Opt-in macOS signing/Keychain test. Uses only a synthetic, separately scoped item."""

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

PROJECT = Path(__file__).resolve().parents[1]


def run(*arguments, expected=0, **kwargs):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=90, **kwargs)
    if result.returncode != expected:
        raise RuntimeError(f"{Path(arguments[0]).name} returned {result.returncode}: {result.stdout} {result.stderr}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-keychain-test", action="store_true", required=True)
    parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix="credential-integration-", dir=PROJECT / ".build"))
    identity = run("/bin/zsh", str(PROJECT / "Scripts/signing_identity.sh")).stdout.strip()
    if identity == "-":
        raise RuntimeError("A local signing identity is required.")
    service = PROJECT / ".build/credential-service-fixture/AirCillerCredentialService.xpc"
    if not service.is_dir():
        raise RuntimeError("Build the synthetic service with build_credential_service.sh --test-fixture first.")
    account = "probe-" + str(uuid.uuid4())
    good_identifier = "local.carlosciller.AirCiller"

    def bundle(name, identifier=good_identifier, signer=identity, raw=False, hardened=True, debug=False, allow_environment=False):
        app = root / f"{name}.app"
        contents = app / "Contents"
        executable = contents / "MacOS/Probe"
        executable.parent.mkdir(parents=True)
        shutil.copytree(service, contents / "XPCServices/AirCillerCredentialService.xpc")
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier, "CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL",
            "CFBundleName": name, "ACCredentialServiceClientVersion": "1", "ProbeBuild": name,
        }))
        if raw:
            run("xcrun", "clang", "-fblocks", "-Wall", "-Wextra", "-Werror", str(PROJECT / "Tests/CredentialServiceRawProbe.c"),
                "-framework", "Foundation", "-o", str(executable))
        else:
            shutil.copy2(PROJECT / ".build/credential-probe", executable)
        arguments = ["/usr/bin/codesign", "--force", "--sign", signer]
        if hardened:
            arguments += ["--options", "runtime"]
        if debug or allow_environment:
            entitlement = root / f"{name}.plist"
            entitlement.write_bytes(plistlib.dumps({
                "com.apple.security.get-task-allow": debug,
                "com.apple.security.cs.allow-dyld-environment-variables": allow_environment,
            }))
            arguments += ["--entitlements", str(entitlement)]
        run(*arguments, str(app))
        return app, executable

    first, first_exe = bundle("First")
    second, second_exe = bundle("Rebuilt")
    cleanup_required = True
    try:
        run(str(first_exe), "read", account)
        cleanup_required = True
        print("First signed client created/read synthetic item without interaction.", flush=True)
        run(str(first_exe), "read", account)
        run(str(second_exe), "read", account)
        print("Different client build reused the same service and credential without interaction.", flush=True)
        for name, options in (
            ("WrongIdentifier", {"identifier": "local.carlosciller.Unrelated", "raw": True}),
            ("WrongSigner", {"signer": "-", "raw": True}),
            ("NoHardening", {"hardened": False, "raw": True}),
            ("DebuggerAllowed", {"debug": True, "raw": True}),
            ("LoaderEnvironmentAllowed", {"allow_environment": True, "raw": True}),
        ):
            _, executable = bundle(name, **options)
            run(str(executable), account, expected=1)
            print(f"Denied at service boundary: {name}.", flush=True)
        tampered, executable = bundle("TamperedService")
        service_info = tampered / "Contents/XPCServices/AirCillerCredentialService.xpc/Contents/Info.plist"
        info = plistlib.loads(service_info.read_bytes())
        info["UntrustedChange"] = True
        service_info.write_bytes(plistlib.dumps(info))
        run(str(executable), "read", account, expected=1)
        print("Client refused the tampered service before reading credentials.", flush=True)
    finally:
        if cleanup_required:
            run(str(first_exe), "cleanup", account)
            run("/usr/bin/security", "find-generic-password", "-s", "local.carlosciller.AirCiller.CredentialService.Probe",
                "-a", account, expected=44)
            print("Synthetic Keychain item removed; no private credentials were accessed.", flush=True)
    print(f"Credential service integration checks: OK. Artifacts: {root}")


if __name__ == "__main__":
    main()

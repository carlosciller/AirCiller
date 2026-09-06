# Local credential service

Local certificate-signed builds can use a small read-only XPC service for AirPlay credentials. The service is copied unchanged between app builds, so the file-based Keychain sees the same executable. Rebuilding or replacing the service itself may require a new approval.

## Scope

- Reads only generic-password items in AirCiller's existing AirPlay service, for a bounded device identifier.
- Does not write, delete, migrate or reset real credentials. Explicit pairing/reset actions keep the existing store implementation.
- Does not access OpenSubtitles credentials or unrelated Keychain items.
- Sends the credential through local XPC messages. No credential files, command-line arguments, environment variables, network requests or diagnostic output are used.
- Starts on demand in the caller's security session, exits after three idle seconds, and has a 75-second maximum lifetime. No launch agent or permanent service is installed.

## Caller authentication

The service pins the local certificate and permits only the ordinary AirCiller and Playback Checks signing identifiers with the versioned client marker. XPC checks the sender's signature on messages. A second check uses `SecCodeCreateWithXPCMessage` and its kernel audit token to require Hardened Runtime and reject debugger or DYLD-environment exceptions. It does not trust a supplied PID, application name or filesystem path as caller identity.

The client verifies the complete embedded service signature and pins its peer identity before sending the request. A missing, modified or wrongly signed service fails closed. There is no fallback to direct Keychain reads in a service-enabled build.

The app's local signature permits loading the separately signed Sparkle framework through the library-validation exception. Debugger and DYLD-environment exceptions remain disabled. The service has no exceptions. These protections do not constitute notarization, and the local signing key remains sensitive developer authority.

Apple documents [XPC peer requirements](https://developer.apple.com/documentation/xpc/xpc_connection_set_peer_code_signing_requirement(_:_:)) and [sharing the caller's Keychain session](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html).

## Setup and rebuilding

After approving and configuring the local signing identity:

```sh
zsh Scripts/build_credential_service.sh
./build.sh --playback-checks
```

The signed service is kept in ignored `.local-credential-service`, outside `.build` so ordinary build cleanup does not remove it. App builds verify the service and its source digest, then copy it without re-signing it. Changed source or missing cache blocks a local signed build; preparing a replacement is an explicit maintenance step. Keep the previous service until a replacement has been validated. Public ad hoc release builds do not use this local component.

Authorize the service through the check app's explicit `--authorize-keychain` command. Later `--check-keychain` calls and automatic batches cannot display password dialogs. A locked Keychain or revoked permission still blocks access. Never remove partition protections or grant access to all applications.

## Verification

The ordinary strict check suite compiles the client, service and protocol probes without touching Keychain items. The opt-in integration test uses a separately compiled service that can create/delete only synthetic items in its isolated test service:

```sh
zsh Scripts/build_credential_service.sh --test-fixture
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  Sources/CredentialServiceClient.swift Tests/CredentialServiceProbe.swift -o .build/credential-probe
python3 Tests/CredentialServiceIntegrationTest.py --local-keychain-test
```

Production compilation excludes the synthetic-write implementation. The test reads from two differently signed client builds using the unchanged component, then sends raw XPC requests from wrong-identifier, wrong-signer, unhardened, debugging-enabled and loader-environment-enabled clients. It also verifies rejection of a modified service. Synthetic data is removed afterward. These checks exercise the system boundary; they do not substitute app-name comparisons for peer authentication.

Synthetic integration passed on 6 September 2026, including access from a changed client build and rejection of the negative cases. Real-credential reads also passed after one explicit approval, from the actual check app and a repackaged copy with a different code-directory hash and the same service bytes. Neither repeated read required another dialog. That first test changed signed app metadata, not Swift source, and started no playback or capture.

The subsequent [playback-check validation](PLAYBACK_CHECKS.md#development-validation-6-september-2026) rebuilt the actual Swift check app after a test correction and completed three playback-control cases using the unchanged service, without another password dialog. Capture experiments and their limitations are recorded separately. These results apply to the approved local service and unlocked Keychain, not every future machine, identity or service replacement.

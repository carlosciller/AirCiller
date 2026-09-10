# Vision OCR failure in the macOS preview runner

## Observed on 10 September 2026

The 0.12.6 release-tag CI failed in `SubtitleOCRCancellationSmokeTest` before the first OCR result. Vision returned `e5rtError("e5rt_e5_compiler_compile call failed", 11)`. This is a recognition-engine startup failure, not evidence that the cancellation deadline was exceeded.

- [Main-branch run 34387048423](https://github.com/carlosciller/AirCiller/actions/runs/34387048423) passed for commit `3acdc4670efec176c63bf5caa0639fe989a50af8` on image `20260901.0153.1`.
- [Release-tag run 34387522192](https://github.com/carlosciller/AirCiller/actions/runs/34387522192) failed for the same commit on image `20260907.0173.1`. One deliberate rerun of the unchanged commit reproduced the same error. It was not retried until green.
- The [runner image release notes](https://github.com/actions/runner-images/releases/tag/xcode-27-arm64%2F20260907.0173) record a host OS change from macOS 26.5.2 to macOS 27.0 beta (26A5406e), despite both jobs requesting `xcode-27`.
- Three consecutive executions of the existing OCR cancellation test passed locally on macOS 27.0 (26A5425a). Each recognized real synthetic text, cancelled without delivering a later result, and rejected an already-cancelled request.

This isolates a reproducible failure in the hosted preview environment. It does not establish which internal Vision compiler component failed, whether virtualization is responsible, or that every macOS 27 build is affected. The local result is not an Apple TV playback test.

## CI environment correction

Required CI now requests the released `macos-26` environment. Manual workflow dispatch retains `xcode-27` for explicit preview investigations, using the same tests and failing normally on errors. No OCR requests, production playback code, dependencies, recognition assertions or cancellation deadlines were changed. The failed preview run remains evidence of an unresolved preview-environment issue, not a successful check.

After publication, the release procedure requires inspection of the tag-triggered run as well as the earlier branch and pull-request runs. A release is not closed on the strength of an earlier green result.

## Validation

The full local `./Scripts/check.sh` passed on 10 September, including the real Vision cancellation check, strict Swift 6 compilation, smoke tests, public-content audit and bundled-app checks. The workflow YAML parsed successfully and `git diff --check` passed. The corrected stable-host workflow still needs validation on GitHub. Do not describe its outcome as passed based on local results.

The installed 0.12.6 (59) app passed strict code-signature verification and its executable matches the published archive. Neither it nor the signed release assets were modified by this investigation.

# Evidence and release readiness

Use this reference for playback diagnosis, validation planning or release assessment. [TESTING.md](../../../../TESTING.md) defines acceptance; [Docs/PLAYBACK_CHECKS.md](../../../../Docs/PLAYBACK_CHECKS.md) owns runner commands, profiles, source approval and report semantics. Read only the needed procedure and relevant historical record.

## Plan validation from the change

- Documentation/agent instructions only: diff review, local links/paths and consistency, `git diff --check`. No app build, receiver session, version bump or installation.
- Code/dependencies/build: focused regressions plus `./Scripts/check.sh`, as required by [CONTRIBUTING.md](../../../../CONTRIBUTING.md). Local UI-only work does not automatically require a playback matrix; explain the unaffected boundary.
- Playback preparation, tracks or controls: deterministic coverage, applicable local-media checks and the affected physical Apple TV cases in TESTING. Shared session/server changes require examining both routes; engine upgrades require both. Keep route results separate even in a single batch.
- Release/install candidate affecting playback: complete the applicable TESTING matrix, including stop, replay and app close. The basic three-clip runner is only a subset: select track changes, long pauses, natural completion, rapid commands from the required remotes, or cancellation cases according to the affected behavior. Receiver-free bitmap cancellation is local evidence.

Before a device run, use the isolated check-app procedure with the approved receiver and a confirmed free TV. Reuse existing authorization when it covers the run; do not assert `--tv-is-idle` without that evidence. Build the isolated candidate when application code changes. Preserve the installed app, daily preferences and original media. Missing credentials/source readiness is a concrete blocker, not permission to pair, reset settings or choose another source. Retain failed reports; only retry when a bounded diagnostic or changed condition justifies it.

## Label what the evidence proves

| Evidence | Supports | Does not establish |
| --- | --- | --- |
| Deterministic/local | Strict build, simulated bridge behavior, container/metadata checks, OCR, local AVPlayer and synthetic benchmarks for their specific fixtures | tvOS acceptance, television picture/sound, physical controls or end-to-end speed |
| Receiver | Fresh receiver state/progress, correlated replies, media requests, natural end and cleanup for the observed case | An ACK alone is not progress; a Mac timer or echoed target is not a receiver position; receiver state is not audiovisual acceptance |
| Sampled digital output from the approved Apple TV source | Observed motion, measured non-silent audio and expected cues inside the recorded window, separately from receiver controls | Physical speakers, Atmos layout, television HDR rendering, frame-accurate sync, physical remote use or whole-movie reliability |
| Physical observation | Picture, sound, track presentation and hardware/remote behavior actually confirmed on the tested setup | Other formats, devices, unobserved intervals or later candidates |

For physical HDR/Atmos claims, obtain the appropriate television/audio-chain observation; metadata preservation, AVFoundation and sampled screen frames cannot certify them. Attribute user-confirmed observations as such. Report each required but absent observation as pending/unverified; contradictory evidence remains a failure. A later pass or offline reassessment must not overwrite an earlier failure or be described as a fresh live run.

Record the candidate commit/hash, route, relevant media/track properties, scenario, tools/evaluator identity, observed result and limits. Keep raw plans, clips, frames and diagnostics private under the runner's ignored output location. Publish only a sanitized account with enough identity and coverage to review claims; never include private movie names, subtitle text, device/network identifiers or credentials.

## Release readiness

Follow [DISTRIBUTION.md](../../../../DISTRIBUTION.md) rather than duplicating its signing and upload commands. Assess separately:

1. **Code acceptance:** required local checks pass for the candidate; applicable playback evidence covers each affected path and control case. Account for changes since the tested candidate before reusing evidence. Missing physical coverage prevents claiming the playback gate complete.
2. **Release content:** derive versions from current files, reconcile the release diff with [CHANGELOG.md](../../../../CHANGELOG.md), versioned notes and affected compatibility/roadmap records. Use [the release-note template](../../../../Distribution/ReleaseNotes/TEMPLATE.md) for usage, supported scope and evidence-linked limitations. Do not bump a version merely for agent documentation.
3. **Distribution:** validate the intended signing configuration, pinned runtime, bundle size, preserved third-party signatures, archive and signed Sparkle feed under DISTRIBUTION. Local certificate/ad hoc builds are not notarized releases. Do not hand-edit signed feeds or replace historical assets for a prose correction.
4. **Publication/installation:** act only within conversation authorization. Check CI for the exact relevant commit; after an authorized tag, verify that tag-triggered run separately. Pending or failed required CI is not completion. Verify published URLs, notes, signatures and the real update/install result when those actions are in scope; preserve a rollback copy before replacing the daily app.

Report code-ready, playback-validated, packaged, published and installed only to the extent each is observed. A documentation PR can be ready for review while no binary release has been attempted. Preparing a branch or PR does not authorize merging main, publishing binaries or replacing the installed app.

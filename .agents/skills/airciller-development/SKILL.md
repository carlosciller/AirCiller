---
name: airciller-development
description: Implement, debug, review and validate changes in the AirCiller repository, including playback-path selection and release readiness. Use for AirCiller development; not ordinary media playback or unrelated projects.
---

# AirCiller development

Follow [AGENTS.md](../../../AGENTS.md). Run commands from the repository root; resolve these links relative to this file. Treat current code as evidence of implemented behavior, contribution/architecture documents as requirements, and dated validation records as evidence only for their recorded candidates. If they conflict, identify the discrepancy before changing behavior or claiming acceptance.

## Select the task

Read [CONTRIBUTING.md](../../../CONTRIBUTING.md#minimum-validation) to choose the validation gate, then load only the relevant branch below. Do not load all playback or release documents for an unrelated edit.

| Task | Entry point |
| --- | --- |
| Documentation or agent instructions only | Review the diff and changed references; run `git diff --check` against the delivery base, including new files. No app build or device session. |
| UI, library or other non-playback code | Inspect the affected view/service and its tests; use [library recovery](../../../Docs/LIBRARY_RECOVERY.md) or [credential service](../../../Docs/CREDENTIAL_SERVICE.md) only if involved. |
| Playback, preparation, subtitles or shared controls | Read [playback development and evidence](references/playback.md), then the specific architecture, compatibility and test sections it identifies. |
| Performance | Read [reproducible local fixtures](../../../TESTING.md#12-reproducible-performance-fixtures) or the relevant [ROADMAP.md](../../../ROADMAP.md) phase. Use the playback reference for end-to-end claims. Retain the dedicated startup-phase checkpoint in AGENTS. |
| Packaging, release-readiness review, installation or publication | Read [release readiness](references/release-readiness.md). Assessment alone does not trigger publication steps. |

## Implement, debug or review

1. Identify the requested outcome, current branch/commit, existing changes and affected boundary. For a bug, reproduce the smallest failing case and retain its result; for review-only work, inspect and report without applying fixes. State material reproduction gaps instead of assuming a cause.
2. Trace the affected entry point to the responsible code. Inspect the existing test and command in [Scripts/check.sh](../../../Scripts/check.sh). For suspected environment/tooling failures, compare the unchanged baseline under the same conditions and preserve both results; do not weaken validation to manufacture a pass.
3. Make the smallest fix that preserves the documented invariants. Add regression coverage for meaningful changed behavior using synthetic/non-private fixtures or simulated events. A test should distinguish the failure from the fix; avoid assertions that merely restate implementation. Add new required standalone tests to the check script when appropriate. Documentation-only edits do not require new tests.
4. Use focused checks while iterating, then the contribution-policy gate: `./Scripts/check.sh` for code, dependency or build changes. It includes the strict build; an identical second build is unnecessary. Use repository bootstrap scripts for missing prerequisites, and the documented lock-regeneration procedure for Python dependency changes. Do not hand-edit `requirements.lock` or substitute a host playback engine.
5. Review the complete delivery diff and applicable evidence. Report what changed, what ran, what was observed and what remains unverified. Historical passes need an explicit comparison with the current candidate. Stop when required checks pass; expand only for new changes, failures or unresolved concerns.

Read the applicable [TESTING.md](../../../TESTING.md) section before choosing tests. Pure UI work needs local validation of its actual interaction; a control that starts, changes or stops playback also needs the affected playback checks. Preserve original data and the user's existing authorization boundaries throughout.

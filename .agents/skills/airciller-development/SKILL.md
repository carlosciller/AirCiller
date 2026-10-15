---
name: airciller-development
description: Implement, debug, review and validate the AirCiller macOS app, its playback paths and releases. Use for work in this repository, not ordinary media playback or unrelated projects.
---

# AirCiller development

Follow [AGENTS.md](../../../AGENTS.md). Run commands from the repository root;
resolve these links relative to this file. Code establishes implemented behavior,
maintained guides define requirements, and dated records support only their
identified candidates. Resolve a material conflict before changing behavior or
claiming acceptance.

## Select the workflow

Start with [minimum validation](../../../CONTRIBUTING.md#minimum-validation),
then load only the relevant entry points:

| Task | Read and inspect |
| --- | --- |
| Documentation or agent instructions | Changed references and their callers. Use the documentation gate; no app build or receiver session unless executable behavior changes. |
| Native UI/UX | [Native design](../../../Docs/NATIVE_DESIGN.md), the affected view/service and its tests. Inspect implemented interaction in the running app; a mockup is not runtime acceptance. |
| Library or credentials | The affected service/tests and, as relevant, [library recovery](../../../Docs/LIBRARY_RECOVERY.md), [seasons](../../../Docs/LIBRARY_SEASONS.md) or [credential service](../../../Docs/CREDENTIAL_SERVICE.md). |
| Playback, preparation, subtitles or shared controls | [Playback development and evidence](references/playback.md), which routes to architecture, format limits and affected tests. |
| Performance | [Local fixtures](../../../TESTING.md#12-reproducible-performance-fixtures) and the authorized [roadmap phase](../../../ROADMAP.md#faster-playback-startup). Use playback evidence for end-to-end claims. |
| Release assessment, packaging or installation | [Release readiness](references/release-readiness.md), then Distribution at the relevant stage. An assessment does not authorize publication. |

## Working with this repository

- Trace the real entry point and test target in [Scripts/check.sh](../../../Scripts/check.sh). Add meaningful regressions with synthetic inputs or simulated events. For environment failures, compare the unchanged baseline under the same conditions.
- `check.sh` includes the strict Swift 6 build. Use focused checks while iterating, then run the applicable final gate once. Bootstrap and lock-regeneration commands belong to CONTRIBUTING; never substitute a host playback engine.
- Preserve evidence identity across changes: production source, resources/helpers, locked engines, relevant build configuration and media. A release-metadata edit is not a fresh device test; a changed playback input can invalidate earlier evidence.
- Keep failures and offline reassessments distinguishable from fresh runs. Required observation gaps block the corresponding claim, not independent work that can proceed safely.

# Native UI fixture builders: 15 November 2026

## Scope and validation selection

Baseline: `0f14557` on `codex/release-0.19.2-record`.
Only isolated UI fixture construction changes. Keep one constructor for all six
variants and retain the three historical commands as forwarding entry points.
Preserve fixture source selection, bundle names and identifiers, UUID isolation,
Swift 6 strict flags, frameworks, localizations and ad hoc signatures.

Required checks: `zsh Tests/NativeUIBuildersTest.sh` builds all six variants,
exercises the historical entry points, rejects an unknown mode and verifies
bundle metadata, localizations and signatures. Run `Scripts/check.sh` once for
the final executable changes, plus `git diff --check`.

No Apple TV session is required: production sources, playback helpers, resources,
engines, dependencies and the production build script are unchanged. This work
does not claim fresh receiver or physical playback evidence. No fixture is
launched; the installed app and its session are not replaced or stopped.

## Results

- All six variants compiled with strict Swift 6 and warnings-as-errors. Bundle
  metadata, executable presence, both localizations and signatures passed.
  The first five passed in the regression script. The recovery command had
  always lacked an executable bit; the new test initially invoked it directly.
  The test now invokes historical commands through `zsh`. Recovery alone was
  then built and checked successfully; the five unchanged builds were retained.
- Local gate initially selected host Python 3.13.16 instead of pinned
  3.13.15, then on cache access restrictions. The final run explicitly selects
  the existing bundled Python and Node 24.19.0 with cache access. No dependencies
  or test criteria were changed. All code regressions and capture-tool compilation
  passed. The publication prose check then rejected this report's heading dash
  and wording. After correcting only prose, execution resumed at that check
  (`Scripts/check.sh`, line 581) through the strict app build, signature and
  bundled-Python packaging checks. Final result: `AirCiller local checks: OK`.
  Successful code tests were not repeated. The opt-in regression's invocation
  correction does not change application inputs or the ordinary suite.
- Shell syntax and `git diff --check` passed. Final report changes were checked
  separately with the public-content check; no application rebuild is needed.
- Environment: macOS 27.2.1 (26B131), Apple Swift 6.4.2.
- Builder implementation: 66 fewer lines, retaining historical entry points.
  The separate opt-in regression covers all six variants without launching them.
- No publication or installation requested. Next step after local acceptance:
  review/commit this tooling-only change; runtime simplification is separate work.

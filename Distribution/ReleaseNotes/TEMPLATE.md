# AirCiller X.Y.Z

A short opening explaining what this release makes possible or which recurring problem it resolves.

- Describe the most useful change first, including where to use it if it is not obvious.
- For a fix, name the symptom and the conditions affected. Do not extend the claim beyond the verified case.
- For a new format, state the accepted input, relevant track/layout limits and whether preparation copies media or recognizes subtitle images as text.
- Mention changed requirements, actions the user needs to take and important remaining limitations.
- Link the version-specific scope and validation record when compatibility needs more detail.

Use short sentences. Group under New, Improved or Fixed only when the release needs sections. Omit internal refactors, test counts, repeated privacy promises and unverified performance claims.

Keep the same factual changes in CHANGELOG.md and GitHub. Do not change published signed archives or appcasts when editing release prose.

## Editorial check before publication

1. Review the commits and diff since the previous release. Account for every meaningful user-facing change; record internal work and evidence in the relevant engineering documents instead of inflating the notes.
2. Check each claim against implemented behavior and recorded validation. Separate local preparation, sampled Apple TV output and untested behavior in the linked record. Include remaining limitations that affect the advertised feature.
3. Read the notes as someone unfamiliar with development: what changed, how do I use it, and what will not work? Replace vague phrases such as "stability improvements" with the actual symptom. Avoid marketing superlatives, em dashes and formulaic contrast slogans. Do not pad a small release to meet a length target.
4. Keep CHANGELOG.md and the versioned notes factually aligned. Check links against the intended release tag. Update compatibility documentation and roadmap status when behavior changes.
5. Report publication state precisely. Editing these files does not update GitHub Release text or an already-signed Sparkle feed. Synchronize GitHub prose only within an authorized publication task; never silently replace historical signed assets.

This checklist is authoring guidance; omit it from the finished release notes.

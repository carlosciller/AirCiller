# Library recovery

## Unreadable saved lists (unreleased)

Unreadable Playlist, Recents and season data is retained. Ordinary saves cannot
replace it with an empty fallback. A library notice opens recovery options;
there is no automatic restore or startup alert. Restoring requires confirmation
of the affected list and copy date. Starting an empty list also requires explicit
confirmation and preservation of its failed data. Other lists and media files
are not replaced. Editing waits until unreadable data has been resolved.

Recovery records live in Application Support under the app's bundle identifier,
in `Library Recovery`. Each collection has a valid checkpoint and up to two
incident records, capped at 4 MiB each (36 MiB retained in total, plus a temporary
atomic write). A checkpoint is refreshed at startup or an explicit retry; it is
not a continuous backup. Unresolved incidents cannot overwrite each other.
After resolution, the next incident retains its predecessor; only the oldest
resolved incident ages out. Oversized or inaccessible data is never truncated.

The interface distinguishes unreadable JSON, an unrecognized format, unsupported
recovery versions, permission failures and archive read/write errors. Recovery
uses the current UserDefaults library representation, which has no transactional
disk-write acknowledgement. See [candidate checks and limits](LIBRARY_RELIABILITY_REVIEW.md).

## Missing files (0.12.6)

This change removed automatic deletion of missing files from Playlist and Recents, both when loading stored lists and when attempting playback. Missing storage is not treated as a request to delete an entry. The existing explicit Remove and Clear actions remain available.

## Behavior

- Failed file access marks the attempted entry unavailable and offers Locate File. The app does not periodically scan drives; reconnecting and retrying clears the mark once the file is accessible.
- Locate File is also available from each list's context menu. The user selects the same movie at its new location. Both lists update together, keeping order, saved position and duration. Original files are neither moved nor renamed.
- The app does not guess that a similarly named file is the same movie. It refuses to merge with an existing destination entry. Cancel leaves the library and playback unchanged.
- A movie currently preparing or streaming cannot be relocated. Relocating another entry leaves that session alone. An idle selected movie is analyzed again at the explicit replacement path without starting playback.
- A missing next Playlist file stops automatic advancement with an explanation. It is not removed or silently skipped. No authorization or video packaging changes are included.
- Entries removed by older versions cannot be reconstructed automatically. The former corrupt-JSON reset behavior is replaced by the unreleased recovery change above; unavailable storage is not treated as corrupt data.

## Validation

The focused history test passes for byte-identical persistence after loading unavailable entries, reconnecting storage, moving a file and explicitly relinking it, preserved order/progress/duration, duplicate and stale-entry rejection, independent Playlist/Recents membership, the existing 30-item Recents limit and malformed JSON. Availability is read fresh on access, accepts readable regular files through symbolic links, and rejects missing files and directories.

## Interface check, 9 September 2026

An isolated window compiled from the real library views and coordinator used its own application identifier and two fictitious entries. It did not launch receiver discovery, read AirPlay credentials or use the installed app's library.

- Attempting the unavailable first item displayed Cancel and Locate File. Cancelling retained both entries and marked the first unavailable.
- Locate File appeared in both Playlist and Recents context menus. Selecting an explicit replacement updated both lists, retained the first Playlist position and focus, cleared the unavailable mark and displayed Continue at 07:00 in Recents.
- Logged coordinator state retained the simulated playing/streaming flags and the 420-second saved position before and after relocation. This verifies local state preservation, not a live AirPlay session.

Both the first full strict suite and the final suite after the symbolic-link availability check passed with `AirCiller local checks: OK`. The latter also ran all 25 capture supervisor tests. A subsequent capture-tool correction passed the full suite with 29 supervisor tests and an integrated three-case Apple TV batch. The installed 0.12.5 executable was not replaced during these checks.

### Remaining coordinator branches

A second isolated harness compiled the unchanged production coordinator and views, with a synthetic 60-second clip and a deliberately unavailable next entry. It used its own library and did not discover a receiver or read credentials.

- After real local media analysis, invoking the coordinator's existing receiver-ended callback retained both Playlist entries, marked the unavailable next item and reported the error. The runtime was idle and the observed load count did not increase. This exercises the completion handler with an injected event, not a new physical natural-end observation.
- The same clip was selected while idle at second 12, then moved within the private test directory. The real Locate File panel selected its replacement. Analysis completed against the new path with duration and audio tracks populated. Both lists retained the entry, saved progress stayed at second 12 and the runtime remained idle. No playback started and no old-path duplicate appeared.

Both checks passed and the harness was closed. Initial harness setup attempts failed before these checks because of an incorrect deployment target and a missing embedded framework; neither was an application failure or a passing test. The applicable library branches now have local integration coverage. The separately recorded Apple TV batch covers sampled playback; no physical receiver claim is inferred from these local callback or interface checks.

The separate capture-readiness improvement is documented in [Playback checks](PLAYBACK_CHECKS.md#initial-capture-readiness).

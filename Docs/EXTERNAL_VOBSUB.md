# External VobSub subtitles

## Scope

The candidate attaches a local VobSub v7 `.idx`/`.sub` pair through the subtitle picker. Choosing either file resolves the pair. Automatic discovery uses matching movie names and reads only the index, so its companion does not create a duplicate entry.

The index supplies language, optional track title, default selection, canvas, palette and packet timestamps. Each populated stream becomes a separate selectable track. Empty stream IDs do not consume a stream index; nonsequential DVD IDs map to the demuxer's stream order. This follows the pinned FFmpeg implementation in `libavformat/mpeg.c`.

Only the selected bitmap stream is decoded and recognized with Apple Vision. The existing direct MP4 and HLS subtitle materializers consume the resulting text. Neither video packager nor the WebVTT segment writer changes. Original movies and subtitle files remain untouched.

The cache identity includes the index, bitmap companion, selected stream, language and movie duration. Both files are validated before a cache hit can be returned. Missing companions, unreadable files, invalid palettes, invalid stream IDs and out-of-file packet positions produce an error. Reads are limited to a 4 MiB index and a 256 MiB bitmap file, with bounded canvas dimensions. A `.sub` file containing MicroDVD text is not treated as VobSub.

## Local validation, 9 September 2026

- The full strict Swift 6 suite passed, including publication and bundle checks. No engine or dependency version changed.
- Deterministic tests cover selection of either half, mixed-case extensions, sparse and empty IDs, language/title/default metadata, distinct track identities, sibling discovery without duplicates, index and bitmap cache invalidation, duration changes, whitespace, malformed data, missing files and read limits.
- A private MPEG program-stream copy of existing DVD subtitle packets was paired with a generated index. The pinned decoder recovered the expected packets. A source-bitmap cue from 0.901 to 2.899 seconds matched both direct and HLS text materialization within 2 ms. DVD stop-display timing has its own clock quantization; container packet duration is not used as the bitmap's clear time.
- A separate private pair contains two populated tracks with DVD IDs 7 and 2. FFprobe confirms stream indexes 0 and 1 with the expected metadata. Full local OCR returns the distinct expected phrase for each track, and reading the resulting cache returns byte-identical text.
- The normal signed candidate measures 153,969,055 logical bytes, below the existing 165,000,000-byte limit. Its executable SHA-256 is `e8a9b3a955ec06f6c6701ca0268011b1b7bf15450a27734dbc9a590c641d3e76`.

## Physical validation

Two receiver attempts stopped because the approved Apple TV capture source produced no ready marker. Neither attempt produced a sampled video frame, so neither is a physical playback pass. The supervisor terminated its test processes and preserved incomplete reports.

A separate bounded diagnostic verified the exact approved input, created the capture session and returned from `startRunning`, but received no first frame within 25 seconds. This establishes a capture-evidence gap; it does not establish a VobSub playback defect or successful television output. No alternate input, camera, microphone, permission reset or pairing reset was used.

The prior external PGS/control results remain in [their own record](EXTERNAL_PGS.md). The remaining short HLS visibility gap immediately after seeking is not claimed fixed.

The maintainer subsequently reported that the television had been off and switched it on. The next two batches captured motion and digital audio on both routes. The HLS subtitle was visible after the seek burst; the direct HDR run had no visible expected subtitle. Those initial direct runs are failures, not passes.

A local MP4 comparison isolated a metadata problem: the pinned muxer drops the language tag for `en` and retains it for `eng`. VobSub supplies two-letter language IDs. The reader now normalizes those IDs to their equivalent three-letter code before either materializer receives the track. The regression test covers English and Spanish. The video packagers and text-segment writer remain unchanged.

The corrected check executable (`bdbc0100363417faad6352a74e0379c9d479736c9846e2aba58d8f120350c1d8`) completed four independent receiver-control cases. Captured subtitle evidence is recorded separately:

| Track and route | Video samples | Moving samples | Non-silent audio / audio samples | Expected subtitle in late seek window |
| --- | ---: | ---: | ---: | ---: |
| First track, HLS | 30 | 29 | 67 / 76 | 3 / 3 |
| First track, direct HDR | 29 | 27 | 44 / 74 | 4 / 4 |
| Second track, HLS | 29 | 28 | 65 / 74 | 4 / 4 |
| Second track, direct HDR | 30 | 28 | 42 / 74 | 2 / 3 automatic; 3 / 3 visual review |

The second direct run's automatic assessment remains `incomplete`: its OCR classifier missed one frame. Independent inspection of all three late-window images confirms the expected subtitle visibly present in each, matching the source bitmap. That visual review supplies the missing output evidence; the automatic report was not overwritten and is not described as a pass. No further receiver run was needed to observe those already-captured frames.

Each case confirmed receiver playback, pause/resume, the intended final position after a four-command Mac seek burst and cleanup. The two expected subtitle phrases were checked independently against source bitmaps, captured output and local OCR results. Index and bitmap fingerprints were unchanged after playback. These are sampled digital-output checks, not certification of physical speakers, HDR rendering, remote-originated command bursts or whole-movie reliability.

The full strict suite passed again after the language correction. Release metadata advances to 0.12.5/build 58; packaging, CI and installation are separate distribution steps. Private fixtures, captures and the maintainer's audit stay outside the publication set.

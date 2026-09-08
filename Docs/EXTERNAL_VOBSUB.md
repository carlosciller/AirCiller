# External VobSub candidate

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

## Physical validation is pending

Two receiver attempts stopped because the approved Apple TV capture source produced no ready marker. Neither attempt produced a sampled video frame, so neither is a physical playback pass. The supervisor terminated its test processes and preserved incomplete reports.

A separate bounded diagnostic verified the exact approved input, created the capture session and returned from `startRunning`, but received no first frame within 25 seconds. This establishes a capture-evidence gap; it does not establish a VobSub playback defect or successful television output. No alternate input, camera, microphone, permission reset or pairing reset was used.

Before release, complete separate HLS and direct HDR captured-output checks with the two VobSub tracks, including late recovery after rapid Mac skips. Retain the prior external PGS/control results in [their own record](EXTERNAL_PGS.md). The remaining short HLS visibility gap immediately after seeking is not claimed fixed.

This candidate has not been published or installed. Version metadata remains 0.12.4/build 57. The installed local PGS candidate and its rollback are unchanged. Private fixtures, captures and the maintainer's audit stay outside the publication set.

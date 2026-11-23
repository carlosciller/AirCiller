# PGS cold preparation

Two complete local PGS tracks were tested with empty AirCiller subtitle caches.
The first baseline run was followed by an 8 / 4 / 8 worker sequence. Runs were
sequential; the operating system's disk cache was not reset. All comparisons
used the same bundled FFmpeg, Vision settings and subtitle inputs.

| Track | Visible groups / output cues | Four workers, first / interleaved | Eight workers, two runs |
| --- | ---: | ---: | ---: |
| A | 1247 / 1246 | 58.94 / 32.03 s | 22.98 / 22.26 s |
| B | 658 / 658 | 17.94 / 17.41 s | 14.47 / 12.36 s |

The first run on A was substantially slower. Against the interleaved
baseline, median whole-track preparation saved about 9.4 s on A and 4.0 s on B.
In that baseline, OCR and writing took 21.02 s and 10.63 s respectively; with
eight workers the medians were 11.47 s and 6.22 s. Output WebVTT hashes matched
across every run for each input, including cue text, timing, layout and final
cue. Immediate cache hits were unchanged. These timings are local preparation,
not Play-to-picture or a claim about all hardware.

Eight is a fixed upper bound for PGS with modern Vision on macOS 15 or later,
at least eight active cores and 16 GB RAM. No recognition options, cache keys,
VobSub worker limit, remuxer, receiver transport or engine dependencies change.

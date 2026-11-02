# Preparation review for the local-library goal

Delivery 5, 2 November 2026. No new engine or preparation optimization is adopted.

## Reused evidence and current boundary

The [library measurements](LIBRARY_STARTUP_MEASUREMENT.md) used three complete
movies, three empty/warm pairs each, isolated app caches and the pinned engine.
Empty-cache HLS medians were 20-22 seconds; warm checkout was 0.57-2.28 seconds.
The 20.92 GB input exceeded the ordinary 16 GiB retention preference, so its warm
result is not a promise of an ordinary cache hit. “Empty” did not mean an OS-cold
disk. Source and served-file identities were checked in that campaign.

Those HLS preparation/cache production files have no diff from the measured
`5886fee` reference in this candidate. The new season/title controls operate
before playback; chapter actions delegate to the existing seek operation.
Completed-preparation information adds no probe or media read. Reusing these
records establishes where costs were measured, not a fresh end-to-end speedup.

The separate [direct-demand experiment](DIRECT_DEMAND_MEASUREMENT.md) identified
competition between the full packet scan and direct MP4 preparation. The
[28 October review](REVIEW_2026_10_28.md) then implemented and validated cancellation
and joining of the unfinished scan. Its large-movie medians were 12.843 seconds
versus 20.205 seconds with concurrent analysis; the smaller episode was variable.
The current direct entry still captures `cancelDemand()`, awaits that task and
revalidates session ownership before preparation. Completed demand profiles and
the estimated fallback remain. HLS still cancels its redundant demand task.
That fix is already shipped; it is not a new saving from this goal.

## Decisions

| Candidate | Evidence | Decision |
| --- | --- | --- |
| Replace Foundation links with POSIX links | Existing five-pair link experiment: 0.962 vs 0.936 s medians, overlapping ranges and a reversed pair | Reject: no demonstrated worthwhile real-movie saving |
| Remove full analysis from direct startup | The demonstrated contention is already fixed | No duplicate rewrite or benchmark campaign |
| Skip package/cache integrity checks | No evidence justifies weakening them | Reject |
| Change VOD finalization/segments or either packager | No newly reproduced bottleneck in this goal | Reject speculative changes |
| Cache direct MP4 or parallelize bitmap OCR | Existing evidence does not validate those changed lifetimes/timelines | Separate experiment only if actual usage establishes the need |

There is no new matched measurement of first image/sound, external-drive
performance or retry latency here. No numerical improvement is claimed for this
delivery. Retained reports are sufficient for this conditional decision; another
Apple TV, full-movie remux or large temporary-media campaign would not test a
new hypothesis. Originals, engines, cache budgets and preparation checks stay
unchanged.

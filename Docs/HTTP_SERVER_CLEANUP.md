# Failed HTTP connection cleanup

19 October 2026. Repair for [issue #32](https://github.com/carlosciller/AirCiller/issues/32).
No packager, media format, engine, authorization or conversion behavior changes.

## Cause and evidence

The HTTP server treated Network.framework `failed` and `cancelled` events alike:
it removed the connection and transfer from its dictionaries, but did not cancel
a failed connection. Cleanup therefore depended on later callbacks or reference
release. That is unsafe when outgoing callbacks hold only weak references.

The original CI assertion observed 16 to 31 process descriptors after 160
abandoned ranges. Ordinary local and runner reproductions often passed. Kernel
descriptor diagnostics distinguish server/client TCP sockets, files and internal
Network.framework channels without publishing addresses or paths.

A bounded four-process runner experiment on the unchanged server retained 6,
9 and 10 additional server TCP sockets in CLOSED state; file/channel counts were
stable. Its existing descriptor threshold was not exceeded in that experiment.
These observations identify retained server transports, not an open-video-file
leak or a new aiohttp dependency defect.

- [Unchanged-server contention experiment](https://github.com/carlosciller/AirCiller/actions/runs/39224433278)
- [Corrected-server matched experiment](https://github.com/carlosciller/AirCiller/actions/runs/39224811956)

The correction calls `cancel()` on the failed connection before retiring its
last server reference. Existing cancelled-state and file cleanup remain intact.
In the corrected runner experiment all four process counts returned from 14 to
14; all original HTTP cases and the new terminal-event regression passed.

## Regression and acceptance

The deterministic regression uses a real accepted NWConnection and delivers a
synthetic failure event to its actual server state handler on the server queue.
It retains the connection and requires cancellation within one second. It fails
with the old handler (`FailedConnectionNotCancelled`) and passes the correction.
This is fault injection, not a fresh reproduction of the original CI count of 31.
The injection hook exists only in `AIRCILLER_HTTP_TESTS` builds.

The original stress retains 160 abandoned ranges, the 128-descriptor soft limit,
one-second drain interval, baseline + 12 assertion and post-stress health request.
No acceptance limit, timeout or assertion is relaxed. Descriptor-type diagnostics
remain for future failures. The temporary runner workflow is removed from the
final change; the regression is part of the ordinary strict check.

Validation selection: focused HTTP tests first, one final `Scripts/check.sh`,
exact-head PR CI and brief direct-MP4/HLS receiver checks with seeks and cleanup.
No OCR, long-pause, codec matrix or cache campaign is selected. New receiver
checks require a currently available Apple TV and only its approved digital
screen/audio capture. Keep receiver and output results separate from local
regressions; native-output acceptance is not inferred from this record.

Final run URLs, outcomes and any outstanding observations belong in the PR
handoff. No installed-app replacement or release publication is implied.

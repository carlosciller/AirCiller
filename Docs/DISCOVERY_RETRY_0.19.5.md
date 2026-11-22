# Discovery retry validation

The local coordinator tests exercise the preserved start position, duplicate
Play, cancellation, receiver choice and a retry after an empty discovery.
In the native window, an empty result showed Retry and Cancel; Cancel restored
the ready state. The final full local suite passed with the pinned runtimes.
An earlier HLS process-ownership failure passed in isolation and on the final
full run; the engine was not changed.

One isolated AirPlay check on 22 November injected an empty result only for
the first search. The Retry action used unmodified receiver discovery and
started the original AAC clip without a second Play. The verified digital
source recorded 36 measurements matching the clip's 880 Hz test tone.
Stop restored the ready state. No other media or receiver scenarios were
repeated. The check does not reproduce the cause of intermittent multicast.

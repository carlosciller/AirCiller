# Playback information boundaries

Delivery 3 of the local-library goal. Keep detail in the existing collapsed
technical disclosure, not a new live dashboard.

The view separates original-file badges, the selected preparation plan and an
immutable record of the completed local preparation. The record is populated
only after the existing local package/AVPlayer checks and session-ownership
checks, before AirPlay startup. Stop, replacement and runtime cleanup clear it.
A later selected plan cannot rewrite what that recorded preparation did.

The record names the actual MP4/HLS preparation branch. Compatible and stereo
audio conversions explicitly say lossy; FLAC says lossless without Atmos objects.
Converted output never inherits the source's Atmos label or channel count.
“Up to 5.1” remains an operation bound, not a measured HDMI speaker layout.
Original mode says without re-encoding. No extra probe, decoder, process,
network request, conversion, consent or change to either packager is introduced.

Receiver state is separately labeled as a playback/pause report. File metadata,
local validation, a media request or a receiver state cannot verify HDMI format,
physical HDR rendering, Atmos objects or speakers. The UI says so explicitly;
it does not invent a “verified Atmos” indicator.

Regression checks cover original versus converted descriptions, absence of
inherited channels/Atmos, no-audio behavior, immutable completed information
after a plan change and clearing on Stop. Native review checks the disclosure,
scrolling and long text in both languages. An initial visual review exposed
ellipsis truncation; value and footer text now wrap instead.

The isolated native view passed disclosure/scrolling and complete long-text
readback in English/dark and Spanish/light after the truncation correction.
The synthetic fixture deliberately has no analyzed movie or receiver; it tests
presentation, not a completed real-media preparation. Final strict-gate
validation of this delivery remains pending. The receiver/media behavior is unchanged, so this
presentation-only delivery does not request another Apple TV batch. The earlier
chapter-skip device record remains scoped to its named candidate; it is not a
new test of this information view.

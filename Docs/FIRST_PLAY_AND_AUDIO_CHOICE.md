# First Play and original audio choices (0.19.4 candidate)

Play retains its requested position while receiver discovery is pending. Stop or
opening a different file discards the request. A single receiver, or a previous
selection still present, can continue; an ambiguous list needs a user choice.
This does not retry pairing, relax authorization or change either packager.

For DTS, the playback prompt lists compatible originals with a known matching
language in file order. Track numbers distinguish otherwise identical labels.
Comments, alternate mixes and descriptive tracks are not silently promoted or
excluded. The explicit conversion action and its existing consent scope remain
separate.

The local coordinator regression simulates late discovery, duplicate Play,
Stop, multiple receivers, explicit selection and duplicate completion. It uses
a removed temporary file to observe the handoff at the next startup guard
without contacting a receiver. Track metadata checks cover ordering, language
aliases, unknown languages and incompatible tracks. In the native dialog,
Cancel kept DTS; choosing the second of two original alternatives selected
that exact track. An earlier alert truncated the conversion action; the final
sheet displayed both originals, Cancel and Convert together.

On 20 November the rebuilt isolated candidate received one Play during an
active receiver search. Discovery continued to the audio prompt without a
second Play. Selecting the second original (AAC main mix, after AC-3 commentary)
started AirPlay playback. The approved digital source captured 55 matching
tone measurements (median 880.05 Hz); the other tracks used 440 Hz. Stop
returned the candidate to ready. This sampled check does not claim physical
speaker output. Engines, preparers and streaming formats were unchanged.

"""Independent PCM → development TrueHD → pinned FLAC preservation matrix."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import wave


def checked(command):
    result = subprocess.run(command, capture_output=True, timeout=60)
    if result.returncode != 0 or result.stderr.strip():
        raise RuntimeError(result.stderr.decode(errors="replace")[:2000])
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("encoder", "engine", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    ffmpeg = str(args.engine.resolve() / "ffmpeg")
    ffprobe = str(args.engine.resolve() / "ffprobe")

    def samples(path):
        return checked([ffmpeg, "-v", "error", "-xerror", "-err_detect", "crccheck+explode",
                        "-i", str(path), "-c:a", "pcm_s32le", "-f", "s32le", "pipe:1"])

    def metadata(path):
        stream = json.loads(checked([ffprobe, "-v", "error", "-show_streams", "-of", "json",
                                     str(path)]))["streams"][0]
        return {key: stream.get(key) for key in (
            "sample_rate", "channels", "channel_layout", "bits_per_raw_sample")}

    rows = []
    for bits in (16, 24):
        for rate in (44100, 48000, 88200, 96000, 176400, 192000):
            for channels, layout in ((1, "mono"), (2, "stereo"), (6, "5.1(side)")):
                directory = args.output / f"{bits}-{rate}-{channels}"
                directory.mkdir()
                source, encoded, flac = (directory / name for name in ("source.wav", "source.thd", "converted.flac"))
                data = bytearray()
                expected = bytearray()
                for sample in range(rate * 2):
                    for channel in range(channels):
                        value = round(0.2 * (2 ** (bits - 1) - 1) * math.sin(
                            2 * math.pi * (211 + 137 * channel) * sample / rate))
                        data.extend(struct.pack("<i", value)[:bits // 8])
                        expected.extend(struct.pack("<i", value << (32 - bits)))
                with wave.open(str(source), "wb") as writer:
                    writer.setnchannels(channels)
                    writer.setsampwidth(bits // 8)
                    writer.setframerate(rate)
                    writer.writeframes(data)
                checked([str(args.encoder.resolve()), "-v", "error", "-nostdin", "-n",
                         "-channel_layout", layout, "-i", str(source), "-c:a", "truehd",
                         "-sample_fmt", "s16p" if bits == 16 else "s32p",
                         "-strict", "experimental", str(encoded)])
                checked([ffmpeg, "-v", "error", "-xerror", "-err_detect", "crccheck+explode",
                         "-nostdin", "-n", "-i", str(encoded), "-c:a", "flac", str(flac)])
                original_metadata, converted_metadata = metadata(encoded), metadata(flac)
                truehd_pcm, flac_pcm = samples(encoded), samples(flac)
                identical = truehd_pcm == expected and flac_pcm == expected
                layout_preserved = all(original_metadata[key] == converted_metadata[key]
                                       for key in ("sample_rate", "channels", "channel_layout"))
                encoded_bits = int(original_metadata["bits_per_raw_sample"])
                precision_preserved = encoded_bits >= bits and int(
                    converted_metadata["bits_per_raw_sample"]) == encoded_bits
                rows.append({"bits": bits, "rate": rate, "channels": channels, "layout": layout,
                             "expectedBytes": len(expected), "expectedSHA256": hashlib.sha256(expected).hexdigest(),
                             "truehdSHA256": hashlib.sha256(truehd_pcm).hexdigest(),
                             "flacSHA256": hashlib.sha256(flac_pcm).hexdigest(),
                             "identicalSamples": identical, "identicalLayoutRate": layout_preserved,
                             "identicalPrecision": precision_preserved,
                             "truehdDeclaredBits": encoded_bits,
                             "inputMetadata": original_metadata, "outputMetadata": converted_metadata})
    report = {"receiverTested": False, "cases": rows}
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    passed = sum(row["identicalSamples"] and row["identicalLayoutRate"] and row["identicalPrecision"] for row in rows)
    print(f"Complete PCM, precision, rate and layout: {passed}/{len(rows)}")
    if passed != len(rows):
        raise SystemExit(1)


if __name__ == "__main__":
    main()

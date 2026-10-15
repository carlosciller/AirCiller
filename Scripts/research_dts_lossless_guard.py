"""Test native XLL decoding and strict-error recovery with a bounded FATE sample."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "engine", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    if not args.source.is_file() or args.source.stat().st_size > 1_048_576:
        raise ValueError("Use the short FATE XLL fixture")
    data = args.source.read_bytes()
    positions = []
    cursor = 0
    while True:
        cursor = data.find(bytes.fromhex("41a29547"), cursor)
        if cursor < 0:
            break
        positions.append(cursor)
        cursor += 4
    if len(positions) != 7:
        raise ValueError("Unexpected XLL framing")
    args.output.mkdir(parents=True, exist_ok=False)
    corrupted = bytearray(data)
    corrupted[positions[3]] ^= 1
    damaged = args.output / "damaged-xll-sync.dtshd"
    damaged.write_bytes(corrupted)
    extension_positions = []
    cursor = 0
    while True:
        cursor = data.find(bytes.fromhex("64582025"), cursor)
        if cursor < 0:
            break
        extension_positions.append(cursor)
        cursor += 4
    if len(extension_positions) != 7:
        raise ValueError("Unexpected extension framing")
    missing_data = bytearray(data)
    missing_data[extension_positions[3]] ^= 1
    missing = args.output / "missing-extension-sync.dtshd"
    missing.write_bytes(missing_data)
    engine = args.engine.resolve()
    rows = []
    for label, source in (("original", args.source), ("damaged", damaged), ("missingExtension", missing)):
        flac = args.output / (label + ".flac")
        command = [str(engine / "ffmpeg"), "-hide_banner", "-nostdin", "-n", "-v", "verbose", "-noauto_conversion_filters",
                   "-xerror", "-err_detect", "explode", "-core_only", "0", "-i", str(source.resolve()),
                   "-map", "0:a:0", "-af", "aresample=isf=s32p:osf=s32", "-c:a", "flac", str(flac.resolve())]
        result = subprocess.run(command, capture_output=True, timeout=30)
        row = {"case": label, "exitCode": result.returncode,
               "invalidXLLSyncReported": b"Invalid XLL sync word" in result.stderr,
               "forcedRecoveryReported": b"Forcing XLL recovery mode" in result.stderr}
        metadata = json.loads(subprocess.check_output([
            str(engine / "ffprobe"), "-v", "error", "-show_streams", "-of", "json", str(source)
        ], stderr=subprocess.PIPE, timeout=30))["streams"][0]
        row["inputMetadata"] = {key: metadata.get(key) for key in (
            "profile", "sample_fmt", "sample_rate", "channels", "channel_layout", "bits_per_raw_sample")}
        if result.returncode == 0:
            pcm = subprocess.check_output([str(engine / "ffmpeg"), "-v", "error", "-i", str(flac),
                                           "-c:a", "pcm_s24le", "-f", "s24le", "pipe:1"], stderr=subprocess.PIPE, timeout=30)
            row.update(decodedBytes=len(pcm), decodedSHA256=hashlib.sha256(pcm).hexdigest())
        rows.append(row)
    if args.source.read_bytes() != data:
        raise ValueError("Original input changed")
    report = {"sourceSHA256": hashlib.sha256(data).hexdigest(), "sourceUnchanged": True,
              "XLLFrames": len(positions), "receiverTested": False, "cases": rows}
    with (args.output / "report.json").open("x") as output:
        json.dump(report, output, indent=2)
        output.write("\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

"""Bounded TrueHD reference preservation and damaged-input research; no app eligibility claim."""
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
    data = args.source.read_bytes()
    expected_sha = "f00a67adeec561c8bb9e98da06e38f5d3f204778ff931c592f81db54ce428127"
    if len(data) != 655360 or hashlib.sha256(data).hexdigest() != expected_sha:
        raise ValueError("Use the exact FATE truehd_5.1.raw reference")
    args.output.mkdir(parents=True, exist_ok=False)
    changed = bytearray(data)
    changed[len(data) // 2] ^= 128
    variants = [("original", args.source)]
    for label, payload in (("flippedByte", changed), ("truncatedByte", data[:-1]),
                           ("truncatedTail", data[:-4096])):
        path = args.output / (label + ".thd")
        path.write_bytes(payload)
        variants.append((label, path))
    ffmpeg = str(args.engine.resolve() / "ffmpeg")
    rows = []
    for label, source in variants:
        flac = args.output / (label + ".flac")
        result = subprocess.run([
            ffmpeg, "-hide_banner", "-nostdin", "-n", "-v", "error", "-xerror",
            "-err_detect", "explode", "-f", "truehd", "-i", str(source.resolve()),
            "-map", "0:a:0", "-c:a", "flac", str(flac.resolve())
        ], capture_output=True, timeout=30)
        row = {"case": label, "exitCode": result.returncode,
               "diagnostic": result.stderr.decode("utf-8", errors="replace")[:2048]}
        if result.returncode == 0:
            pcm = subprocess.check_output([
                ffmpeg, "-v", "error", "-xerror", "-i", str(flac),
                "-c:a", "pcm_s32le", "-f", "s32le", "pipe:1"
            ], stderr=subprocess.PIPE, timeout=30)
            row.update(decodedBytes=len(pcm), decodedMD5=hashlib.md5(pcm).hexdigest())
        rows.append(row)
    if rows[0].get("decodedMD5") != "95d8aac39dd9f0d7fb83dc7b6f88df35":
        raise ValueError("Complete decoded FLAC differs from independent FATE PCM reference")
    if args.source.read_bytes() != data:
        raise ValueError("Original changed")
    report = {"sourceSHA256": expected_sha, "sourceUnchanged": True,
              "receiverTested": False, "cases": rows}
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

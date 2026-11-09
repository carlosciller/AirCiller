"""Prepare a private 60-second bitmap-boundary fixture, without video encoding.

Arguments: source movie, PGS stream index, existing 60-second HDR fixture, output
directory (must not exist). Only copies subtitle packets and encoded HDR media.
The last display has deliberately no clear event: actual OCR must bound it by VOD.
"""
from pathlib import Path
import json
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
from benchmark_bitmap_preparation import ENGINE


def main():
    source, index, hdr, destination = sys.argv[1:]
    if not Path(source).is_file() or not Path(hdr).is_file() or Path(hdr).stat().st_size > 2 * 1024**3:
        raise ValueError("Expected existing source and bounded HDR clip")
    metadata = json.loads(subprocess.check_output([
        str(ENGINE / "ffprobe"), "-v", "error", "-show_entries", "format=duration",
        "-of", "json", hdr], timeout=15))
    if not 59 <= float(metadata["format"]["duration"]) <= 61:
        raise ValueError("This boundary fixture requires a 60-second HDR clip")
    root = Path(destination)
    root.mkdir(mode=0o700, parents=False, exist_ok=False)
    original = root / "source.sup"
    subprocess.run([str(ENGINE / "ffmpeg"), "-v", "error", "-nostdin", "-i", source,
                    "-map", f"0:{int(index)}", "-c", "copy", "-frames:s", "2", str(original)],
                   check=True, timeout=60)
    data = original.read_bytes()
    groups = []
    offset = 0
    while offset < len(data):
        if data[offset:offset+2] != b"PG" or offset + 13 > len(data):
            raise ValueError("Invalid SUP header")
        pts, dts, kind, length = struct.unpack(">IIBH", data[offset+2:offset+13])
        payload = data[offset+13:offset+13+length]
        if len(payload) != length:
            raise ValueError("Truncated segment")
        if not groups or groups[-1][0] != pts:
            groups.append((pts, []))
        groups[-1][1].append((kind, payload))
        offset += 13 + length
    if len(groups) != 2:
        raise ValueError("Expected one complete display and one clear")
    display, clear = groups[0][1], groups[1][1]
    def object_count(segments):
        pcs = next(payload for kind, payload in segments if kind == 0x16)
        return pcs[10]
    if object_count(display) == 0 or object_count(clear) != 0:
        raise ValueError("Unexpected display/clear ordering")
    output = bytearray()
    for seconds, segments in [(0, display), (40, clear), (58, display)]:
        for kind, payload in segments:
            output += b"PG" + struct.pack(">IIBH", seconds * 90000, 0, kind, len(payload)) + payload
    sup = root / "terminal.eng.sup"
    sup.write_bytes(output)
    # Keep the source encoded video/audio and put the bitmap in its own stream.
    subprocess.run([str(ENGINE / "ffmpeg"), "-v", "error", "-nostdin", "-i", hdr,
                    "-i", str(sup), "-map", "0:v:0", "-map", "0:a:0", "-map", "1:0",
                    "-c", "copy", "-metadata:s:s:0", "language=eng", str(root / "terminal-hdr.mkv")],
                   check=True, timeout=60)
    (root / "fixture.json").write_text(json.dumps({
        "sourceDisplayCopied": True, "displayStarts": [0, 58], "clearAt": 40,
        "lastDisplayHasNoClear": True, "videoReencoded": False,
        "purpose": "Terminal bitmap interval bounded by 60-second source movie"}, indent=2) + "\n")
    print(root)


if __name__ == "__main__":
    main()

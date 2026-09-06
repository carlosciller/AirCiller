"""Compare bounded local fixtures with remux output. Never opens a media device."""
import hashlib
import json
import math
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
from playback_capture import bounded_command


def coded_picture_digest(data, codec):
    """Ignore container framing and repeated parameter sets, retain coded pictures and DV RPU."""
    digest, count = hashlib.sha256(), 0
    for nal in re.split(b"\x00\x00(?:\x00)?\x01", data):
        nal = nal.rstrip(b"\x00")  # Annex B trailing_zero_8bits
        if not nal:
            continue
        kind = nal[0] & 31 if codec == "h264" else (nal[0] >> 1) & 63
        retain = 1 <= kind <= 5 if codec == "h264" else kind <= 31 or kind == 62
        if retain:
            digest.update(len(nal).to_bytes(4, "big"))
            digest.update(nal)
            count += 1
    if not count:
        raise ValueError("No coded pictures")
    return count, digest.hexdigest()


def packet_audio_digest(data):
    """Compare encoded FLAC frames without container-generated FLAC metadata blocks."""
    packets = json.loads(data)["packets"]
    if not packets:
        raise ValueError("No encoded audio packets")
    digest = hashlib.sha256()
    for packet in packets:
        size, value = int(packet["size"]), packet["data_hash"]
        if size <= 0 or not re.fullmatch(r"SHA256:[0-9a-fA-F]{64}", value):
            raise ValueError("Invalid audio packet")
        digest.update(size.to_bytes(8, "big"))
        digest.update(bytes.fromhex(value.removeprefix("SHA256:")))
    return digest.hexdigest()


def packet_duration(data):
    packets = json.loads(data)["packets"]
    if not packets:
        raise ValueError("No timed packets")
    intervals = [(float(p["pts_time"]), float(p["duration_time"])) for p in packets]
    if any(not math.isfinite(t) or not math.isfinite(d) or d <= 0 for t, d in intervals):
        raise ValueError("Invalid packet timing")
    span = max(t + d for t, d in intervals) - min(t for t, _ in intervals)
    if not math.isfinite(span) or span <= 0:
        raise ValueError("Invalid packet duration")
    return span


def verify(source, directory, engine):
    ffmpeg, ffprobe = engine / "ffmpeg", engine / "ffprobe"

    def probe(path):
        return json.loads(bounded_command([ffprobe, "-v", "error", "-analyzeduration", "10000000",
                                           "-probesize", "32000000", "-show_streams", "-show_format",
                                           "-of", "json", path], limit=2_000_000))

    original = probe(source)
    if not 45 <= float(original["format"]["duration"]) <= 180:
        raise ValueError("Only short fixtures are accepted")
    video = next(s for s in original["streams"] if s["codec_type"] == "video")
    audio = next(s for s in original["streams"] if s["codec_type"] == "audio")
    if video["codec_name"] not in {"h264", "hevc"} or audio["codec_name"] not in {"aac", "ac3", "eac3", "flac"}:
        raise ValueError("Unsupported fixture codecs")
    direct = (directory / "movie.mp4").is_file()
    video_path = directory / ("movie.mp4" if direct else "video.m3u8")
    audio_path = directory / ("movie.mp4" if direct else "audio.m3u8")
    if not direct and not audio_path.is_file():
        audio_path = video_path  # Multiplexed HDR HLS, with no separate audio rendition.

    def elementary(path, stream, codec):
        output_format = "adts" if codec == "aac" else codec
        filters = ["-bsf:v", f"{codec}_mp4toannexb"] if stream == "v" else []
        return bounded_command([ffmpeg, "-v", "error", "-nostdin", "-i", path,
                                "-map", f"0:{stream}:0", "-c", "copy", *filters,
                                "-f", output_format, "pipe:1"], timeout=60, limit=134_217_728)

    before_video = coded_picture_digest(elementary(source, "v", video["codec_name"]), video["codec_name"])
    after_video = coded_picture_digest(elementary(video_path, "v", video["codec_name"]), video["codec_name"])
    if before_video != after_video:
        raise ValueError("Coded video changed")
    def audio_digest(path):
        if audio["codec_name"] == "flac":
            return packet_audio_digest(bounded_command([
                ffprobe, "-v", "error", "-select_streams", "a:0", "-show_packets",
                "-show_entries", "packet=size,data_hash", "-show_data_hash", "sha256", "-of", "json", path],
                timeout=60, limit=4_000_000))
        return hashlib.sha256(elementary(path, "a", audio["codec_name"])).hexdigest()

    before_audio = audio_digest(source)
    after_audio = audio_digest(audio_path)
    if before_audio != after_audio:
        raise ValueError("Encoded audio changed")
    video_info, audio_info = probe(video_path), probe(audio_path)
    prepared_video = next(s for s in video_info["streams"] if s["codec_type"] == "video")
    prepared_audio = next(s for s in audio_info["streams"] if s["codec_type"] == "audio")

    def duration(path, stream):
        if "duration" in stream:
            value = float(stream["duration"])
            if not math.isfinite(value) or value <= 0:
                raise ValueError("Invalid stream duration")
            return value
        # Matroska often omits stream duration. The container's duration may
        # include another track's lead-in or tail; measure this stream itself.
        return packet_duration(bounded_command([
            ffprobe, "-v", "error", "-select_streams", str(stream["index"]),
            "-show_packets", "-show_entries", "packet=pts_time,duration_time", "-of", "json", path],
            timeout=60, limit=4_000_000))

    for before, after, info in [(video, prepared_video, video_info), (audio, prepared_audio, audio_info)]:
        for key in ["codec_name", "profile", "width", "height", "color_transfer", "channels", "channel_layout",
                    "sample_rate", "bits_per_raw_sample"]:
            if before.get(key) != after.get(key):
                raise ValueError(f"Stream property changed: {key}")
        if not 0 <= float(after["start_time"]) < 1:
            raise ValueError("Output did not start near zero")
        before_duration = duration(source, before)
        output_path = video_path if before is video else audio_path
        if abs(duration(output_path, after) - before_duration) > 0.2:
            raise ValueError("Stream duration changed")
    original_offset = float(video["start_time"]) - float(audio["start_time"])
    prepared_offset = float(prepared_video["start_time"]) - float(prepared_audio["start_time"])
    # Existing remux paths may retain codec preroll; reject a TS clock origin leaking into playback.
    if abs(original_offset - prepared_offset) > 0.15:
        raise ValueError("Audio/video relative start changed")
    result = {"codedVideoSHA256": before_video[1], "codedPictureUnits": before_video[0],
              "encodedAudioSHA256": before_audio, "videoCodec": video["codec_name"],
              "audioCodec": audio["codec_name"], "sourceStart": original["format"]["start_time"],
              "relativeStartDifference": prepared_offset - original_offset, "copyVerified": True}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("Usage: verify_stream_copy.py SOURCE OUTPUT_DIRECTORY PINNED_FFMPEG_BIN_DIRECTORY")
    verify(*(Path(value).resolve() for value in sys.argv[1:]))

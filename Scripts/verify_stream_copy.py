"""Compare bounded local fixtures with remux output. Never opens a media device."""
import hashlib
import json
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
    if video["codec_name"] not in {"h264", "hevc"} or audio["codec_name"] not in {"aac", "ac3", "eac3"}:
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
    before_audio = hashlib.sha256(elementary(source, "a", audio["codec_name"])).hexdigest()
    after_audio = hashlib.sha256(elementary(audio_path, "a", audio["codec_name"])).hexdigest()
    if before_audio != after_audio:
        raise ValueError("Encoded audio changed")
    video_info, audio_info = probe(video_path), probe(audio_path)
    prepared_video = next(s for s in video_info["streams"] if s["codec_type"] == "video")
    prepared_audio = next(s for s in audio_info["streams"] if s["codec_type"] == "audio")
    for before, after, info in [(video, prepared_video, video_info), (audio, prepared_audio, audio_info)]:
        for key in ["codec_name", "profile", "width", "height", "color_transfer", "channels", "channel_layout"]:
            if before.get(key) != after.get(key):
                raise ValueError(f"Stream property changed: {key}")
        if not 0 <= float(after["start_time"]) < 1:
            raise ValueError("Output did not start near zero")
        before_duration = float(before.get("duration", original["format"]["duration"]))
        if abs(float(after.get("duration", info["format"]["duration"])) - before_duration) > 0.2:
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

"""Opt-in complete TrueHD → FLAC production HLS checks; no receiver or capture."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
from verify_stream_copy import coded_picture_digest


def audio_timeline_matches(before, after, before_rate, after_rate, origin):
    """Compare sample-index clocks across different codec frame boundaries."""
    if before_rate <= 0 or before_rate != after_rate or not math.isfinite(origin):
        return False
    try:
        left = [(float(frame["pts_time"]), int(frame["nb_samples"])) for frame in before]
        right = [(float(frame["pts_time"]), int(frame["nb_samples"])) for frame in after]
    except (KeyError, TypeError, ValueError, OverflowError):
        return False
    if not left or not right or any(
        not math.isfinite(pts) or count <= 0 for pts, count in (*left, *right)
    ):
        return False
    left_index = right_index = left_used = right_used = 0
    while left_index < len(left) and right_index < len(right):
        left_pts, left_count = left[left_index]
        right_pts, right_count = right[right_index]
        # The two intervals cover the same source sample indices. Checking each
        # overlap observes both sides of every discontinuity, even when the
        # overall start/end and complete decoded PCM are unchanged. Matroska's
        # millisecond timestamp rounding is the only permitted clock tolerance.
        difference = (right_pts + right_used / after_rate
                      - left_pts - left_used / before_rate - origin)
        if abs(difference) > 0.001 + 1e-9:
            return False
        count = min(left_count - left_used, right_count - right_used)
        left_used += count
        right_used += count
        if left_used == left_count:
            left_index += 1
            left_used = 0
        if right_used == right_count:
            right_index += 1
            right_used = 0
    return left_index == len(left) and right_index == len(right)


def check_audio_timeline_regressions():
    def frames(values):
        return [{"pts_time": pts, "nb_samples": count} for pts, count in values]

    source = frames([(0, 1000), (1, 1000), (2, 1000)])
    cases = [
        (frames([(0, 1500), (1.5, 1500)]), 0, True),
        (frames([(10, 1500), (11.5, 1500)]), 10, True),
        (frames([(0, 1000), (1.001, 1000), (2, 1000)]), 0, True),
        # Same first/last clocks and sample count, different middle timing.
        (frames([(0, 1000), (1.1, 1000), (2, 1000)]), 0, False),
        (frames([(0, 1000), (.9, 1000), (2, 1000)]), 0, False),
        (frames([(0, 1000), (1.00101, 1000), (2, 1000)]), 0, False),
        (frames([(0, 1000), (1, 1000), (2, 999)]), 0, False),
        (frames([(0, 1000), (float("nan"), 1000), (2, 1000)]), 0, False),
        ([], 0, False),
    ]
    for candidate, origin, expected in cases:
        if audio_timeline_matches(source, candidate, 1000, 1000, origin) != expected:
            raise AssertionError("Sample-index timeline regression")
    if audio_timeline_matches(source, source, 1000, 2000, 0):
        raise AssertionError("A changed sample rate cannot preserve the sample-index clock")
    # A boundary present only in the source must also be inspected.
    if audio_timeline_matches(cases[3][0], frames([(0, 3000)]), 1000, 1000, 0):
        raise AssertionError("Source discontinuity disappeared inside one output frame")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("engine", "runner", "video", "fixtures", "output"):
        parser.add_argument("--" + name, type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--additional-movie", type=Path, action="append", default=[])
    parser.add_argument("--only-additional", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        check_audio_timeline_regressions()
        print("TrueHD sample-index timeline regressions: OK")
        return
    missing = [name for name in ("engine", "runner", "video", "fixtures", "output")
               if getattr(args, name) is None]
    if missing:
        parser.error("Required for media validation: " + ", ".join("--" + name for name in missing))
    args.output.mkdir(parents=True, exist_ok=False)
    ffmpeg = str(args.engine.resolve() / "ffmpeg")
    ffprobe = str(args.engine.resolve() / "ffprobe")

    def run(command):
        result = subprocess.run(command, capture_output=True, timeout=90)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors="replace")[-3000:])
        return result.stdout

    def pcm(path):
        payload = run([ffmpeg, "-v", "error", "-xerror", "-i", str(path), "-map", "0:a:0",
                       "-c:a", "pcm_s32le", "-f", "s32le", "pipe:1"])
        return len(payload), hashlib.sha256(payload).hexdigest()

    def packets(path, selector):
        return json.loads(run([ffprobe, "-v", "error", "-select_streams", selector,
                               "-show_packets", "-show_data_hash", "sha256", "-of", "json",
                               str(path)]))["packets"]

    def metadata(path, selector="a:0"):
        return json.loads(run([ffprobe, "-v", "error", "-select_streams", selector,
                               "-show_streams", "-of", "json", str(path)]))["streams"][0]

    def audio_frames(path):
        return json.loads(run([ffprobe, "-v", "error", "-select_streams", "a:0",
                               "-show_frames", "-show_entries", "frame=pts_time,nb_samples",
                               "-of", "json", str(path)]))["frames"]

    def pictures(path, codec):
        payload = run([ffmpeg, "-v", "error", "-i", str(path), "-map", "0:v:0",
                       "-c:v", "copy", "-bsf:v", f"{codec}_mp4toannexb", "-f", codec, "pipe:1"])
        return coded_picture_digest(payload, codec)

    rows = []
    fixtures = [] if args.only_additional else [
        (path.parent.name, path, False) for path in sorted(args.fixtures.glob("24-*/source.thd"))]
    fixtures += [(path.stem, path, True) for path in args.additional_movie]
    for label, fixture, is_movie in fixtures:
        directory = args.output / label
        directory.mkdir()
        source = fixture.resolve() if is_movie else directory / "source.mkv"
        if not is_movie:
            run([ffmpeg, "-v", "error", "-n", "-i", str(args.video.resolve()), "-i", str(fixture.resolve()),
                 "-map", "0:v:0", "-map", "1:a:0", "-c", "copy", "-t", "2", str(source)])
        expected_pcm = pcm(source)
        before = metadata(source)
        video_codec = metadata(source, "v:0")["codec_name"]
        if video_codec not in ("h264", "hevc"):
            raise ValueError("A copied H.264 or HEVC movie is required")
        expected_picture = pictures(source, video_codec)
        before_video = packets(source, "v:0")
        before_audio = audio_frames(source)
        cache = directory / "cache"
        for warm in (False, True):
            output = directory / ("warm" if warm else "cold")
            result = subprocess.run([
                str(args.runner.resolve()), str(source.resolve()), str(output.resolve()),
                str(args.engine.resolve()), "losslessFLAC", str(cache.resolve()), "--no-subtitles"
            ], capture_output=True, timeout=90)
            row = {"case": label, "warm": warm, "exitCode": result.returncode,
                   "diagnostic": result.stderr.decode(errors="replace")[-2000:]}
            if result.returncode == 0:
                prepared = json.loads(result.stdout.decode().splitlines()[-1])
                video_playlist = output / "video.m3u8"
                audio_playlist = video_playlist if prepared["hdr"] else output / "audio.m3u8"
                after = metadata(audio_playlist)
                after_video = packets(video_playlist, "v:0")
                after_audio = audio_frames(audio_playlist)
                origin = float(after_video[0]["pts_time"]) - float(before_video[0]["pts_time"])
                video_preserved = len(before_video) == len(after_video) and all(
                    abs(float(after_packet[key]) - float(before_packet[key]) - origin) <= 0.001 + 1e-9
                    for before_packet, after_packet in zip(before_video, after_video)
                    for key in ("pts_time", "dts_time") if key in before_packet and key in after_packet)
                audio_preserved = audio_timeline_matches(
                    before_audio, after_audio, int(before["sample_rate"]), int(after["sample_rate"]), origin)
                checks = {
                    "completePCMEqual": pcm(audio_playlist) == expected_pcm,
                    "decodedSampleCountEqual": sum(int(f["nb_samples"]) for f in before_audio)
                    == sum(int(f["nb_samples"]) for f in after_audio),
                    "codedVideoEqual": pictures(video_playlist, video_codec) == expected_picture,
                    "videoTimelineEqual": video_preserved, "audioTimelineEqual": audio_preserved,
                    "metadataEqual": all(before.get(key) == after.get(key) for key in (
                        "sample_rate", "channels", "channel_layout", "bits_per_raw_sample")),
                    "cacheExpected": prepared["used_cache"] == warm,
                    "finishedVOD": all("#EXT-X-ENDLIST" in path.read_text()
                                       for path in (audio_playlist, video_playlist)),
                }
                row.update(checks=checks, passed=all(checks.values()), hdr=prepared["hdr"], inputMetadata={
                    key: before.get(key) for key in ("sample_rate", "channels", "channel_layout", "bits_per_raw_sample")},
                    decodedBytes=expected_pcm[0], decodedSHA256=expected_pcm[1])
            else:
                row["passed"] = False
            rows.append(row)
    if not rows:
        raise ValueError("No independently generated 24-bit TrueHD fixtures")
    (args.output / "report.json").write_text(json.dumps({"receiverTested": False, "cases": rows}, indent=2) + "\n")
    print(f"Production HLS preservation: {sum(row['passed'] for row in rows)}/{len(rows)}")
    if not all(row["passed"] for row in rows):
        raise SystemExit(1)


if __name__ == "__main__":
    main()

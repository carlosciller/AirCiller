#!/usr/bin/env python3
"""Opt-in production HLS PCM checks. Never opens a receiver or capture device."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import time
from verify_stream_copy import coded_picture_digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--video', type=Path, required=True, help='Existing legal synthetic H.264 fixture')
    parser.add_argument('--audio-fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--bluray', action='store_true', help='Generate real LPCM-framed M2TS using the pinned encoder')
    parser.add_argument('--no-subtitles', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    ffmpeg = str((args.engine / 'ffmpeg').resolve())
    ffprobe = str((args.engine / 'ffprobe').resolve())

    def execute(command):
        return subprocess.run(command, capture_output=True, timeout=90)

    def required(command):
        result = execute(command)
        if result.returncode:
            raise RuntimeError(result.stderr.decode()[-4000:])
        return result.stdout

    def decoded(path):
        data = required([ffmpeg, '-v', 'error', '-i', str(path), '-map', '0:a:0',
                         '-c:a', 'pcm_s32le', '-f', 's32le', 'pipe:1'])
        return len(data), hashlib.sha256(data).hexdigest()

    def packets(path, selector):
        raw = required([ffprobe, '-v', 'error', '-select_streams', selector,
                        '-show_packets', '-show_data_hash', 'sha256', '-of', 'json', str(path)])
        return json.loads(raw)['packets']

    def stream(path):
        raw = required([ffprobe, '-v', 'error', '-select_streams', 'a:0', '-show_streams',
                        '-of', 'json', str(path)])
        return json.loads(raw)['streams'][0]

    def pictures(path):
        data = required([ffmpeg, '-v', 'error', '-i', str(path), '-map', '0:v:0',
                         '-c:v', 'copy', '-bsf:v', f'{video_codec}_mp4toannexb', '-f', video_codec, 'pipe:1'])
        return coded_picture_digest(data, video_codec)

    video_info = json.loads(required([ffprobe, '-v', 'error', '-select_streams', 'v:0',
                                     '-show_entries', 'stream=codec_name', '-of', 'json', str(args.video.resolve())]))
    video_codec = video_info['streams'][0]['codec_name']
    if video_codec not in ('h264', 'hevc'):
        raise ValueError('A synthetic H.264 or HEVC fixture is required')

    def bounds(values):
        return min(float(p['pts_time']) for p in values), max(
            float(p['pts_time']) + float(p['duration_time']) for p in values)

    results = []
    for fixture in sorted(args.audio_fixtures.glob('pcm_*/source.mov')):
        if args.bluray and (not fixture.parent.name.startswith(('pcm_s16le-', 'pcm_s24le-'))
                            or fixture.parent.name.endswith('-5.1')):
            continue
        directory = args.output / fixture.parent.name
        directory.mkdir()
        subtitle = directory / 'source.srt'
        subtitle.write_text('1\n00:00:00,500 --> 00:00:07,500\nPCM local check\n', encoding='utf8')
        source = directory / ('source.m2ts' if args.bluray else 'source.mov')
        required([ffmpeg, '-v', 'error', '-i', str(args.video.resolve()), '-stream_loop', '3',
                  '-i', str(fixture.resolve()),
                  '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy',
                  '-c:a', 'pcm_bluray' if args.bluray else 'copy',
                  *(['-mpegts_m2ts_mode', '1'] if args.bluray else []), '-t', '8', str(source)])
        metadata = stream(source)
        output = directory / 'hls'
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        started = time.monotonic()
        prepared = execute([str(args.runner.resolve()), str(source.resolve()), str(output.resolve()),
                            str(args.engine.resolve()), 'losslessFLAC',
                            *(['--no-subtitles'] if args.no_subtitles else [])])
        elapsed = time.monotonic() - started
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        case = {'case': fixture.parent.name, 'source': metadata, 'exit_code': prepared.returncode,
                'wall_seconds': elapsed, 'cpu_seconds': after.ru_utime + after.ru_stime
                - usage.ru_utime - usage.ru_stime,
                'stderr': prepared.stderr.decode()[-3000:]}
        # Rear 5.1 is intentionally rejected. No process should prepare outputs.
        expected_rejection = metadata.get('channel_layout') == '5.1'
        if expected_rejection:
            case['passed'] = prepared.returncode == 2 and (
                'Esta pista no admite conversión PCM a FLAC sin pérdida.' in case['stderr']
            ) and not list(output.glob('*.m4s'))
        elif prepared.returncode == 0:
            case['runner'] = json.loads(prepared.stdout.decode().splitlines()[-1])
            case['subtitle_selection_equal'] = case['runner']['subtitles'] == (not args.no_subtitles)
            video_playlist = output / 'video.m3u8'
            audio_playlist = output / ('video.m3u8' if case['runner']['hdr'] else 'audio.m3u8')
            original_video = packets(source, 'v:0')
            output_video = packets(video_playlist, 'v:0')
            case['raw_video_packets_equal'] = [(p['size'], p['data_hash']) for p in original_video] == [
                (p['size'], p['data_hash']) for p in output_video]
            case['coded_video_equal'] = pictures(source) == pictures(video_playlist)
            case['video_packet_count_equal'] = len(original_video) == len(output_video)
            origin_shift = float(output_video[0]['pts_time']) - float(original_video[0]['pts_time'])
            case['video_timeline_equal'] = len(original_video) == len(output_video) and all(
                abs(float(after[key]) - float(before[key]) - origin_shift) < 0.002
                for before, after in zip(original_video, output_video) for key in ('pts_time', 'dts_time'))
            playlist_duration = sum(float(line.split(':', 1)[1].rstrip(','))
                                    for line in video_playlist.read_text().splitlines()
                                    if line.startswith('#EXTINF:'))
            decode_start = min(float(p['dts_time']) for p in output_video)
            decode_end = max(float(p['dts_time']) + float(p['duration_time']) for p in output_video)
            case['declared_duration_error'] = playlist_duration - (decode_end - decode_start)
            case['reported_duration_error'] = case['runner']['duration'] - playlist_duration
            case['pcm_equal'] = decoded(source) == decoded(audio_playlist)
            output_audio = stream(audio_playlist)
            case['output_audio'] = output_audio
            case['layout_equal'] = metadata.get('channel_layout') == output_audio.get('channel_layout')
            case['sample_rate_equal'] = metadata.get('sample_rate') == output_audio.get('sample_rate')
            before_audio = bounds(packets(source, 'a:0'))
            before_video = bounds(original_video)
            after_audio = bounds(packets(audio_playlist, 'a:0'))
            after_video = bounds(output_video)
            # Each rendition may share a different constant presentation origin;
            # compare relative A/V start and final sample extent, not absolute PTS.
            start_error = (after_audio[0] - after_video[0]) - (before_audio[0] - before_video[0])
            tail_error = (after_audio[1] - after_video[0]) - (before_audio[1] - before_video[0])
            case['relative_start_error'] = start_error
            case['relative_tail_error'] = tail_error
            case['temporary_bytes'] = sum(p.stat().st_size for p in output.iterdir() if p.is_file())
            case['passed'] = all(case[key] for key in ('coded_video_equal', 'video_packet_count_equal', 'video_timeline_equal', 'pcm_equal',
                                                      'layout_equal', 'sample_rate_equal', 'subtitle_selection_equal')) and max(
                                                          abs(start_error), abs(tail_error),
                                                          abs(case['declared_duration_error']),
                                                          abs(case['reported_duration_error'])) < 0.002
        else:
            case['passed'] = False
        results.append(case)
        print(case['case'], 'PASS' if case['passed'] else 'FAIL', flush=True)
        (args.output / 'results.json').write_text(json.dumps(
            {'receiver_tested': False, 'cases': results}, indent=2) + '\n')
    if not results or not all(case['passed'] for case in results):
        raise SystemExit(1)


if __name__ == '__main__':
    main()

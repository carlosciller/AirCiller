#!/usr/bin/env python3
"""Receiver-free comparison of separate PCM/FLAC HLS clocks using the real builder."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from verify_stream_copy import coded_picture_digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--source', type=Path, action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    ffmpeg, ffprobe = (str((args.engine / name).resolve()) for name in ('ffmpeg', 'ffprobe'))

    def required(command):
        return subprocess.check_output(command, stderr=subprocess.PIPE, timeout=90)

    def packets(path, selector):
        return json.loads(required([ffprobe, '-v', 'error', '-select_streams', selector,
                                    '-show_packets', '-of', 'json', str(path)]))['packets']

    def pcm(path):
        data = required([ffmpeg, '-v', 'error', '-i', str(path), '-map', '0:a:0',
                         '-c:a', 'pcm_s32le', '-f', 's32le', 'pipe:1'])
        return len(data), hashlib.sha256(data).hexdigest()

    def pictures(path):
        data = required([ffmpeg, '-v', 'error', '-i', str(path), '-map', '0:v:0',
                         '-c:v', 'copy', '-bsf:v', 'h264_mp4toannexb', '-f', 'h264', 'pipe:1'])
        return coded_picture_digest(data, 'h264')

    def bounds(values):
        return (min(float(p['pts_time']) for p in values),
                max(float(p['pts_time']) + float(p['duration_time']) for p in values))

    results = []
    for number, source in enumerate(args.source, 1):
        source = source.resolve()
        before_audio, before_video = bounds(packets(source, 'a:0')), bounds(packets(source, 'v:0'))
        for variant in ('default', 'disabled', 'negative-cts', 'combined'):
            output = args.output / f'case-{number}-{variant}'
            process = subprocess.run([str(args.runner.resolve()), str(source), str(output.resolve()),
                                      str(args.engine.resolve()), 'losslessFLAC', '--clock-' + variant],
                                     capture_output=True, timeout=90)
            row = {'source_number': number, 'variant': variant, 'exit_code': process.returncode,
                   'stderr': process.stderr.decode()[-4000:], 'receiver_tested': False}
            if process.returncode == 0:
                audio, video = output / 'audio.m3u8', output / 'video.m3u8'
                after_audio, after_video = bounds(packets(audio, 'a:0')), bounds(packets(video, 'v:0'))
                row['relative_start_error'] = (after_audio[0] - after_video[0]) - (before_audio[0] - before_video[0])
                row['relative_tail_error'] = (after_audio[1] - after_video[0]) - (before_audio[1] - before_video[0])
                row['pcm_equal'] = pcm(source) == pcm(audio)
                row['coded_video_equal'] = pictures(source) == pictures(video)
                row['preservation_contract_passed'] = row['pcm_equal'] and row['coded_video_equal'] and max(
                    abs(row['relative_start_error']), abs(row['relative_tail_error'])) < 0.002
            results.append(row)
            print(number, variant, row.get('preservation_contract_passed', False),
                  row.get('relative_start_error'), flush=True)
            (args.output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()

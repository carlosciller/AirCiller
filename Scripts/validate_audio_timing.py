#!/usr/bin/env python3
"""Local timing reproduction using the current Swift command builder, no receiver."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('runner', 'engine', 'source', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--shared-clock', action='store_true', help='Local command-only experiment, not production')
    parser.add_argument('--hold-first-frame', action='store_true', help='Local negative-adjustment padding experiment')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    source = args.source.resolve()
    before_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    ffmpeg, ffprobe = (str((args.engine / name).resolve()) for name in ('ffmpeg', 'ffprobe'))

    def run(command):
        return subprocess.check_output(command, stderr=subprocess.PIPE, timeout=90)

    def packets(path, selector):
        return json.loads(run([ffprobe, '-v', 'error', '-select_streams', selector,
                               '-show_packets', '-show_data_hash', 'sha256', '-of', 'json', str(path)]))['packets']

    def bounds(rows):
        return min(float(p['pts_time']) for p in rows), max(
            float(p['pts_time']) + float(p['duration_time']) for p in rows)

    metadata = json.loads(run([ffprobe, '-v', 'error', '-show_streams', '-show_format',
                              '-of', 'json', str(source)]))
    assert [(s['index'], s['codec_name']) for s in metadata['streams']] == [(0, 'h264'), (1, 'eac3')]
    assert 59 <= float(metadata['format']['duration']) <= 61
    original = {kind: packets(source, kind + ':0') for kind in ('v', 'a')}
    original_offset = bounds(original['a'])[0] - bounds(original['v'])[0]
    rows = []
    for delay in (0, .5, -.5, 5, -5):
        directory = args.output / f'offset-{delay:+g}'
        directory.mkdir()
        command = json.loads(run([str(args.runner.resolve()), str(source), str(directory.resolve()), str(delay),
                                 *(['--shared-clock'] if args.shared_clock else []),
                                 *(['--hold-first-frame'] if args.hold_first_frame and delay < 0 else [])]))
        (directory / 'command.json').write_text(json.dumps(command, indent=2) + '\n')
        run([ffmpeg, *command])
        video, audio = packets(directory / 'video.m3u8', 'v:0'), packets(directory / 'audio.m3u8', 'a:0')
        actual_offset = bounds(audio)[0] - bounds(video)[0]
        row = {'requested_delay': delay, 'source_relative_offset': original_offset,
               'output_relative_offset': actual_offset,
               'offset_error': actual_offset - original_offset - delay,
               'video_packets_retained': len(video) == len(original['v']),
               'audio_payloads_retained': [p['data_hash'] for p in audio] == [p['data_hash'] for p in original['a']],
               'video_extent': bounds(video)[1] - bounds(video)[0],
               'audio_extent': bounds(audio)[1] - bounds(audio)[0], 'receiver_tested': False}
        for kind in ('video', 'audio'):
            row[kind + '_playlist_duration'] = sum(float(line.split(':', 1)[1].rstrip(','))
                for line in (directory / (kind + '.m3u8')).read_text().splitlines() if line.startswith('#EXTINF:'))
        row['video_first_pts'], row['audio_first_pts'] = bounds(video)[0], bounds(audio)[0]
        row['second_frame_offset_error'] = (
            bounds(audio)[0] - float(video[1]['pts_time'])
            - (bounds(original['a'])[0] - float(original['v'][1]['pts_time'])) - delay)
        rows.append(row)
        print(json.dumps(row), flush=True)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == before_hash
    (args.output / 'report.json').write_text(json.dumps(
        {'source_sha256': before_hash, 'original_unchanged': True, 'cases': rows}, indent=2) + '\n')
    if any(abs(r['second_frame_offset_error'] if args.hold_first_frame and r['requested_delay'] < 0
               else r['offset_error']) >= .002 or not r['video_packets_retained']
           or not r['audio_payloads_retained'] for r in rows):
        raise SystemExit(1)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Receiver-free audio packaging research using explicitly supplied pinned tools.

Results establish local packaging only, never AirPlay acceptance. Files are
synthetic, per-channel tones. The output directory must not exist.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import time
import wave


def run(command):
    started = time.monotonic()
    result = subprocess.run(command, capture_output=True, timeout=60)
    return result, time.monotonic() - started


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True, type=Path)
    parser.add_argument('--ffprobe', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--sample-rate', type=int, choices=(44100, 48000, 96000, 192000), default=48000)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    ffmpeg = str(args.ffmpeg.resolve())
    ffprobe = str(args.ffprobe.resolve())
    version, _ = run([ffmpeg, '-version'])
    results = {'engine': version.stdout.decode().splitlines()[0], 'receiver_tested': False,
               'cases': []}

    def probe(path):
        result, _ = run([ffprobe, '-v', 'error', '-show_streams', '-of', 'json', str(path)])
        if result.returncode:
            raise RuntimeError(result.stderr.decode())
        stream = json.loads(result.stdout)['streams'][0]
        return {key: stream.get(key) for key in
                ('codec_name', 'sample_rate', 'channels', 'channel_layout',
                 'bits_per_raw_sample', 'bits_per_sample', 'start_time', 'duration')}

    def samples(path):
        result, _ = run([ffmpeg, '-v', 'error', '-i', str(path), '-map', '0:a:0',
                         '-c:a', 'pcm_s32le', '-f', 's32le', 'pipe:1'])
        if result.returncode:
            raise RuntimeError(result.stderr.decode())
        return {'bytes': len(result.stdout), 'sha256': hashlib.sha256(result.stdout).hexdigest()}

    for codec in ('pcm_s16le', 'pcm_s24le', 'pcm_s16be', 'pcm_s24be'):
        for layout, channels in (('mono', 1), ('stereo', 2), ('5.1', 6),
                                 ('5.1(side)', 6), ('7.1', 8)):
            name = f'{codec}-{layout.replace("(", "-").replace(")", "")}'
            directory = args.output / name
            directory.mkdir()
            source = directory / 'source.mov'
            # The released engine deliberately omits lavfi. Generate deterministic
            # 24-bit integer samples without a second FFmpeg installation.
            wav = directory / 'tones.wav'
            data = bytearray()
            for sample in range(args.sample_rate * 2):
                for channel in range(channels):
                    value = round(0.2 * (2**23 - 1) * math.sin(
                        2 * math.pi * (211 + channel * 137) * sample / args.sample_rate))
                    data.extend(struct.pack('<i', value)[:3])
            with wave.open(str(wav), 'wb') as writer:
                writer.setnchannels(channels)
                writer.setsampwidth(3)
                writer.setframerate(args.sample_rate)
                writer.writeframes(data)
            generated, _ = run([ffmpeg, '-v', 'error', '-channel_layout', layout, '-i', str(wav),
                                '-c:a', codec, str(source)])
            if generated.returncode:
                raise RuntimeError(generated.stderr.decode())
            original = probe(source)
            original_samples = samples(source)
            for target in ('copy', 'flac', 'alac'):
                output = directory / f'{target}.mp4'
                result, elapsed = run([ffmpeg, '-v', 'error', '-i', str(source),
                                       '-map', '0:a:0', '-c:a', target,
                                       '-movflags', '+frag_keyframe+empty_moov', str(output)])
                case = {'source_codec': codec, 'requested_layout': layout,
                        'source': original, 'target': target, 'seconds': elapsed,
                        'exit_code': result.returncode,
                        'stderr': result.stderr.decode()[-2000:]}
                if result.returncode == 0:
                    prepared = probe(output)
                    decoded = samples(output)
                    case.update(output=prepared, output_bytes=output.stat().st_size,
                                identical_pcm=decoded == original_samples,
                                identical_layout=prepared['channel_layout'] == original['channel_layout'],
                                identical_rate=prepared['sample_rate'] == original['sample_rate'])
                results['cases'].append(case)
    (args.output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    for target in ('copy', 'flac', 'alac'):
        cases = [case for case in results['cases'] if case['target'] == target]
        safe = [case for case in cases if case.get('identical_pcm')
                and case.get('identical_layout') and case.get('identical_rate')]
        print(f'{target}: {len(safe)}/{len(cases)} preserve local PCM, layout and rate')
    print('No receiver tested. Report:', args.output / 'results.json')


if __name__ == '__main__':
    main()

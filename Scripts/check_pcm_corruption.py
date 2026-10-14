#!/usr/bin/env python3
"""Reject synthetic Blu-ray LPCM headers advertising unsupported precision.

Works on a copy inside a new directory. Never modifies the input or uses devices.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'runner', 'engine', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--movie', type=Path, required=True,
                        help='Synthetic PCM MOV used for a truncated-container rejection')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    original = args.source.read_bytes()
    if len(original) % 192:
        raise ValueError('Expected a synthetic M2TS fixture')
    original_digest = hashlib.sha256(original).hexdigest()
    candidates = []
    for base in range(0, len(original), 192):
        packet = original[base + 4:base + 192]
        if packet[0] != 0x47 or not packet[1] & 0x40:
            continue
        pid = ((packet[1] & 31) << 8) | packet[2]
        if pid != 0x1100:
            continue
        control = (packet[3] >> 4) & 3
        payload = 4 + (1 + packet[4] if control == 3 else 0)
        if control not in (1, 3) or packet[payload:payload + 3] != b'\x00\x00\x01':
            continue
        pcm = payload + 9 + packet[payload + 8]
        if pcm + 4 > len(packet) or packet[pcm + 3] >> 6 not in (1, 3):
            raise ValueError('Unexpected synthetic PCM framing')
        candidates.append(base + 4 + pcm + 3)
    if len(candidates) < 20:
        raise ValueError('Insufficient LPCM frames')
    records = []
    for name, indices in [('unsupported-20bit', candidates),
                          ('midstream-corruption', candidates[len(candidates) // 2:])]:
        changed = bytearray(original)
        for offset in indices:
            changed[offset] = (changed[offset] & 63) | 0x80
        source = args.output / (name + '.m2ts')
        source.write_bytes(changed)
        output = args.output / name
        result = subprocess.run([str(args.runner.resolve()), str(source.resolve()),
                                 str(output.resolve()), str(args.engine.resolve()), 'losslessFLAC'],
                                capture_output=True, timeout=90)
        error = result.stderr.decode()
        expected_code = 2 if name == 'unsupported-20bit' else 3
        expected_detail = ('Esta pista no admite conversión PCM a FLAC sin pérdida.'
                           if expected_code == 2 else 'unsupported sample depth')
        passed = result.returncode == expected_code and expected_detail in error and not (
            output / 'master.m3u8').exists()
        records.append({'case': name, 'modified_headers': len(indices), 'exit_code': result.returncode,
                        'stderr': error[-4000:], 'passed': passed})
        print(name, 'PASS' if passed else 'FAIL')
    movie = args.movie.read_bytes()
    movie_digest = hashlib.sha256(movie).hexdigest()
    if len(movie) < 4096:
        raise ValueError('Synthetic MOV is too short for this truncation case')
    truncated = args.output / 'truncated-container.mov'
    truncated.write_bytes(movie[:len(movie) // 2])
    output = args.output / 'truncated-container'
    result = subprocess.run([str(args.runner.resolve()), str(truncated.resolve()),
                             str(output.resolve()), str(args.engine.resolve()), 'losslessFLAC'],
                            capture_output=True, timeout=90)
    error = result.stderr.decode()
    passed = result.returncode == 2 and 'Probe rejection:' in error and not output.exists()
    records.append({'case': 'truncated-container', 'exit_code': result.returncode,
                    'stderr': error[-4000:], 'passed': passed})
    print('truncated-container', 'PASS' if passed else 'FAIL')
    assert hashlib.sha256(args.movie.read_bytes()).hexdigest() == movie_digest
    assert hashlib.sha256(args.source.read_bytes()).hexdigest() == original_digest
    (args.output / 'results.json').write_text(json.dumps(
        {'receiver_tested': False, 'original_unchanged': True, 'cases': records}, indent=2) + '\n')
    if not all(record['passed'] for record in records):
        raise SystemExit(1)


if __name__ == '__main__':
    main()

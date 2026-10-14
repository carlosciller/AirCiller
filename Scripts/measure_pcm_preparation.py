#!/usr/bin/env python3
"""Measure two existing output choices and verify a real PCM cache round trip.

Short synthetic movie only. No receiver, credentials or system cache reset.
"""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import statistics
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('runner', 'engine', 'source', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    records = []

    def run(mode, name, cache=False):
        directory = args.output / name
        command = [str(args.runner.resolve()), str(args.source.resolve()), str(directory.resolve()),
                   str(args.engine.resolve()), mode]
        if cache:
            command.append(str((args.output / 'cache').resolve()))
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        started = time.monotonic()
        result = subprocess.run(command, capture_output=True, timeout=90)
        elapsed = time.monotonic() - started
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        if result.returncode:
            raise RuntimeError(result.stderr.decode())
        report = json.loads(result.stdout.decode().splitlines()[-1])
        record = {'mode': mode, 'name': name, 'wall_seconds': elapsed,
                  'cpu_seconds': after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime,
                  'prepared_bytes': sum(path.stat().st_size for path in directory.iterdir() if path.is_file()),
                  'report': report}
        records.append(record)
        return directory, report

    for mode in ('compatible', 'losslessFLAC'):
        for repetition in range(3):
            run(mode, f'{mode}-{repetition}')
    cold, cold_report = run('losslessFLAC', 'cache-cold', cache=True)
    warm, warm_report = run('losslessFLAC', 'cache-warm', cache=True)
    assert not cold_report['used_cache'] and warm_report['used_cache']
    def media(directory):
        return {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                for path in directory.iterdir() if path.suffix in ('.m4s', '.mp4')}
    assert media(cold) and media(cold) == media(warm)
    # A different output choice must not reuse the lossless base.
    _, converted_report = run('compatible', 'cache-different-mode', cache=True)
    assert not converted_report['used_cache']
    report = {'receiver_tested': False, 'cache_identity_passed': True, 'records': records,
              'medians': {mode: {key: statistics.median(record[key] for record in records
                           if record['mode'] == mode and record['name'].startswith(mode + '-'))
                           for key in ('wall_seconds', 'cpu_seconds', 'prepared_bytes')}
                          for mode in ('compatible', 'losslessFLAC')}}
    (args.output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['medians'], indent=2))
    print('Immutable cache reuse and output-mode isolation: PASS')


if __name__ == '__main__':
    main()

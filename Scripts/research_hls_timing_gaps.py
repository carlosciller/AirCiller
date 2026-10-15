#!/usr/bin/env python3
"""Build a copied synthetic HLS gap experiment and run a muted local player."""
import argparse
from datetime import datetime, timedelta, timezone
import functools
import http.server
import json
import math
from pathlib import Path
import shutil
import subprocess
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('package', 'output', 'engine', 'player'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--gaps', action='store_true')
    args = parser.parse_args()
    shutil.copytree(args.package, args.output)
    ffprobe = str((args.engine / 'ffprobe').resolve())
    renditions = {}
    for kind in ('video', 'audio'):
        path = args.output / (kind + '.m3u8')
        files = [line for line in path.read_text().splitlines() if line and not line.startswith('#')]
        segments = []
        for filename in files:
            joined = args.output / (kind + '-probe.mp4')
            joined.write_bytes((args.output / (kind + '-init.mp4')).read_bytes()
                               + (args.output / filename).read_bytes())
            packets = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-show_packets',
                '-of', 'json', str(joined)], stderr=subprocess.PIPE, timeout=30))['packets']
            first = min(float(p['pts_time']) for p in packets)
            end = max(float(p['pts_time']) + float(p['duration_time']) for p in packets)
            segments.append({'file': filename, 'start': first, 'end': end})
        renditions[kind] = segments
    start = min(rows[0]['start'] for rows in renditions.values())
    end = max(rows[-1]['end'] for rows in renditions.values())
    epoch = datetime(2000, 1, 1, tzinfo=timezone.utc)
    for kind, segments in renditions.items():
        entries = []
        if args.gaps and segments[0]['start'] - start > .001:
            entries.append({'file': kind + '-leading-gap.m4s', 'start': start,
                            'end': segments[0]['start'], 'gap': True})
        entries.extend(segments)
        if args.gaps and end - segments[-1]['end'] > .001:
            entries.append({'file': kind + '-trailing-gap.m4s', 'start': segments[-1]['end'],
                            'end': end, 'gap': True})
        target = math.ceil(max(row['end'] - row['start'] for row in entries))
        lines = ['#EXTM3U', '#EXT-X-VERSION:8', f'#EXT-X-TARGETDURATION:{target}',
                 '#EXT-X-MEDIA-SEQUENCE:0', '#EXT-X-PLAYLIST-TYPE:VOD',
                 f'#EXT-X-MAP:URI="{kind}-init.mp4"']
        for row in entries:
            date = epoch + timedelta(seconds=row['start'] - start)
            lines.append('#EXT-X-PROGRAM-DATE-TIME:' + date.isoformat(timespec='milliseconds'))
            if row.get('gap'): lines.append('#EXT-X-GAP')
            lines.extend([f"#EXTINF:{row['end'] - row['start']:.6f},", row['file']])
        lines.append('#EXT-X-ENDLIST')
        (args.output / (kind + '.m3u8')).write_text('\n'.join(lines) + '\n')
    (args.output / 'master.m3u8').write_text(
        '#EXTM3U\n#EXT-X-VERSION:8\n#EXT-X-START:TIME-OFFSET=0,PRECISE=YES\n'
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Original",DEFAULT=YES,AUTOSELECT=YES,URI="audio.m3u8"\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=4000000,CODECS="avc1.64001f,ec-3",AUDIO="audio"\nvideo.m3u8\n')
    requests = []
    request_lock = threading.Lock()

    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format, *values):
            with request_lock:
                if len(requests) < 200:
                    requests.append(self.path)

    handler = functools.partial(Handler, directory=str(args.output.resolve()))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = subprocess.run([str(args.player.resolve()),
            f'http://127.0.0.1:{server.server_port}/master.m3u8'], capture_output=True, timeout=40)
        report = {'gaps': args.gaps, 'renditions': renditions, 'start': start, 'end': end,
                  'exit_code': result.returncode, 'stdout': result.stdout.decode(),
                  'stderr': result.stderr.decode(), 'requests': list(requests), 'receiver_tested': False}
        (args.output / 'local-player.json').write_text(json.dumps(report, indent=2) + '\n')
        print(result.stdout.decode(), result.stderr.decode(), flush=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


if __name__ == '__main__':
    main()

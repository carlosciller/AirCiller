import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from compare import Snapshot, pcm_difference


class Response(io.BytesIO):
    def __init__(self, url, data):
        super().__init__(data)
        self.url = url


class SnapshotTests(unittest.TestCase):
    def test_pcm_difference_preserves_strict_gate(self):
        self.assertTrue(pcm_difference([0, 1, 2], [0, 1, 2])["identical"])
        changed = pcm_difference([0, 1, 2], [1, 1, 2])
        self.assertFalse(changed["identical"])
        self.assertEqual(changed["firstDifference"], 0)
        self.assertEqual(changed["lastDifference"], 0)
        self.assertFalse(pcm_difference([0, 1, 2], [0, 1])["identical"])

    def test_refuses_nonlocal_origin(self):
        for url in ("https://example.com/movie", "file:///tmp/movie", "http://192.0.2.1/movie"):
            with self.assertRaises(ValueError):
                Snapshot(url, Path("unused"))

    def snapshot(self, root, resources):
        class Opener:
            def open(self, url, timeout):
                return Response(url, resources[url])
        return patch("urllib.request.build_opener", return_value=Opener())

    def test_complete_vod_and_relative_subtitles(self):
        base = "http://127.0.0.1:1234/token/"
        resources = {
            base + "master.m3u8": b'#EXTM3U\n#EXT-X-MEDIA:TYPE=SUBTITLES,URI="sub.m3u8"\nvideo.m3u8\n',
            base + "video.m3u8": b'#EXTM3U\n#EXTINF:4,\nseg.mp4\n#EXT-X-ENDLIST\n',
            base + "sub.m3u8": b'#EXTM3U\n#EXTINF:4,\nsub.vtt\n#EXT-X-ENDLIST\n',
            base + "seg.mp4": b"synthetic",
            base + "sub.vtt": b"WEBVTT\n\n00:00.000 --> 00:04.000\ncaption\n",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.snapshot(root, resources):
                snapshot = Snapshot(base + "master.m3u8", root)
                entry = snapshot.fetch(base + "master.m3u8")
                self.assertEqual(len(snapshot.saved), 5)
                self.assertNotIn("http", (root / entry).read_text())
                self.assertEqual(len(list(root.glob("*.vtt"))), 1)

    def test_refuses_unfinished_vod(self):
        url = "http://127.0.0.1:1234/video.m3u8"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.snapshot(root, {url: b"#EXTM3U\n#EXTINF:4,\nseg.mp4\n"}):
                with self.assertRaisesRegex(ValueError, "complete VOD"):
                    Snapshot(url, root).fetch(url)

    def test_refuses_cross_origin_and_resource_budget(self):
        snapshot = Snapshot("http://127.0.0.1:1234/master.m3u8", Path("unused"))
        with self.assertRaisesRegex(ValueError, "Cross-origin"):
            snapshot.fetch("http://127.0.0.1:4321/other.m3u8")
        snapshot.saved = {str(i): "test" for i in range(256)}
        with self.assertRaisesRegex(ValueError, "Resource budget"):
            snapshot.fetch("http://127.0.0.1:1234/master.m3u8")


if __name__ == "__main__":
    unittest.main()

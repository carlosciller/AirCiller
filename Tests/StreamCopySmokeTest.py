"""The copy verifier must detect altered coded pictures and Dolby Vision payloads."""
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from verify_stream_copy import coded_picture_digest


class StreamCopyTests(unittest.TestCase):
    def test_h264_framing_and_parameter_repetition(self):
        picture = b"\x65\x13\x80"
        a = b"\x00\x00\x01" + picture
        b = b"\x00\x00\x00\x01\x67\x44\x80\x00\x00\x01" + picture + b"\x00\x00"
        self.assertEqual(coded_picture_digest(a, "h264"), coded_picture_digest(b, "h264"))
        self.assertNotEqual(coded_picture_digest(a, "h264"), coded_picture_digest(a + a, "h264"))
        self.assertNotEqual(coded_picture_digest(a, "h264"), coded_picture_digest(a[:-1] + b"\x90", "h264"))

    def test_hevc_rpu_cannot_be_dropped(self):
        picture = b"\x00\x00\x01\x26\x01\x80"
        rpu = b"\x00\x00\x01\x7c\x01\x80"
        self.assertNotEqual(coded_picture_digest(picture, "hevc"), coded_picture_digest(picture + rpu, "hevc"))
        with self.assertRaises(ValueError):
            coded_picture_digest(b"\x00\x00\x01\x67\x80", "h264")


if __name__ == "__main__":
    unittest.main()

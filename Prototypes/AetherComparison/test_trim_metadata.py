import struct
import unittest
from trim_metadata import correct_audio_edit, final_audio_duration_field


def box(kind, payload):
    return struct.pack(">I4s", len(payload) + 8, kind) + payload


def fixture(version=0, handler=b"soun", scale=48000):
    mdhd = box(b"mdhd", bytes(12) + struct.pack(">I", scale) + bytes(8))
    hdlr = box(b"hdlr", bytes(8) + handler + bytes(12))
    entry = struct.pack(">Qqhh", 0, 1008, 1, 0) if version else struct.pack(">Iihh", 0, 1008, 1, 0)
    edit = box(b"edts", box(b"elst", bytes([version, 0, 0, 0]) + struct.pack(">I", 1) + entry))
    track = box(b"trak", box(b"mdia", mdhd + hdlr) + edit)
    return box(b"moov", box(b"mvhd", bytes(12) + struct.pack(">I", 1000) + bytes(8)) + track) + box(b"mdat", b"unchanged-packets")


class TrimTests(unittest.TestCase):
    def test_final_explicit_audio_duration(self):
        tfhd = box(b"tfhd", bytes(4) + struct.pack(">I", 2))
        trun = box(b"trun", struct.pack(">IIIII", 0x100, 3, 1536, 1536, 1392))
        data = box(b"moof", box(b"traf", tfhd + trun)) + box(b"mdat", b"original")
        pos, duration = final_audio_duration_field(data, 2)
        self.assertEqual(duration, 1392)
        patched = bytearray(data)
        struct.pack_into(">I", patched, pos, 1536)
        self.assertEqual(patched[:pos], data[:pos])
        self.assertEqual(patched[pos + 4:], data[pos + 4:])
        self.assertIsNone(final_audio_duration_field(data, 1))

    def test_exact_edit_both_versions(self):
        for version in (0, 1):
            original = fixture(version)
            result, changes = correct_audio_edit(original, 1024, 48000, 1296384)
            self.assertEqual(len(original), len(result))
            self.assertTrue(result.endswith(box(b"mdat", b"unchanged-packets")))
            self.assertEqual(changes[0]["newMediaTime"], 1024)
            self.assertEqual(changes[0]["presentationDuration"], 27008)
            self.assertEqual(correct_audio_edit(result, 1024, 48000, 1296384)[0], result)

    def test_video_untouched(self):
        original = fixture(handler=b"vide")
        self.assertEqual(correct_audio_edit(original, 1024, 48000), (original, []))

    def test_refuses_unrepresentable_and_unrelated_edits(self):
        for skip, rate, duration in [(1024, 44100, None), (2048, 48000, None), (1024, 48000, 1)]:
            with self.assertRaises(ValueError):
                correct_audio_edit(fixture(), skip, rate, duration)

    def test_malformed_box(self):
        with self.assertRaises(ValueError):
            correct_audio_edit(b"broken", 1024, 48000)


if __name__ == "__main__":
    unittest.main()

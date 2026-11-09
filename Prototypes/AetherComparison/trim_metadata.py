"""Experimental finalized-VOD edit-list precision. Never edits encoded samples."""
import struct


def boxes(data, start=0, end=None):
    end = len(data) if end is None else end
    while start < end:
        if start + 8 > end:
            raise ValueError("Truncated box")
        size, kind = struct.unpack_from(">I4s", data, start)
        if size < 8 or start + size > end:
            raise ValueError("Unsupported or invalid box size")
        yield start, size, kind
        start += size


def correct_audio_edit(data, skip_samples, sample_rate, presented_samples=None):
    """Correct only the audio media-time field; preserve box sizes and all media."""
    result = bytearray(data)
    changes = []
    for p, n, kind in boxes(data):
        if kind != b"moov":
            continue
        movie = next(x[0] for x in boxes(data, p + 8, p + n) if x[2] == b"mvhd")
        movie_scale = struct.unpack_from(">I", data, movie + (28 if data[movie + 8] else 20))[0]
        for t, tn, tk in boxes(data, p + 8, p + n):
            if tk != b"trak":
                continue
            children = list(boxes(data, t + 8, t + tn))
            media = next((x for x in children if x[2] == b"mdia"), None)
            if media is None:
                continue
            m, mn, _ = media
            fields = list(boxes(data, m + 8, m + mn))
            h = next(x[0] for x in fields if x[2] == b"hdlr")
            if data[h + 16:h + 20] != b"soun":
                continue
            md = next(x[0] for x in fields if x[2] == b"mdhd")
            scale = struct.unpack_from(">I", data, md + (28 if data[md + 8] else 20))[0]
            if scale != sample_rate:
                raise ValueError("Audio timescale must equal sample rate")
            ed = next((x for x in children if x[2] == b"edts"), None)
            if ed is None:
                raise ValueError("Audio edit list absent")
            e, en, _ = ed
            el = next(x[0] for x in boxes(data, e + 8, e + en) if x[2] == b"elst")
            version = data[el + 8]
            if version not in (0, 1) or struct.unpack_from(">I", data, el + 12)[0] != 1:
                raise ValueError("Only single-entry edit lists are supported")
            pos = el + (24 if version else 20)
            fmt = ">q" if version else ">i"
            old = struct.unpack_from(fmt, data, pos)[0]
            if old < 0 or abs(old - skip_samples) > sample_rate // 1000:
                raise ValueError("Edit is not a rounded codec pre-roll")
            struct.pack_into(fmt, result, pos, skip_samples)
            change = {"oldMediaTime": old, "newMediaTime": skip_samples, "timescale": scale}
            if presented_samples is not None:
                duration, remainder = divmod(presented_samples * movie_scale, sample_rate)
                if remainder:
                    raise ValueError("Movie timescale cannot represent exact presentation duration")
                struct.pack_into(">Q" if version else ">I", result, el + 16, duration)
                change["presentationDuration"] = duration
                change["movieTimescale"] = movie_scale
            changes.append(change)
    return bytes(result), changes


def audio_track_id(data):
    for p, n, kind in boxes(data):
        if kind != b"moov":
            continue
        for t, tn, tk in boxes(data, p + 8, p + n):
            if tk != b"trak":
                continue
            children = list(boxes(data, t + 8, t + tn))
            m, mn, _ = next(x for x in children if x[2] == b"mdia")
            h = next(x[0] for x in boxes(data, m + 8, m + mn) if x[2] == b"hdlr")
            if data[h + 16:h + 20] == b"soun":
                th = next(x[0] for x in children if x[2] == b"tkhd")
                return struct.unpack_from(">I", data, th + (28 if data[th + 8] else 20))[0]
    raise ValueError("Audio track missing")


def final_audio_duration_field(data, track_id):
    """Return final explicit audio duration offset and value, without modifying it."""
    found = None
    for p, n, kind in boxes(data):
        if kind != b"moof":
            continue
        for t, tn, tk in boxes(data, p + 8, p + n):
            if tk != b"traf":
                continue
            children = list(boxes(data, t + 8, t + tn))
            h = next(x[0] for x in children if x[2] == b"tfhd")
            if struct.unpack_from(">I", data, h + 12)[0] != track_id:
                continue
            for r, rn, rk in children:
                if rk != b"trun":
                    continue
                flags = int.from_bytes(data[r + 9:r + 12], "big")
                count = struct.unpack_from(">I", data, r + 12)[0]
                if not count:
                    continue
                if not flags & 0x100:
                    raise ValueError("Explicit sample durations required for bounded tail repair")
                start = r + 16 + (4 if flags & 1 else 0) + (4 if flags & 4 else 0)
                stride = 4 * sum(bool(flags & bit) for bit in (0x100, 0x200, 0x400, 0x800))
                pos = start + (count - 1) * stride
                if pos + stride > r + rn:
                    raise ValueError("Truncated sample table")
                found = (pos, struct.unpack_from(">I", data, pos)[0])
    return found

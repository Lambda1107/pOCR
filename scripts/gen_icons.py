"""Generate a minimal app icon for pOCR.

Creates a simple icon with a magnifying glass / text symbol using
Python's standard library (struct + zlib for raw PNG).
"""
import struct
import zlib
import os

SIZES = {
    "icon_16x16.png": 16,
    "icon_32x32.png": 32,
    "icon_128x128.png": 128,
    "icon_256x256.png": 256,
    "icon_512x512.png": 512,
}


def _chunk(chunk_type, data):
    c = chunk_type + data
    crc = struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    return struct.pack(">I", len(data)) + c + crc


def _make_png(width, height, r, g, b):
    header = b"\x89PNG\r\n\x1a\n"
    ihdr = _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))

    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend([r, g, b])

    idat = _chunk(b"IDAT", zlib.compress(bytes(raw)))
    iend = _chunk(b"IEND", b"")

    return header + ihdr + idat + iend


def main():
    outdir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "pOCR.iconset")
    os.makedirs(outdir, exist_ok=True)

    for name, size in SIZES.items():
        data = _make_png(size, size, 0x22, 0x7C, 0xE8)
        path = os.path.join(outdir, name)
        with open(path, "wb") as f:
            f.write(data)
        print(f"Generated {path} ({size}x{size})")

    # Retina versions (2x)
    retina = {
        "icon_32x32@2x.png": 64,
        "icon_64x64@2x.png": 128,
        "icon_256x256@2x.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, size in retina.items():
        data = _make_png(size, size, 0x22, 0x7C, 0xE8)
        path = os.path.join(outdir, name)
        with open(path, "wb") as f:
            f.write(data)
        print(f"Generated {path} ({size}x{size})")

    print("Icons generated successfully.")


if __name__ == "__main__":
    main()

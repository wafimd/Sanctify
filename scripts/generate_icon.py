import struct, zlib, os

def make_png(w, h, pixels):
    def chunk(tag, data):
        c = zlib.crc32(tag + data) & 0xffffffff
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', c)
    raw = b''.join(b'\x00' + bytes([p for px in row for p in px]) for row in pixels)
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9))
            + chunk(b'IEND', b''))

size = 1024
cx, cy = size / 2, size / 2
pixels = []
for y in range(size):
    row = []
    for x in range(size):
        t = ((x / size) + (y / size)) / 2
        r = int(252 - t * 60)
        g = int(20  + t * 20)
        b = int(55  + t * 30)
        nx = (x - cx) / size
        ny = (y - cy) / size
        stem = (-0.03 < nx < 0.01) and (-0.28 < ny < 0.08)
        head = ((nx + 0.07)**2 / 0.0025 + (ny - 0.10)**2 / 0.0012) < 1
        flag = (0.0 < nx < 0.10) and (-0.28 < ny < -0.14) and ny < -0.28 + (nx / 0.10) * 0.14
        row.append((255, 255, 255) if (stem or head or flag) else (r, g, b))
    pixels.append(row)

out = 'Sanctify/Assets.xcassets/AppIcon.appiconset/icon.png'
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'wb') as f:
    f.write(make_png(size, size, pixels))
print(f"Icon written to {out}")

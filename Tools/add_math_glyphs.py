import pathlib
import struct

atlas_path = pathlib.Path(__file__).resolve().parents[1] / 'Sources/ChromaFont/Resources/FontAtlas.atlas'
data = atlas_path.read_bytes()
magic, version, width, height, count = struct.unpack_from('<5I', data)
scalars = list(struct.unpack_from(f'<{count}I', data, 20))
pixels = bytearray(data[20 + count * 4:20 + count * 4 + width * height])


def glyph(character):
    index = scalars.index(ord(character))
    x, y = index % 32 * 66 + 3, index // 32 * 90 + 3
    return [list(pixels[(y + row) * width + x:(y + row) * width + x + 36]) for row in range(84)]


def cropped(image):
    points = [(x, y) for y, row in enumerate(image) for x, ink in enumerate(row) if ink]
    left, right = min(x for x, y in points), max(x for x, y in points) + 1
    top, bottom = min(y for x, y in points), max(y for x, y in points) + 1
    return [row[left:right] for row in image[top:bottom]]


def stamp(canvas, character, left, top, w, h):
    source = cropped(glyph(character))
    # Area averaging keeps the smaller fraction digits antialiased.
    for y in range(h):
        for x in range(w):
            values = [source[sy][sx]
                      for sy in range(y * len(source) // h, max(y * len(source) // h + 1, (y + 1) * len(source) // h))
                      for sx in range(x * len(source[0]) // w, max(x * len(source[0]) // w + 1, (x + 1) * len(source[0]) // w))]
            canvas[top + y][left + x] = max(canvas[top + y][left + x], (sum(values) + len(values) // 2) // len(values))


for character, numerator, denominator in [('¼', '1', '4'), ('½', '1', '2'), ('¾', '3', '4'), ('≤', '', ''), ('≥', '', '')]:
    canvas = [[0] * 36 for _ in range(84)]
    if numerator:
        stamp(canvas, '/', 3, 23, 30, 42)
        stamp(canvas, numerator, 0, 21, 14, 23)
        stamp(canvas, denominator, 22, 45, 14, 23)
    else:
        stamp(canvas, '<' if character == '≤' else '>', 3, 29, 30, 27)
        stamp(canvas, '-', 3, 62, 30, 4)
    if ord(character) not in scalars:
        scalars.append(ord(character))
    index = scalars.index(ord(character))
    assert index < height // 90 * 32
    x, y = index % 32 * 66 + 3, index // 32 * 90 + 3
    for row in range(84):
        pixels[(y + row) * width + x:(y + row) * width + x + 36] = bytes(canvas[row])

output = bytearray(struct.pack('<5I', magic, version, width, height, len(scalars)))
output.extend(struct.pack(f'<{len(scalars)}I', *scalars))
while True:
    output.extend(pixels)
    if width == height == 1:
        break
    w, h = max(1, width // 2), max(1, height // 2)
    reduced = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            values = [pixels[sy * width + sx]
                      for sy in range(y * 2, min(y * 2 + 2, height))
                      for sx in range(x * 2, min(x * 2 + 2, width))]
            reduced[y * w + x] = (sum(values) + len(values) // 2) // len(values)
    pixels, width, height = reduced, w, h
atlas_path.write_bytes(output)

hash_value = 14_695_981_039_346_656_037
for byte in output[20:]:
    hash_value = ((hash_value ^ byte) * 1_099_511_628_211) & ((1 << 64) - 1)
print(f'{len(scalars)} glyphs; snapshot hash {hash_value}')

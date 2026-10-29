#!/usr/bin/env python3
"""生成 App 图标（1024x1024 PNG，纯标准库手写 PNG 编码器）。

画一个像素风草方块：黑底 + 草方块 + 一点高光。
用法： python3 Tools/make_icon.py <输出目录>
"""
import os
import struct
import sys
import zlib

SIZE = 1024


def blend(dst, src, alpha):
    return tuple(int(round(d * (1 - alpha) + s * alpha)) for d, s in zip(dst, src))


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "JavaMC/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(out_dir, exist_ok=True)

    pixels = [[(0, 0, 0) for _ in range(SIZE)] for _ in range(SIZE)]

    # 背景：深色渐变
    for y in range(SIZE):
        t = y / (SIZE - 1)
        bg = blend((16, 20, 28), (40, 52, 74), t)
        row = pixels[y]
        for x in range(SIZE):
            row[x] = bg

    # 方块区域
    block = int(SIZE * 0.62)
    origin = (SIZE - block) // 2
    cell = block // 16  # 16x16 像素网格

    grass_top = (122, 178, 74)
    grass_side = (96, 148, 60)
    dirt = (134, 96, 67)
    dirt_dark = (110, 78, 54)

    for gy in range(16):
        for gx in range(16):
            if gy < 5:
                color = grass_top if (gx + gy) % 3 else grass_side
            else:
                color = dirt if (gx * 7 + gy * 3) % 4 else dirt_dark
            # 顶部亮一点，底部暗一点
            shade = 1.0 - (gy / 15.0) * 0.22
            color = tuple(min(255, int(c * shade)) for c in color)
            x0 = origin + gx * cell
            y0 = origin + gy * cell
            # 块与块之间留一像素描边，显得更有像素味
            for y in range(y0 + 1, min(y0 + cell - 1, SIZE)):
                row = pixels[y]
                for x in range(x0 + 1, min(x0 + cell - 1, SIZE)):
                    row[x] = color

    # 左上角高光
    hl = int(block * 0.5)
    for y in range(origin, origin + hl):
        for x in range(origin, origin + hl):
            if (x - origin) + (y - origin) < hl:
                pixels[y][x] = blend(pixels[y][x], (255, 255, 255), 0.10)

    # 编码 PNG
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # filter type 0
        row = pixels[y]
        for x in range(SIZE):
            r, g, b = row[x]
            raw.append(r)
            raw.append(g)
            raw.append(b)

    def chunk(tag, data):
        out = struct.pack(">I", len(data))
        out += tag + data
        out += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return out

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", header)
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    path = os.path.join(out_dir, "icon-1024.png")
    with open(path, "wb") as handle:
        handle.write(png)
    print("wrote", path, len(png), "bytes")

    contents = """{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
    with open(os.path.join(out_dir, "Contents.json"), "w") as handle:
        handle.write(contents)
    print("wrote Contents.json")


if __name__ == "__main__":
    main()

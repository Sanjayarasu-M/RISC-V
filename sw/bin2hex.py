#!/usr/bin/env python3
# Converts a raw little-endian binary image into the plain 32-bit-word hex
# format $readmemh expects here (one 8-hex-digit word per line, no @addr
# markers) -- matching program.hex's existing format.
import sys

def main():
    in_path, out_path = sys.argv[1], sys.argv[2]
    with open(in_path, 'rb') as f:
        data = f.read()

    # pad to a multiple of 4 bytes
    if len(data) % 4:
        data += b'\x00' * (4 - len(data) % 4)

    words = []
    for i in range(0, len(data), 4):
        b0, b1, b2, b3 = data[i], data[i+1], data[i+2], data[i+3]
        word = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        words.append(word)

    with open(out_path, 'w', newline='\n') as f:
        for w in words:
            f.write(f"{w:08x}\n")

    print(f"{in_path} ({len(data)} bytes) -> {out_path} ({len(words)} words)")

if __name__ == '__main__':
    main()

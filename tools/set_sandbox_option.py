"""Set one sandbox option in a save's map_sand.bin (adds it if the save doesn't have it yet).

Format (zombie.SandboxOptions.save, 42.21): b"SAND", int32 249, int32 version, int32 count,
then count pairs of (name, value), then the preset name. Strings are a big-endian uint16
byte length followed by UTF-8. Run only while the game is closed; it writes a .bak first.

    python set_sandbox_option.py <map_sand.bin> <Option.Name> <value> [--dry-run]
"""
import shutil
import struct
import sys
from datetime import datetime


def read_str(data, pos):
    (n,) = struct.unpack_from(">H", data, pos)
    pos += 2
    return data[pos:pos + n].decode("utf-8"), pos + n


def write_str(s):
    b = s.encode("utf-8")
    return struct.pack(">H", len(b)) + b


def parse(data):
    if data[:4] != b"SAND":
        raise ValueError("not a map_sand.bin file")
    magic2, version, count = struct.unpack_from(">iii", data, 4)
    pos = 16
    pairs = []
    for _ in range(count):
        name, pos = read_str(data, pos)
        value, pos = read_str(data, pos)
        pairs.append([name, value])
    preset, pos = read_str(data, pos)
    if pos != len(data):
        raise ValueError(f"{len(data) - pos} unexpected trailing bytes")
    return magic2, version, pairs, preset


def build(magic2, version, pairs, preset):
    out = bytearray(b"SAND")
    out += struct.pack(">iii", magic2, version, len(pairs))
    for name, value in pairs:
        out += write_str(name) + write_str(value)
    out += write_str(preset)
    return bytes(out)


def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry_run = "--dry-run" in sys.argv
    path, option, value = args
    with open(path, "rb") as f:
        data = f.read()
    magic2, version, pairs, preset = parse(data)
    if build(magic2, version, pairs, preset) != data:
        raise ValueError("round trip mismatch; format changed, not touching the file")

    old = None
    for pair in pairs:
        if pair[0] == option:
            old, pair[1] = pair[1], value
            break
    else:
        pairs.append([option, value])
    new_data = build(magic2, version, pairs, preset)
    if parse(new_data)[2] != pairs:
        raise ValueError("rebuilt file doesn't parse back; not writing")

    print(f"{len(pairs)} options, preset {preset!r}; {option}: {old!r} -> {value!r}")
    if dry_run:
        return
    backup = f"{path}.{datetime.now():%Y%m%d-%H%M%S}.bak"
    shutil.copy2(path, backup)
    with open(path, "wb") as f:
        f.write(new_data)
    print(f"written; backup at {backup}")


if __name__ == "__main__":
    main()

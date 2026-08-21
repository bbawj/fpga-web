import argparse
from pathlib import Path


def _align_32(size):
    if size % 4 == 0:
        return size
    else:
        return size + 4 - (size % 4)


def calc_tcp_checksum(b: bytearray):
    if len(b) % 2 != 0:
        b.append(0x00)
    temp = 0
    for i in range(0, len(b), 2):
        temp += int.from_bytes(b[i:i+2], 'big')
        if temp > 0xFFFF:
            temp &= 0xFFFF
            temp += 1

    return temp


NOTFOUND_HTTP = "HTTP/1.0 404 Not Found\r\nContent-Length: "
BASE_HTTP = "HTTP/1.0 200 OK\r\nContent-Length: "
PROJ_FOLDER = Path(__file__).parent.parent
DEFAULT_TARGET = PROJ_FOLDER / "docs/pages"


def read_files(start_addr=0x00000000, num_entries=512, folder=DEFAULT_TARGET):
    count = 0
    next_start_addr = (start_addr or 0x00000000) + 1024
    num_entries = max(num_entries or 0, 512)
    pages = sorted(folder.resolve().glob('*.html'))
    pages.insert(0, (PROJ_FOLDER / "tools/404.html").resolve())
    addrs = [0] * num_entries
    lens = [0] * num_entries
    with open("content.mem", "w", newline="") as fc:
        with open("content_hex.mem", "w", newline="") as fh:
            total_length = 0

            for idx, p in enumerate(pages):
                print(f"Parsing {p}")
                assert count < num_entries

                data = p.read_text()

                res_code = NOTFOUND_HTTP if "404.html" == p.name else BASE_HTTP
                entire_data = f"{res_code}{len(data)}\r\n\r\n{data}"
                length = len(entire_data)
                padded_length_32 = int(_align_32(length))
                entire_data += " " * (padded_length_32 - length)
                data_bytes = bytearray(entire_data, "ascii")
                fc.write(entire_data)
                for i in range(0, len(data_bytes), 4):
                    word = int.from_bytes(data_bytes[i:i+4], 'little')
                    fh.write(f'{word:08X}\n')

                addrs[idx] = next_start_addr
                lens[idx] = padded_length_32

                count += 1
                next_start_addr += int(padded_length_32/4)
                total_length += int(padded_length_32 / 4)

    # put metadata at start of content file
    with open("content_hex.mem", "r+", newline="") as fh:
        data = fh.read()
        fh.seek(0)
        for i in range(512):
            if i >= num_entries:
                fh.write(f"{0:08x}\n")
            else:
                fh.write(f"{addrs[i]:08x}\n")

        for i in range(512):
            if i >= num_entries:
                fh.write(f"{0:08x}\n")
            else:
                fh.write(f"{lens[i]:08x}\n")

        fh.write(data)
        # padding to 512 rows
        for i in range(total_length + 1, num_entries):
            fh.write(f'{0:08X}\n')

    with open("content.mem", "wb") as fc:
        for val in addrs:
            fc.write(int.to_bytes(val, 32, "little", signed=False))
        for val in lens:
            fc.write(int.to_bytes(val, 32, "little", signed=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-start", help="Start address of Flash to write", type=int)
    parser.add_argument(
        "-entries", help="Number of HTTP entries", type=int)
    parser.add_argument(
        "-folder", help="Target folder containing HTTP files", type=str, default=DEFAULT_TARGET)
    args = parser.parse_args()
    read_files(args.start, args.entries, Path(args.folder))

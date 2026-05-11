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
    print(b)
    temp = 0
    for i in range(0, len(b), 2):
        temp += int.from_bytes(b[i:i+2], 'big')
        if temp > 0xFFFF:
            temp &= 0xFFFF
            temp += 1

    return temp


BASE_HTTP = "HTTP/1.0 200 OK\r\nContent-Length: "


def read_files(start_addr=0x00000000, num_entries=512):
    root = Path(__file__).parent
    count = 0
    next_start_addr = start_addr or 0x00000000
    num_entries = num_entries or 512
    with open("addrs.mem", "w") as fa:
        with open("lengths.mem", "w") as fl:
            with open("content.mem", "w", newline="") as fc:
                with open("content_hex.mem", "w", newline="") as fh:
                    for p in root.glob('*.html'):
                        assert count < num_entries

                        data = p.read_text()

                        entire_data = f"{BASE_HTTP}{len(data)}\r\n\r\n{data}"
                        data_bytes = bytearray(entire_data, "ascii")
                        fc.write(entire_data)
                        for i in range(0, len(data_bytes), 4):
                            word = int.from_bytes(data_bytes[i:i+4], 'little')
                            fh.write(f'{word:08X}\n')
                        #     data_word_count += 1

                        fa.write(f"{next_start_addr:09x}\n")

                        padded_length_32 = int(
                            _align_32(len(data) + len(BASE_HTTP) + 4))
                        length_data = f"{padded_length_32:04x}\n"
                        checksum = calc_tcp_checksum(data_bytes)
                        fl.write(f"0{checksum:04x}{length_data}")

                        count += 1
                        next_start_addr += padded_length_32

                    # pad the rest with zeroes
                    for i in range(count, num_entries):
                        fa.write(f"{0:09x}\n")
                        fl.write(f"{0:09x}\n")
                    # padding to 512 rows
                    for i in range(512-padded_length_32):
                        fh.write(f'{0:08X}\n')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-start", help="Start address of Flash to write", type=int)
    parser.add_argument(
        "-entries", help="Number of HTTP entries", type=int)
    args = parser.parse_args()
    read_files(args.start, args.entries)

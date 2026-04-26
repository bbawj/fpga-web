import argparse
from pathlib import Path


def _align_32(size):
    if size % 4 == 0:
        return size
    else:
        return size + 4 - (size % 4)


def read_files(start_addr=0x00100000, num_entries=512):
    root = Path(__file__).parent
    count = 0
    next_start_addr = start_addr or 0x00040000
    num_entries = num_entries or 512
    with open("addrs.mem", "w") as fa:
        with open("lengths.mem", "w") as fl:
            for p in root.glob('*.html'):
                assert count < num_entries

                data = p.read_text()
                length_data = f"{len(data):018x}\n"

                fa.write(f"{next_start_addr:018x}\n")
                fl.write(length_data)

                count += 1
                next_start_addr += _align_32(len(data))

            # pad the rest with zeroes
            for i in range(count, num_entries):
                fa.write(f"{0:018x}\n")
                fl.write(f"{0:018x}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-start", help="Start address of Flash to write", type=int)
    parser.add_argument(
        "-entries", help="Number of HTTP entries", type=int)
    args = parser.parse_args()
    read_files(args.start, args.entries)

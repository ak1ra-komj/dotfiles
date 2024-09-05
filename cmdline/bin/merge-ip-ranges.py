#! /usr/bin/env python3
# coding: utf-8
# sudo apt install python3-netaddr

import argparse
import fileinput

from netaddr import IPSet, IPNetwork


def digit_str_zfill(digit_str: str, group):
    zfill = (len(digit_str) + group - 1) // group * group
    return " ".join(
        digit_str.zfill(zfill)[i : i + group] for i in range(0, len(digit_str), group)
    )


def digit_to_binary(digit_str: str, base=16, group=4):
    try:
        binary_str = bin(int(digit_str, base)).removeprefix("0b")
        return digit_str_zfill(binary_str, group)
    except ValueError:
        return digit_str


def ip_network_to_binary(ip_network: IPNetwork):
    sep, base, group = (":", 16, 4) if ip_network.version == 6 else (".", 10, 8)
    binary_addr = sep.join(
        digit_to_binary(digit_str, base, group)
        for digit_str in str(ip_network.network).split(sep)
    )
    return f"{binary_addr}/{ip_network.prefixlen}"


def ip_network_zfill(ip_network: IPNetwork):
    sep, group = (":", 4) if ip_network.version == 6 else (".", 3)
    zfill_addr = sep.join(
        digit_str_zfill(digit_str, group)
        for digit_str in str(ip_network.network).split(sep)
    )
    return f"{zfill_addr}/{ip_network.prefixlen}"


def merge_ip_ranges(ip_range_files):
    ipset = IPSet()
    try:
        # Read from input sources (either files or stdin)
        for ip_range in fileinput.input(files=ip_range_files):
            ip_range = ip_range.strip()
            if ip_range:  # Skip empty ip_ranges
                ipset.add(IPNetwork(ip_range))
    except KeyboardInterrupt:
        print()
    return ipset


def main():
    parser = argparse.ArgumentParser(
        description="merge IP ranges from files or standard input."
    )
    parser.add_argument(
        "-b",
        "--binary",
        action="store_true",
        default=False,
        help="output addresses in binary format.",
    )
    parser.add_argument(
        "-z",
        "--zfill",
        action="store_true",
        default=False,
        help="output addresses prefixed with zero.",
    )
    parser.add_argument(
        "files",
        nargs="*",
        metavar="FILE",
        help="input files containing IP ranges. If not specified, reads from stdin.",
    )
    args = parser.parse_args()

    for cidr in merge_ip_ranges(args.files).iter_cidrs():
        if args.binary:
            print(ip_network_to_binary(cidr))
        elif args.zfill:
            print(ip_network_zfill(cidr))
        else:
            print(str(cidr))


if __name__ == "__main__":
    main()

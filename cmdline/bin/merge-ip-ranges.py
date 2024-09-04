#! /usr/bin/env python3
# coding: utf-8
# apt install python3-netaddr

import argparse
import fileinput
from netaddr import IPSet, IPNetwork


def merge_ip_ranges(ip_range_files):
    ipset = IPSet()

    # Read from input sources (either files or stdin)
    for ip_range in fileinput.input(files=ip_range_files):
        ip_range = ip_range.strip()
        if ip_range:  # Skip empty ip_ranges
            ipset.add(IPNetwork(ip_range))

    # Return the merged ranges
    return list(ipset.iter_cidrs())


def main():
    parser = argparse.ArgumentParser(
        description="Merge IP ranges from files or standard input."
    )
    parser.add_argument(
        "files",
        nargs="*",
        metavar="FILE",
        help="Input files containing IP ranges. If not specified, reads from stdin.",
    )
    args = parser.parse_args()

    merged_ranges = merge_ip_ranges(args.files)

    for cidr in merged_ranges:
        print(cidr)


if __name__ == "__main__":
    main()

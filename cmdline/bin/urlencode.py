#! /usr/bin/env python3
# coding: utf-8

import argparse
import fileinput
from urllib.parse import quote, unquote


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-d",
        "--decode",
        action="store_true",
        default=False,
        help="urldecode lines from files",
    )
    parser.add_argument(
        "files",
        nargs="*",
        metavar="FILE",
        help="files to read, if empty, stdin is used",
    )
    args = parser.parse_args()
    process = unquote if args.decode else quote

    try:
        for line in fileinput.input(
            files=args.files if len(args.files) > 0 else ("-",)
        ):
            print(process(line.rstrip()))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

#! /usr/bin/env python3
# coding: utf-8

import argparse

from urllib.parse import quote


def urlencode(urls):
    for url in urls:
        print(quote(url))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "urls",
        nargs="+",
        metavar="URL",
        help="urls to encode with urllib.parse.quote()",
    )
    args = parser.parse_args()

    if len(args.urls) > 0:
        urlencode(args.urls)


if __name__ == "__main__":
    main()

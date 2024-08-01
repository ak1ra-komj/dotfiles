#! /usr/bin/env python3
# coding: utf-8

import argparse

from urllib.parse import quote


def urlencode(texts):
    for text in texts:
        print(quote(text))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "texts",
        nargs="+",
        metavar="TEXT",
        help="texts to encode with urllib.parse.quote()",
    )
    args = parser.parse_args()

    if len(args.texts) > 0:
        urlencode(args.texts)


if __name__ == "__main__":
    main()

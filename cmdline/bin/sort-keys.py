#! /usr/bin/env python3
# coding: utf-8

import argparse
import json


def save_json(filename, data):
    with open(filename, "w", encoding="utf-8") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent=4, sort_keys=True))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("json_files", nargs="+", metavar="JSON_FILE",
                        help="json input files to sort_keys")
    args = parser.parse_args()

    input_files = args.json_files if args.json_files and len(args.json_files) > 0 else []

    for file in input_files:
        with open(file) as f:
            data = json.loads(f.read())
        save_json(file, data)


if __name__ == "__main__":
    main()

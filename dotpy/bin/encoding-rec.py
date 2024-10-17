#!/usr/bin/env python3
# coding: utf-8
# ref: [乱码恢复指北 | Re:Linked](https://blog.outv.im/2019/encoding-guide/)
# ref: http://www.mytju.com/classcode/tools/messyCodeRecover.asp
# (gbk       ) "垽偝傟側偔偰傕孨偑偄傞" => (shift-jis ) "愛されなくても君がいる"

import argparse
import fileinput


def encoding_rec(text):
    encoding_list = ["utf-8", "iso-8859-1", "gbk", "big5", "shift-jis"]
    align = max(len(_) for _ in encoding_list)
    for current_enc in encoding_list:
        for guessed_enc in encoding_list:
            if guessed_enc == current_enc:
                continue

            text_encoded = text.encode(current_enc, errors="ignore")
            if not text_encoded:
                continue

            text_decoded = text_encoded.decode(guessed_enc, errors="ignore")
            if not text_decoded:
                continue

            print(
                f'({current_enc:>{align}}) "{text}" => ({guessed_enc:>{align}}) "{text_decoded}"'
            )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "files",
        nargs="*",
        metavar="FILE",
        help="messy encoded files to read, if empty, stdin is used",
    )
    args = parser.parse_args()

    try:
        for line in fileinput.input(files=args.files):
            encoding_rec(line.rstrip())
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()

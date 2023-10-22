#!/usr/bin/env python3
# coding: utf-8
# ref: [乱码恢复指北 | Re:Linked](https://blog.outv.im/2019/encoding-guide/)
# ref: http://www.mytju.com/classcode/tools/messyCodeRecover.asp

import argparse


def messy_text_recover(messy_text, encodings=None):
    if not encodings:
        encodings = ['iso-8859-1', 'windows-1252', 'gbk', 'big5', 'shift-jis']
    for current_encoding in encodings:
        for guessed_encoding in encodings:
            decoded = messy_text.encode(current_encoding, errors='ignore').decode(
                guessed_encoding, errors='ignore')
            print(
                f'"{messy_text}".encode("{current_encoding}").decode("{guessed_encoding}") => "{decoded}"')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("texts", nargs="+", help="messy text to recover")
    args = parser.parse_args()

    # "垽偝傟側偔偰傕孨偑偄傞".encode("gbk").decode("shift-jis") => "愛されなくても君がいる"
    messy_texts = args.texts if args.texts and len(args.texts) > 0 else []
    for messy_text in messy_texts:
        messy_text_recover(messy_text)


if __name__ == "__main__":
    main()

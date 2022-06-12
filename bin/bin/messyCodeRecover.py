#!/usr/bin/env python3
# coding: utf-8
# ref: [乱码恢复指北 | Re:Linked](https://blog.outv.im/2019/encoding-guide/)
# ref: http://www.mytju.com/classcode/tools/messyCodeRecover.asp

import sys

def recover(messy_input, encodings=None):
    if not encodings:
        encodings = ['iso-8859-1', 'windows-1252', 'gbk', 'big5', 'shift-jis']
    for current_encoding in encodings:
        for guessed_encoding in encodings:
            decoded = messy_input.encode(current_encoding, errors='ignore').decode(guessed_encoding, errors='ignore')
            print(f'"{messy_input}".encode("{current_encoding}").decode("{guessed_encoding}") => "{decoded}"')

if __name__ == "__main__":
    # "垽偝傟側偔偰傕孨偑偄傞".encode("gbk").decode("shift-jis") => "愛されなくても君がいる"
    for messy_input in sys.argv[1:]:
        recover(messy_input)

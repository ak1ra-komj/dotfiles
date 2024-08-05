#! /usr/bin/env python3
# coding: utf-8

import fileinput
import urllib.parse


if __name__ == "__main__":
    for line in fileinput.input():
        print(urllib.parse.quote(line.strip()))

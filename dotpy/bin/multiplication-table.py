#!/usr/bin/env python3

import sys
import unicodedata


FULL_WIDTH_SPACE = "　"


def uses_full_width_spacing(digits):
    """
    Return True when the digit set contains wide or full-width symbols.
    """
    return any(unicodedata.east_asian_width(digit) in {"F", "W"} for digit in digits)


def format_number(num, digits):
    """
    Convert a decimal number `num` to a string representation
    using the given `digits` character set as the positional system.
    """
    base = len(digits)
    if num == 0:
        return digits[0]
    result = []
    while num > 0:
        result.append(digits[num % base])
        num //= base
    return "".join(reversed(result))


def print_multiplication_table(digits):
    """
    Print a staircase multiplication table (1 × 1 up to max × max)
    using the custom digit set. The base is determined by len(digits).
    """
    base = len(digits)
    if base < 2:
        print("Error: digit set must contain at least 2 characters.")
        return

    max_num = base - 1
    # Width of the largest product string, used for alignment
    max_product_str = format_number(max_num * max_num, digits)
    width = len(max_product_str)
    separator = FULL_WIDTH_SPACE if uses_full_width_spacing(digits) else " "

    for i in range(1, max_num + 1):
        row_label = digits[i]
        items = []
        for j in range(1, i + 1):
            product_str = format_number(i * j, digits).rjust(width, separator)
            expr = f"{digits[i]}×{digits[j]}={product_str}"
            items.append(expr)
        print(f"{row_label}{separator * 2}" + separator.join(items))


def main():
    """
    Print a staircase multiplication table with custom digit sets.
    The digit set defines the base and the symbols used for numbers.

    Some examples of digit sets:
        - "⚀⚁⚂⚃⚄⚅" (base 6)
        - "😋😃😄😁😆😅🤣😂" (base 8)
        - "⓪①②③④⑤⑥⑦⑧⑨" (base 10)
        - "〇一二三四五六七八九" (base 10)
        - "零壹贰叁肆伍陆柒捌玖" (base 10)
        - "〇〡〢〣〤〥〦〧〨〩" (base 10, 苏州码子)
        - "甲乙丙丁戊己庚辛壬癸" (base 10)
        - "子丑寅卯辰巳午未申酉戌亥" (base 12)
        - "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" (base 36)
    """
    default_digits = "0123456789ABCDEF"

    # Allow a custom digit string from the command line
    if len(sys.argv) > 1:
        digits = sys.argv[1]
    else:
        digits = default_digits

    base = len(digits)
    print(f"\nMultiplication table using digit set: '{digits}' (base {base})\n")
    print_multiplication_table(digits)


if __name__ == "__main__":
    main()

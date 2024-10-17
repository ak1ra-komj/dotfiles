#!/usr/bin/env python3
# coding: utf-8

import shutil
import glob
import argparse
import concurrent.futures


def archive_directory(dir_name, format):
    """Archive the directory based on the format type."""
    # root_dir and base_dir both default to the current directory
    shutil.make_archive(base_name=dir_name, format=format, base_dir=dir_name)
    print(f"Archived directory '{dir_name}' into '{format}' format")


def dir_archive(format, max_workers):
    """Archive all directories in the current directory."""
    # List directories in the current directory, excluding hidden ones like .git
    dirs = [d for d in glob.glob("*/") if not d.startswith((".", "./"))]

    # Execute the archive command in parallel using ProcessPoolExecutor
    with concurrent.futures.ProcessPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(archive_directory, d.strip("/"), format): d for d in dirs
        }
        for future in concurrent.futures.as_completed(futures):
            dir_name = futures[future]
            try:
                future.result()
            except Exception as exc:
                print(f"Error archiving directory '{dir_name}': {exc}")


def main():
    try:
        # Register 7z format if py7zr is installed
        # pip3 install -U py7zr || apt install python3-py7zr
        from py7zr import pack_7zarchive, unpack_7zarchive
        shutil.register_archive_format("7z", function=pack_7zarchive, description="7zip archive")
        shutil.register_unpack_format("7z", extensions=[".7z"], function=unpack_7zarchive)
    except ImportError:
        pass

    # Argument parsing
    parser = argparse.ArgumentParser(
        description="Archive directories in the current directory."
    )
    parser.add_argument(
        "-w",
        "--max_workers",
        type=int,
        default=4,
        help="max_workers for ProcessPoolExecutor (default: %(default)s)",
    )
    parser.add_argument(
        "format",
        choices=[ar[0] for ar in shutil.get_archive_formats()],
        help="Specify the archive format.",
    )
    args = parser.parse_args()

    # Archive directories
    dir_archive(args.format, args.max_workers)


if __name__ == "__main__":
    main()

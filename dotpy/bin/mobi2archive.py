#! /usr/bin/env python3
# A helper script to convert vol.moe's mobi files to 7zip archives.
# python3 -m pip install mobi py7zr

import argparse
import logging
import os
import shutil
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from itertools import repeat
from pathlib import Path

import mobi
from py7zr import pack_7zarchive, unpack_7zarchive

format_ext = {
    "7zip": ".7z",
    "zip": ".zip",
    "tar": ".tar",
    "gztar": ".tar.gz",
    "bztar": ".tar.bz2",
    "xztar": ".tar.xz"
}

def init_logger(name, level=logging.INFO):
    format = "[%(asctime)s][%(levelname) 7s] %(name)s: %(message)s"
    logging.basicConfig(format=format, level=level, stream=sys.stderr)

    return logging.getLogger(name)

logger = init_logger("mobi2archive", logging.DEBUG)

def parse_args():
    parser = argparse.ArgumentParser()

    parser.add_argument("-d", "--directory", default=Path("."), help="directory to process for mobi files")
    parser.add_argument("-f", "--format", default="7zip",
        choices=format_ext.keys(), help="archive file format to convert to")
    parser.add_argument("-F", "--force", action="store_true", default=False,
        help="force to overwrite existing archive files")

    return parser.parse_args()

def mobi2archive(mobi_file, format="7zip"):
    start = time.perf_counter()
    logger.info(f"Processing {mobi_file} to {format} archive...")
    extract_dir, _ = mobi.extract(str(mobi_file))
    elapsed = time.perf_counter() - start
    logger.debug(f"mobi.extract({mobi_file}) finished in {elapsed:0.5f} seconds")
    extract_dir = extract_dir if isinstance(extract_dir, Path) else Path(extract_dir)

    # Images directory
    # HDImages = extract_dir.joinpath("HDImages")
    mobi7 = extract_dir.joinpath("mobi7/Images")
    mobi8 = extract_dir.joinpath("mobi8/OEBPS/Images")
    root_dir = mobi8 if any(mobi8.iterdir()) else mobi7

    # 这样应该没有子目录, 压缩文件保存在源文件同目录
    base_name, _ = os.path.splitext(mobi_file)
    archive = base_name + format_ext.get(format)
    start = time.perf_counter()
    shutil.make_archive(base_name, format=format, root_dir=root_dir)
    elapsed = time.perf_counter() - start
    logger.debug(f"shutil.make_archive({archive}) finished in {elapsed:0.5f} seconds")

    # clean up
    shutil.rmtree(extract_dir)

def main():
    args = parse_args()

    # register file format at first
    shutil.register_archive_format("7zip", pack_7zarchive, description="7zip archive")
    shutil.register_unpack_format("7zip", [".7z"], unpack_7zarchive)

    mobi_files = []
    for root, _, files in os.walk(args.directory):
        root = root if isinstance(root, Path) else Path(root)
        for file in files:
            file = root.absolute() / file

            base_name, ext = os.path.splitext(file)
            if ext != ".mobi":
                continue
            archive = base_name + format_ext.get(args.format)
            if os.path.exists(archive) and not args.force:
                logger.info(f"{archive} exist, skip...")
                continue

            mobi_files.append(file)

    if not len(mobi_files) > 0:
        return

    with ProcessPoolExecutor() as executor:
        executor.map(mobi2archive, mobi_files, repeat(args.format))

if __name__ == "__main__":
    start = time.perf_counter()
    main()
    elapsed = time.perf_counter() - start
    logger.debug(f"Program finished in {elapsed:0.5f} seconds")

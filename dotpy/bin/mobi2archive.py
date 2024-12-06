#! /usr/bin/env python3
# coding: utf-8
# A helper script to convert vol.moe's mobi files to 7zip archives.
# python3 -m pip install mobi py7zr

import argparse
import logging
import os
import shutil
import time
import concurrent.futures
from pathlib import Path

import mobi


logging.basicConfig(
    format="[%(asctime)s][%(name)s][%(levelname)s] %(message)s", level=logging.DEBUG
)
logger = logging.getLogger(__name__)


format_ext = {
    "7z": ".7z",
    "zip": ".zip",
    "tar": ".tar",
    "gztar": ".tar.gz",
    "bztar": ".tar.bz2",
    "xztar": ".tar.xz",
}


def mobi2archive(mobi_file, format="zip", dry_run=False):
    start = time.perf_counter()
    logger.info("Processing %s to %s archive...", mobi_file, format)
    extract_dir, _ = mobi.extract(str(mobi_file))
    elapsed = time.perf_counter() - start
    logger.debug("mobi.extract(%s) finished in %0.5f seconds", mobi_file, elapsed)
    extract_dir = extract_dir if isinstance(extract_dir, Path) else Path(extract_dir)

    # Images directory
    # HDImages = extract_dir.joinpath("HDImages")
    mobi7 = extract_dir.joinpath("mobi7/Images")
    mobi8 = extract_dir.joinpath("mobi8/OEBPS/Images")
    root_dir = mobi8 if any(mobi8.iterdir()) else mobi7

    # 这样应该没有子目录, 压缩文件保存在源文件同目录
    start = time.perf_counter()
    archive = shutil.make_archive(
        mobi_file.stem, format=format, root_dir=root_dir, dry_run=dry_run
    )
    elapsed = time.perf_counter() - start
    logger.debug("shutil.make_archive(%s) finished in %0.5f seconds", archive, elapsed)

    # clean up
    shutil.rmtree(extract_dir)

    return mobi_file


def get_mobi_files(directory, format, force=False):
    mobi_files = []
    for root, _, files in os.walk(directory):
        root = root if isinstance(root, Path) else Path(root)
        for f in files:
            file = root.resolve() / f
            if file.suffix != ".mobi":
                continue
            archive = file.with_suffix(format_ext.get(format))
            if os.path.exists(archive) and not force:
                logger.warning("%s exist, skip...", archive)
                continue

            mobi_files.append(file)

    return mobi_files


def parse_args():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "directory",
        help="directory to find for mobi files, os.walk() recursively",
    )
    parser.add_argument(
        "-f",
        "--format",
        default="zip",
        choices=[ar[0] for ar in shutil.get_archive_formats()],
        help="archive file format to convert to",
    )
    parser.add_argument(
        "-F",
        "--force",
        action="store_true",
        help="force to overwrite existing archive files",
    )
    parser.add_argument(
        "-D",
        "--dry-run",
        action="store_true",
        help="dry_run argument for shutil.make_archive",
    )
    parser.add_argument(
        "-w",
        "--max_workers",
        type=int,
        default=4,
        help="max_workers for ProcessPoolExecutor (default: %(default)s)",
    )

    return parser.parse_args()


def main():
    try:
        # Register 7z format if py7zr is installed
        # pip3 install -U py7zr || apt install python3-py7zr
        from py7zr import pack_7zarchive, unpack_7zarchive

        shutil.register_archive_format(
            "7z", function=pack_7zarchive, description="7zip archive"
        )
        shutil.register_unpack_format(
            "7z", extensions=[".7z"], function=unpack_7zarchive
        )
    except ImportError:
        pass

    args = parse_args()
    mobi_files = get_mobi_files()
    if not len(mobi_files) > 0:
        return

    start = time.perf_counter()
    # Execute the archive command in parallel using ProcessPoolExecutor
    with concurrent.futures.ProcessPoolExecutor(
        max_workers=args.max_workers
    ) as executor:
        futures = {
            executor.submit(mobi2archive, file, args.format, args.dry_run): file
            for file in mobi_files
        }
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as exc:
                logger.warning(exc)
    elapsed = time.perf_counter() - start
    logger.debug("Program finished in %0.5f seconds", elapsed)


if __name__ == "__main__":
    main()

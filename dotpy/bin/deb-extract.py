#!/usr/bin/env python3
import argparse
import logging
import shutil
import tarfile
from pathlib import Path

from debian import arfile


class DebExtractor:
    def __init__(self, delete_mode=False, verbose=False):
        self.delete_mode = delete_mode
        self.cwd = Path.cwd()
        self._setup_logging(verbose)

    def _setup_logging(self, verbose):
        """配置日志系统"""
        self.logger = logging.getLogger("deb_extractor")
        handler = logging.StreamHandler()
        formatter = logging.Formatter(
            "%(asctime)s - %(levelname)s - %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
        )
        handler.setFormatter(formatter)
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.DEBUG if verbose else logging.INFO)

    def process_deb(self, deb_path: Path):
        """处理单个.deb文件"""
        extract_dir = self.cwd / deb_path.stem

        if self.delete_mode:
            self._remove_extracted(extract_dir)
        else:
            self._extract_deb(deb_path, extract_dir)

    def _extract_deb(self, deb_path: Path, extract_dir: Path):
        """提取.deb文件内容"""
        if extract_dir.exists():
            self.logger.info(f"Skipping {deb_path.name} (already extracted)")
            return

        try:
            with open(deb_path, "rb") as f:
                ar = arfile.ArFile(fileobj=f)
                self._extract_ar_contents(ar, extract_dir)
            self.logger.info(f"Successfully extracted {deb_path.name} to {extract_dir}")
        except (OSError, arfile.ArError, tarfile.TarError) as e:
            shutil.rmtree(extract_dir, ignore_errors=True)
            self.logger.error(
                f"Failed to process {deb_path.name}: {str(e)}", exc_info=True
            )

    def _extract_ar_contents(self, ar: arfile.ArFile, extract_dir: Path):
        """提取ar文件中的控制信息和数据"""
        control_dir = extract_dir / "control"
        data_dir = extract_dir / "data"

        control_dir.mkdir(parents=True)
        data_dir.mkdir()

        for member in ar.getmembers():
            if member.name.startswith("control.tar"):
                with tarfile.open(fileobj=ar.extractfile(member)) as tar:
                    tar.extractall(path=control_dir)
                self.logger.debug(f"Extracted control files to {control_dir}")
            elif member.name.startswith("data.tar"):
                with tarfile.open(fileobj=ar.extractfile(member)) as tar:
                    tar.extractall(path=data_dir)
                self.logger.debug(f"Extracted data files to {data_dir}")

    def _remove_extracted(self, extract_dir: Path):
        """删除已提取的目录"""
        if extract_dir.exists() and extract_dir.is_dir():
            try:
                shutil.rmtree(extract_dir)
                self.logger.info(f"Successfully removed {extract_dir}")
            except OSError as e:
                self.logger.error(
                    f"Failed to remove {extract_dir}: {str(e)}", exc_info=True
                )

    def run(self):
        """主执行逻辑"""
        deb_files = sorted(self.cwd.glob("*.deb"))
        if not deb_files:
            self.logger.warning("No .deb files found in current directory")
            return

        self.logger.info(f"Found {len(deb_files)} .deb file(s) to process")
        for deb_file in deb_files:
            self.process_deb(deb_file)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Debian package extractor with logging",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "-d",
        "--delete",
        action="store_true",
        help="Remove extracted directories instead of extracting",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Enable verbose/debug output"
    )
    args = parser.parse_args()

    extractor = DebExtractor(delete_mode=args.delete, verbose=args.verbose)
    extractor.run()

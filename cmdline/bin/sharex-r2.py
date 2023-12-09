#! /usr/bin/env python3
# coding: utf-8

import argparse
import asyncio
import json
import mimetypes
import pathlib

import aiofiles
import httpx


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--config",
                        default="~/.config/sharex-r2/config.json", help="config file")
    parser.add_argument("-u", "--upload",
                        metavar="FILE", nargs="+", help="image files to upload")
    parser.add_argument("-d", "--delete",
                        metavar="URL", nargs="+", help="image urls to delete")
    return parser.parse_args()


async def main():
    args = parse_args()

    config_file = pathlib.Path(args.config).expanduser()
    uploads_txt = config_file.parent / "uploads.txt"
    with open(config_file, encoding="utf-8") as f:
        config = json.loads(f.read())

    endpoint = config.get("endpoint")
    headers = {
        "content-type": "",
        "x-auth-key": config.get("x-auth-key")
    }

    upload_files = args.upload if args.upload and len(args.upload) > 0 else []
    delete_urls = args.delete if args.delete and len(args.delete) > 0 else []

    async with httpx.AsyncClient() as client:
        for file in upload_files:
            file = pathlib.Path(file).expanduser()
            headers.update({"content-type": mimetypes.guess_type(file)[0]})

            async with aiofiles.open(file, "rb") as f:
                content = await f.read()
            resp = await client.post(
                endpoint + f"?filename={file.name}", content=content, headers=headers
            )

            async with aiofiles.open(uploads_txt, 'a') as f:
                await f.write(json.dumps(resp.json(), ensure_ascii=False) + "\n")

        headers.pop("content-type")
        for url in delete_urls:
            await client.delete(url, headers=headers)


if __name__ == "__main__":
    asyncio.run(main())

#!/usr/bin/env python3
"""Upload local .pmtiles files to Garage for CloudTAK Hosted tilesets."""
from __future__ import annotations

import argparse
import os
import sys

import boto3
from botocore.client import Config


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("pairs", nargs="+", help="path|key pairs")
    p.add_argument("--endpoint", default=os.environ.get("AWS_S3_ENDPOINT", "http://tak-store:3900"))
    p.add_argument("--bucket", default=os.environ["BUCKET"])
    args = p.parse_args()

    client = boto3.client(
        "s3",
        endpoint_url=args.endpoint,
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        region_name="us-east-1",
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )

    for item in args.pairs:
        path, key = item.split("|", 1)
        size = os.path.getsize(path)
        print(f"put {path} -> s3://{args.bucket}/{key} ({size} bytes)", flush=True)
        client.upload_file(
            path,
            args.bucket,
            key,
            ExtraArgs={"ContentType": "application/vnd.pmtiles"},
        )
        head = client.head_object(Bucket=args.bucket, Key=key)
        print(
            f"ok  {key} etag={head.get('ETag')} size={head.get('ContentLength')}",
            flush=True,
        )
    print("done", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyError as e:
        print(f"missing env: {e}", file=sys.stderr)
        raise SystemExit(1)

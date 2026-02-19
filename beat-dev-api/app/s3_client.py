# app/ai_client.py  (이제 S3 helper로 사용)
from __future__ import annotations

import boto3
from .config import settings

_s3 = boto3.client("s3", region_name=settings.AWS_REGION)

def upload_fileobj_to_s3(fileobj, key: str, content_type: str | None = None) -> None:
    extra = {}
    if content_type:
        extra["ContentType"] = content_type

    _s3.upload_fileobj(
        Fileobj=fileobj,
        Bucket=settings.S3_BUCKET,
        Key=key,
        ExtraArgs=extra if extra else None,
    )

def presign_get(key: str, expires: int | None = None) -> str:
    return _s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.S3_BUCKET, "Key": key},
        ExpiresIn=expires or settings.PRESIGN_EXPIRE_SECONDS,
    )

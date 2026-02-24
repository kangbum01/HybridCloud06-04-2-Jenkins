# app/queue_client.py
import os, json, boto3
from datetime import datetime, timezone
from .config import settings

sqs = boto3.client("sqs", region_name=settings.AWS_REGION)

def publish_job(task_id: str, s3_audio_key: str, user_request: str | None = None, version: int = 3):
    body = {
        "task_id": task_id,
        "s3_audio_key": s3_audio_key,
        "version": version,
        "user_request": user_request or "default",
    }
    sqs.send_message(
        QueueUrl=settings.JOB_QUEUE_URL,
        MessageBody=json.dumps(body,ensure_ascii=False),
    )
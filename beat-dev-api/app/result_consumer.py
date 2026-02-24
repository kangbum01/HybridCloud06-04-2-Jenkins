# app/result_consumer.py
from __future__ import annotations

import json
import threading
import time
from typing import Any, Dict, Optional

import boto3

from .config import settings
from .db_client import update_job_results, update_job_status

_stop_event = threading.Event()
_thread: Optional[threading.Thread] = None


def start_result_consumer() -> None:
    global _thread
    if _thread and _thread.is_alive():
        return
    _stop_event.clear()
    _thread = threading.Thread(target=_loop, name="result-consumer", daemon=True)
    _thread.start()


def stop_result_consumer() -> None:
    _stop_event.set()


def _parse_body(raw: str) -> Dict[str, Any]:
    """
    SQS body가 순수 JSON인 경우가 대부분.
    혹시 SNS->SQS 형태면 {"Message":"...json..."}로 감싸질 수 있어 방어.
    """
    body = json.loads(raw)
    if isinstance(body, dict) and "Message" in body and isinstance(body["Message"], str):
        try:
            return json.loads(body["Message"])
        except Exception:
            pass
    return body if isinstance(body, dict) else {}


def _loop() -> None:
    sqs = boto3.client("sqs", region_name=settings.AWS_REGION)
    qurl = settings.RESULT_QUEUE_URL

    while not _stop_event.is_set():
        try:
            resp = sqs.receive_message(
                QueueUrl=qurl,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20,      # long polling
                VisibilityTimeout=120,   # 처리 시간 여유
            )
            msgs = resp.get("Messages", [])
            if not msgs:
                continue

            msg = msgs[0]
            receipt = msg["ReceiptHandle"]
            body = _parse_body(msg.get("Body", "{}"))

            task_id = body.get("task_id") or body.get("job_id")
            status = body.get("status")
            result = body.get("result") or {}
            error = body.get("error")

            if not task_id or not status:
                # 포맷이 이상하면 DLQ로 보내고 싶겠지만, 일단 재시도로 넘김(삭제 X)
                raise ValueError(f"invalid message: {body}")

            if status == "DONE":
                update_job_results(
                    job_id=task_id,
                    status="DONE",
                    result_json_key=result.get("json_key"),
                    result_html_key=result.get("html_key"),
                    result_mp4_key=result.get("mp4_key"),
                    error_message=None,
                )
            elif status == "FAIL":
                update_job_status(task_id, "FAIL", error_message=error or "AI failed")
            else:
                raise ValueError(f"unknown status: {status}")

            # 성공 처리했으면 메시지 삭제
            sqs.delete_message(QueueUrl=qurl, ReceiptHandle=receipt)

        except Exception as e:
            # 삭제 안 하면 재시도 → maxReceiveCount 넘으면 DLQ로 이동
            print("[result-consumer] ERROR:", repr(e))
            time.sleep(2)
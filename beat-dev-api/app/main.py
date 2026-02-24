# app/main.py
from __future__ import annotations
from .result_consumer import start_result_consumer, stop_result_consumer
from typing import Optional
import uuid
from fastapi import FastAPI, UploadFile, File, Header, HTTPException,Form
from .config import settings
from .s3_client import upload_fileobj_to_s3, presign_get

from .db_client import (
   insert_job_pending,
   get_job as db_get_job,
   update_job_status,
   update_job_results,
)

from .queue_client import publish_job

app = FastAPI(title="beat-dev-api", version="0.2.23")

@app.get("/api/health")
def health():
  return {"ok": True}

@app.post("/api/jobs")
async def create_job(
    file: UploadFile = File(...),
    version: int = Form(3),
    user_request: str = Form(""),
):
    job_id = str(uuid.uuid4())
    user_request = (user_request or "").strip()
    filename = file.filename or "upload.bin"
    s3_key = f"{settings.S3_UPLOAD_PREFIX}/{job_id}/{filename}"
    if version not in (1,2,3):
        raise HTTPException(status_code=400, detail="invalid version")
    # 1) S3 업로드
    try:
        upload_fileobj_to_s3(file.file, key=s3_key, content_type=file.content_type)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"failed to upload to S3: {e}")

    # 2) jobs 테이블에 PENDING 생성 (s3_objects 제거)
    try:
        insert_job_pending(
            job_id=job_id, 
            upload_s3_key=s3_key, 
            original_name=filename,
            )
    except Exception as e:
        # jobs row 생성 자체가 실패하면 status 업데이트도 불가능할 수 있음
        raise HTTPException(status_code=500, detail=f"failed to write job to DB: {e}")

    # 3) SQS에 분석 요청 발행
    try:
        publish_job(
            task_id=job_id,
            s3_audio_key=s3_key,
            user_request=user_request,   # 아래 B에서 받음
            version = version,
        )
    except Exception as e:
        try:
            update_job_status(job_id, "FAIL", error_message=f"SQS publish failed: {e}")
        except Exception:
            pass
        raise HTTPException(status_code=500, detail=f"failed to publish job to SQS: {e}")

    # 4) 상태를 QUEUED로 업데이트
    try:
        update_job_status(job_id, "QUEUED")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"failed to update job status: {e}")

    return {"job_id": job_id, "status": "QUEUED", "upload_s3_key": s3_key}

@app.get("/api/jobs/{job_id}")
def get_job_api(job_id: str):
    row = db_get_job(job_id)
    if not row:
        raise HTTPException(status_code=404, detail="job not found")

    return {
        "job_id": row["job_id"],
        "status": row["status"],
        "upload_s3_key": row.get("upload_s3_key"),
        "original_name": row.get("original_name"),
        "result_json_key": row.get("result_json_key"),
        "result_html_key": row.get("result_html_key"),
        "result_mp4_key": row.get("result_mp4_key"),
        "error": row.get("error_message"),
    }

@app.get("/api/jobs/{job_id}/results")
def get_results(job_id: str):
    row = db_get_job(job_id)
    if not row:
        raise HTTPException(status_code=404, detail="job not found")

    if row["status"] != "DONE":
        raise HTTPException(status_code=409, detail=f"job not ready (status={row['status']})")

    urls = {}
    if row.get("result_json_key"):
        urls["json"] = presign_get(row["result_json_key"])
    if row.get("result_html_key"):
        urls["html"] = presign_get(row["result_html_key"])
    if row.get("result_mp4_key"):
        urls["mp4"] = presign_get(row["result_mp4_key"])
    if row.get("upload_s3_key"):
        urls["audio"] = presign_get(row["upload_s3_key"])

    return {"job_id": row["job_id"], "status": row["status"], "urls": urls}

# (선택) 콜백은 “테스트용”으로만 남겨도 됨
# - 실제 운영은 Result Worker가 RESULT_QUEUE를 consume 해서 DB 업데이트하는 구조가 정석
@app.post("/api/internal/callback")
async def callback(
    payload: dict,
    x_callback_token: Optional[str] = Header(default=None, alias="X-CALLBACK-TOKEN"),
):
    if x_callback_token != settings.CALLBACK_TOKEN:
        raise HTTPException(status_code=401, detail="invalid callback token")

    job_id = payload.get("job_id")
    status = payload.get("status")
    result = payload.get("result") or {}

    if not job_id or not status:
        raise HTTPException(status_code=400, detail="job_id and status are required")

    if status not in ("DONE", "FAIL"):
        raise HTTPException(status_code=400, detail="status must be DONE or FAIL")

    # ✅ DB 업데이트
    if status == "DONE":
        update_job_results(
            job_id=job_id,
            status="DONE",
            result_json_key=result.get("json_key"),
            result_html_key=result.get("html_key"),
            result_mp4_key=result.get("mp4_key"),
            error_message=None,
        )
    else:
        update_job_status(job_id, "FAIL", error_message=payload.get("error"))

    return {"ok": True}

# Result Consumer
@app.on_event("startup")
def _startup():
    start_result_consumer()

@app.on_event("shutdown")
def _shutdown():
    stop_result_consumer()


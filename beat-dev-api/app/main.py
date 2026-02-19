# app/main.py
from __future__ import annotations

from typing import Optional
import uuid
from fastapi import FastAPI, UploadFile, File, Header, HTTPException
from .config import settings
from .store import store
from .s3_client import upload_fileobj_to_s3, presign_get

app = FastAPI(title="beat-dev-api", version="0.2.0")

@app.get("/api/health")
def health():
  return {"ok": True}

@app.post("/api/jobs")
async def create_job(file: UploadFile = File(...)):
  job_id = str(uuid.uuid4())

  # S3 업로드 key 설계: uploads/{job_id}/{원본파일명}
  filename = file.filename or "upload.bin"
  s3_key = f"{settings.S3_UPLOAD_PREFIX}/{job_id}/{filename}"

  # 임시 store(나중에 DB로 교체될 자리)
  store.create(job_id, upload_s3_key=s3_key)

  try:
      # UploadFile.file 은 SpooledTemporaryFile이라 스트리밍 업로드 가능
      upload_fileobj_to_s3(file.file, key=s3_key, content_type=file.content_type)

      # 업로드 완료 상태로 저장 (AI가 DB 보고 처리할 것)
      store.update_status(job_id, "UPLOADED")

      return {"job_id": job_id, "status": "UPLOADED", "upload_s3_key": s3_key}

  except Exception as e:
      store.update_status(job_id, "FAIL", error=str(e))
      raise HTTPException(status_code=500, detail=f"failed to upload to S3: {e}")

@app.get("/api/jobs/{job_id}")
def get_job(job_id: str):
   job = store.get(job_id)
   if not job:
      raise HTTPException(status_code=404, detail="job not found")
   return store.to_dict(job)

@app.get("/api/jobs/{job_id}/results")
def get_results(job_id: str):
    job = store.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")

    if job.status != "DONE":
        raise HTTPException(status_code=409, detail=f"job not ready (status={job.status})")

    urls = {}
    if job.result_json_key:
        urls["json"] = presign_get(job.result_json_key)
    if job.result_html_key:
        urls["html"] = presign_get(job.result_html_key)
    if job.result_mp4_key:
        urls["mp4"] = presign_get(job.result_mp4_key)

    return {"job_id": job.job_id, "status": job.status, "urls": urls}

# (선택) 콜백은 “테스트용”으로만 남겨도 됨
@app.post("/api/internal/callback")
async def callback(
  payload: dict,
  x_callback_token: Optional[str] = Header(default=None, alias="X-CALLBACK-TOKEN")
):
  if x_callback_token != settings.CALLBACK_TOKEN:
     raise HTTPException(status_code=401, detail="invalid callback token")

  job_id = payload.get("job_id")
  status = payload.get("status")
  result = payload.get("result") or {}

  if not job_id or not status:
      raise HTTPException(status_code=400, detail="job_id and status are required")

  job = store.get(job_id)
  if not job:
      raise HTTPException(status_code=404, detail="job not found")

  if status not in ("DONE", "FAIL"):
      raise HTTPException(status_code=400, detail="status must be DONE or FAIL")

  store.update_status(
      job_id,
      status,
      result_json_key=result.get("json_key"),
      result_html_key=result.get("html_key"),
      result_mp4_key=result.get("mp4_key"),
      error=payload.get("error"),
  )
  return {"ok": True}

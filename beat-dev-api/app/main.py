from __future__ import annotations

from typing import Optional
import os
import uuid
from fastapi import FastAPI, UploadFile, File, Header, HTTPException
from fastapi.responses import JSONResponse
from .config import settings
from .store import store
from .ai_client import request_analysis

app = FastAPI(title="beat-dev-api", version="0.1.0")

@app.get("/api/health")
def health():
  return {"ok": True}

@app.post("/api/jobs")
async def create_job(file: UploadFile = File(...)):
  # 업로드 저장
  os.makedirs(settings.UPLOAD_DIR, exist_ok=True)

  job_id = str(uuid.uuid4())
  store.create(job_id)
  store.update_status(job_id, "RUNNING")

  save_path = os.path.join(settings.UPLOAD_DIR, f"{job_id}_{file.filename}")
  try:
      contents = await file.read()
      with open(save_path, "wb") as f:
         f.write(contents)

      await request_analysis(job_id=job_id, file_path=save_path)

      return {"job_id": job_id, "status": "RUNNING"}
  
  except Exception as e:
     store.update_status(job_id, "FAIL", error=str(e))
     raise HTTPException(status_code=500, detail=f"failed to create job: {e}")
  
@app.post("/api/internal/callback")
async def callback(
  payload: dict,
  x_callback_token: Optional[str] = Header(default=None, alias="X-CALLBACK-TOKEN")
):
  # 이곳은 오류 내용들 입니다.
  if x_callback_token != settings.CALLBACK_TOKEN:
     raise HTTPException(status_code=401, detail="invalid callback token")

  job_id = payload.get("job_id")
  status = payload.get("status")
  result = payload.get("result")
  error = payload.get("error")

  if not job_id or not status:
      raise HTTPException(status_code=400, detail="job_id and status are required")

  job = store.get(job_id)
  if not job:
      raise HTTPException(status_code=404, detail="job not found")

  if status not in ("DONE", "FAIL"):
      raise HTTPException(status_code=400, detail="status must be DONE or FAIL")

  store.update_status(job_id, status, result=result, error=error)
  return {"ok": True}

@app.get("/api/jobs/{job_id}")
def get_job(job_id: str):
   job = store.get(job_id)
   if not job:
      raise HTTPException(status_code=404, detail="job not found")
   return store.to_dict(job)

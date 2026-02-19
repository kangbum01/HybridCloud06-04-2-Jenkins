# app/store.py
from __future__ import annotations
from dataclasses import dataclass, asdict
from typing import Dict, Optional, Any
import threading
import time

@dataclass
class Job:
  job_id: str
  status: str  # PENDING | UPLOADED | PROCESSING | DONE | FAIL
  created_at: float

  upload_s3_key: str

  # AI가 생성하는 결과물들(S3 위치)
  result_json_key: Optional[str] = None
  result_html_key: Optional[str] = None
  result_mp4_key: Optional[str] = None

  error: Optional[str] = None

class JobStore:
  def __init__(self) -> None:
    self._lock = threading.Lock()
    self._jobs: Dict[str, Job] = {}

  def create(self, job_id: str, upload_s3_key: str) -> Job:
    job = Job(
      job_id=job_id,
      status="PENDING",
      created_at=time.time(),
      upload_s3_key=upload_s3_key,
    )
    with self._lock:
      self._jobs[job_id] = job
    return job

  def get(self, job_id: str) -> Optional[Job]:
    with self._lock:
      return self._jobs.get(job_id)

  def update_status(
      self,
      job_id: str,
      status: str,
      *,
      result_json_key: str | None = None,
      result_html_key: str | None = None,
      result_mp4_key: str | None = None,
      error: str | None = None,
  ) -> Optional[Job]:
    with self._lock:
      job = self._jobs.get(job_id)
      if not job:
        return None

      job.status = status
      if result_json_key is not None:
        job.result_json_key = result_json_key
      if result_html_key is not None:
        job.result_html_key = result_html_key
      if result_mp4_key is not None:
        job.result_mp4_key = result_mp4_key
      if error is not None:
        job.error = error
      return job

  def to_dict(self, job: Job) -> Dict[str, Any]:
    return asdict(job)

store = JobStore()

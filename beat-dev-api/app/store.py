# 임시 저장소 역할 : 나중에 RDS/Redis로 교체할꺼다
from __future__ import annotations
from dataclasses import dataclass, asdict
from typing import Dict, Optional, Any
import threading
import time

@dataclass
class Job:
  job_id: str
  status: str # PENDING | RUNNING | DONE | FAIL
  created_at: float
  result: Optional[Dict[str, Any]] = None
  error: Optional[str] = None

class JobStore:
  def __init__(self) -> None:
    self._lock = threading.Lock()
    self._jobs: Dict[str, Job] = {}
  
  def create(self, job_id: str) -> Job:
    job = Job(job_id=job_id, status="PENDING", created_at=time.time())
    with self._lock:
        self._jobs[job_id] = job
    return job
  
  def get(self, job_id: str) -> Optional[Job]:
    with self._lock:
      return self._jobs.get(job_id)
  
  def update_status(self, job_id: str, status: str, result=None, error=None) -> Optional[Job]:
    with self._lock:
      job = self._jobs.get(job_id)
      if not job:
        return None
      job.status = status
      if result is not None:
        job.result = result
      if error is not None:
        job.error = error
      return job
  
  def to_dict(self, job: Job) -> Dict[str, Any]:
    return asdict(job)
  
store = JobStore()

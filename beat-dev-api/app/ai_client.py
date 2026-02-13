# 여기서는 “파일을 AI로 전달 + job_id 전달”만 해둠.
# AI 서버 API 스펙이 아직 정확히 없으니 endpoint 이름만 바꾸면 되게 만들어둠.

from __future__ import annotations
import httpx
from typing import Optional
from .config import settings

async def request_analysis(job_id: str, file_path: str) -> Node:
    """
    AI 서버로 분석 요청을 보냄.
    - AI 서버가 성공적으로 요청을 받으면 OK(202/200) 가정
    - 분석 완료는 AI -> WAS 콜백으로 처리
    """
    headers = {}
    if settings.AI_AUTH_TOKEN:
        headers["Authorization"] = f"Bearer {settings.AI_AUTH_TOKEN}"
    
    url = f"{settings.AI_BASE_URL}/analyze"

    async with httpx.AsyncClient(timeout=60.0) as client:
        with open(file_path, "rb") as f:
            files = {"file": (file_path.split("/")[-1], f, "audio/mpeg")}
            data = {"job_id": job_id, "callback_url": "/api/internal/callback"}
            resp = await client.post(url, headers=headers, data=data, files=files)
    
    if resp.status_code >= 400:
        raise RuntimeError(f"AI request failed: {resp.status_code} {resp.text}")

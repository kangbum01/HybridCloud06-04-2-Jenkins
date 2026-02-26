# 🎵 Beat (Phase 2) — WAS ↔ S3 ↔ DB ↔ SQS ↔ AI 비동기 파이프라인

> **사용자 업로드 음악을 AI로 분석**하고, **분석 결과(JSON/MP4)** 를 기반으로 웹 화면이 반응하도록 만드는  
> **하이브리드(AWS + 온프레) 비동기 처리 아키텍처**입니다.

<p align="center">
  <img src="./docs/architecture.png" alt="Architecture" width="820" />
</p>

<p align="center">
  <img alt="AWS" src="https://img.shields.io/badge/AWS-ECS%20%7C%20S3%20%7C%20SQS%20%7C%20ALB-orange" />
  <img alt="FastAPI" src="https://img.shields.io/badge/FastAPI-API%20Server-009688" />
  <img alt="Terraform" src="https://img.shields.io/badge/Terraform-IaC-7B42BC" />
  <img alt="Datadog" src="https://img.shields.io/badge/Datadog-Monitoring-632CA6" />
</p>

---

## 목차

- [1. 프로젝트 한 줄 요약](#1-프로젝트-한-줄-요약)
- [2. 전체 흐름](#2-전체-흐름)
- [3. 구성요소](#3-구성요소)
- [4. API 스펙](#4-api-스펙)
- [5. SQS 메시지 계약](#5-sqs-메시지-계약)
- [6. DB 스키마](#6-db-스키마)
- [7. 환경 변수](#7-환경-변수)
- [8. 로컬 실행](#8-로컬-실행)
- [9. 배포 메모](#9-배포-메모)
- [10. 트러블슈팅](#10-트러블슈팅)
- [11. 다음 개선 과제](#11-다음-개선-과제)
- [Appendix. 리포지토리 구조(예시)](#appendix-리포지토리-구조예시)

---

## 1. 프로젝트 한 줄 요약

- **Web**(정적 페이지)에서 음악 업로드
- **WAS(FastAPI, ECS)** 가 **S3 업로드 + DB jobs 생성 + SQS Job 발행**
- **AI(온프레)** 가 **SQS Job 소비 → 분석 → S3 결과 업로드 → SQS Result 발행**
- **WAS Result Consumer** 가 **SQS Result 소비 → DB jobs 업데이트(DONE/FAIL)**
- **Web**은 `/api/jobs/{id}` & `/api/jobs/{id}/results` 로 **상태/결과 URL(프리사인)** 을 받아 화면을 갱신

---

## 2. 전체 흐름

```mermaid
sequenceDiagram
  autonumber
  participant U as User(Browser)
  participant W as Web(Static)
  participant A as WAS(FastAPI on ECS)
  participant S3 as S3
  participant DB as MySQL(or RDS/Proxy)
  participant J as SQS Job Queue
  participant AI as AI Server(On-Prem)
  participant R as SQS Result Queue

  U->>W: 파일 선택/업로드
  W->>A: POST /api/jobs (multipart)
  A->>S3: uploads/{job_id}/{filename} 업로드
  A->>DB: jobs INSERT (PENDING)
  A->>J: job 메시지 발행
  A->>DB: jobs UPDATE (QUEUED)

  AI->>J: 메시지 수신(consume)
  AI->>S3: results/{job_id}/result.json, video.mp4 업로드
  AI->>R: result 메시지 발행

  A->>R: 메시지 수신(consume)
  A->>DB: jobs UPDATE (DONE/FAIL, result keys)

  W->>A: GET /api/jobs/{job_id}
  alt DONE
    W->>A: GET /api/jobs/{job_id}/results
    A-->>W: presigned urls(json/mp4/audio)
  else QUEUED/PENDING
    W-->>U: 진행중 UI
  end

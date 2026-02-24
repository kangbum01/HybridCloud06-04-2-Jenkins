# db_client.py
import os
from contextlib import contextmanager
from datetime import datetime, timezone

import pymysql


def _db_kwargs():
    """
    ECS Task 환경변수로 주입:
      DB_HOST, DB_USER, DB_PASS, DB_NAME, (optional) DB_PORT, (optional) DB_CHARSET
    """
    return dict(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "3306")),
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASS"],
        database=os.environ["DB_NAME"],
        charset=os.environ.get("DB_CHARSET", "utf8mb4"),
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=5,
        read_timeout=10,
        write_timeout=10,
    )


@contextmanager
def get_conn():
    conn = pymysql.connect(**_db_kwargs())
    try:
        yield conn
    finally:
        conn.close()



# ─────────────────────────────────────────────────────────────
# (선택) SQS 상태관리용 jobs 테이블 CRUD
# - 이건 테이블이 DB에 존재해야 동작함 (DB팀이 만들어주면 OK)
# ─────────────────────────────────────────────────────────────
def insert_job_pending(job_id: str, upload_s3_key: str, original_name: str) -> None:
    sql = """
    INSERT INTO jobs (job_id, upload_s3_key, original_name, status)
    VALUES (%s, %s, %s, %s)
    """
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (job_id, upload_s3_key, original_name, "PENDING"))


def update_job_status(job_id: str, status: str | None = None, error_message: str | None = None) -> None:
    """
    SQS(Standard)는 중복 메시지가 올 수 있어서 멱등 처리 권장:
    - 이미 DONE이면 다시 덮어쓰지 않도록 가드
    """
    sql = """
    UPDATE jobs
       SET status=%s,
           error_message=COALESCE(%s, error_message)
     WHERE job_id=%s
       AND status <> 'DONE'
    """
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (status, error_message, job_id))

def update_job_results(
    job_id: str,
    status: str,
    result_json_key: str | None = None,
    result_html_key: str | None = None,
    result_mp4_key: str | None = None,
    error_message: str | None = None,
) -> None:
    """
    분석 완료/실패 결과를 jobs 테이블에 반영.
    - SQS(Standard)는 중복 메시지가 올 수 있으니 멱등 처리(이미 DONE이면 덮어쓰기 방지) 권장
    """
    sql = """
    UPDATE jobs
       SET status=%s,
           result_json_key=COALESCE(%s, result_json_key),
           result_html_key=COALESCE(%s, result_html_key),
           result_mp4_key=COALESCE(%s, result_mp4_key),
           error_message=COALESCE(%s, error_message)
     WHERE job_id=%s
       AND status <> 'DONE'
    """
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (
                    status,
                    result_json_key,
                    result_html_key,
                    result_mp4_key,
                    error_message,
                    job_id,
                ),
            )
        



def get_job(job_id: str) -> dict | None:
    sql = "SELECT * FROM jobs WHERE job_id=%s LIMIT 1"
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (job_id,))
            return cur.fetchone()
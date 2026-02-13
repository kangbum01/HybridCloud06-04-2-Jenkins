import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 20 },   // 20 VU까지 램프업
    { duration: '1m', target: 20 },    // 유지
    { duration: '30s', target: 0 },    // 램프다운
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],    // 실패율 1% 미만
    http_req_duration: ['p(95)<500'],  // 95%가 500ms 미만 (원하면 조정)
  },
};

export default function () {
  const url = 'http://beat-dev-alb-1975505467.ap-northeast-2.elb.amazonaws.com/';
  const res = http.get(url);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}

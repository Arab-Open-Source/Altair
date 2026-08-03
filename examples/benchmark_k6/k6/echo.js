// Altair benchmark - no-DB echo load.
//
// GETs /health on {BASE_URL} - exercises the HTTP/scheduler layer only,
// isolating it from the DB pool/record path.
import http from "k6/http";
import { check } from "k6";

const VUS = Number(__ENV.VUS || 2000);
const DURATION = Number(__ENV.DURATION || 90);
const WARMUP = Number(__ENV.WARMUP || 5);

export const options = {
  scenarios: {
    ramp: {
      executor: "ramping-vus",
      startVUs: 1,
      stages: [
        { duration: `${WARMUP}s`, target: VUS },
        { duration: `${DURATION}s`, target: VUS },
        { duration: "5s", target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.005"],
  },
};

export default function () {
  const res = http.get(`${__ENV.BASE_URL}/health`);
  check(res, { "status is 200": (r) => r.status === 200 });
}
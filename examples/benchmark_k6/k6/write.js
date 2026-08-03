// Altair benchmark - write load.
//
// POSTs one row per request to {BASE_URL}/items and asserts a 201. The
// load shape (ramp-up, sustained duration, ramp-down) and VU count come
// from the environment, so the runner can reuse this script unchanged.
import http from "k6/http";
import { check } from "k6";

const VUS = Number(__ENV.VUS || 50);
const DURATION = Number(__ENV.DURATION || 30);
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

let seq = 0;

export default function () {
  seq += 1;
  const body = JSON.stringify({
    name: `bench-${__VU}-${seq}`,
    price: (seq % 1000) + 0.5,
  });
  const res = http.post(`${__ENV.BASE_URL}/items`, body, {
    headers: { "Content-Type": "application/json" },
  });
  check(res, { "status is 201": (r) => r.status === 201 });
}
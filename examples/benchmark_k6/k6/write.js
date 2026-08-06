// Altair benchmark - write load.
//
// POSTs one row per request to {BASE_URL}/items and asserts a 201.
//
// Two modes (MODE env):
//   warmup  - ramping-vus 1 -> VUS over WARMUP seconds plus a 3s settle; run
//             first so pool/prepared-statement warm-up is not part of the
//             measured summary (the single ~900ms cold-start spike lives in
//             the first seconds; see docs/architecture/performance-audit.md)
//   load    - constant-vus at VUS for DURATION seconds; the measured run.
//
// Load profile (VUS/DURATION/WARMUP) comes from the environment, so the
// runner can reuse this script unchanged.
import http from "k6/http";
import { check } from "k6";

const VUS = Number(__ENV.VUS || 1000);
const DURATION = Number(__ENV.DURATION || 60);
const WARMUP = Number(__ENV.WARMUP || 5);
const MODE = __ENV.MODE || "load";

const scenarios = {};
if (MODE === "warmup") {
  scenarios.load = {
    executor: "ramping-vus",
    startVUs: 1,
    stages: [
      { duration: `${WARMUP}s`, target: VUS },
      { duration: "3s", target: VUS },
    ],
  };
} else {
  scenarios.load = {
    executor: "constant-vus",
    vus: VUS,
    duration: `${DURATION}s`,
  };
}

export const options = {
  scenarios,
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

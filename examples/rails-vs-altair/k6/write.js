// Rails vs Altair — WRITE workload.
//
// POSTs one row per request to {BASE_URL}/items and asserts a 201. Same tiered
// VU ramp as the read script: 500 -> 1000 -> 2000 concurrent clients, holding
// each level TIER_HOLD seconds. The per-VU seq counter means every request
// inserts a fresh row (ids never collide across iterations).
import http from "k6/http";
import { check } from "k6";

const TIER_HOLD = Number(__ENV.TIER_HOLD || 60);
const TIER1 = Number(__ENV.TIER1 || 500);
const TIER2 = Number(__ENV.TIER2 || 1000);
const TIER3 = Number(__ENV.TIER3 || 2000);

export const options = {
  scenarios: {
    ramp: {
      executor: "ramping-vus",
      stages: [
        { duration: "10s", target: TIER1 },
        { duration: `${TIER_HOLD}s`, target: TIER1 },
        { duration: "15s", target: TIER2 },
        { duration: `${TIER_HOLD}s`, target: TIER2 },
        { duration: "15s", target: TIER3 },
        { duration: `${TIER_HOLD}s`, target: TIER3 },
        { duration: "10s", target: 0 },
      ],
      gracefulRampDown: "30s",
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
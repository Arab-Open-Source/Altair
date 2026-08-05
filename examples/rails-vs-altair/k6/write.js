// Rails vs Altair — WRITE workload.
//
// POSTs one row per request to {BASE_URL}/items and asserts a 201. Each
// virtual user pauses THINK_MS between requests (default 100 ms), so the load
// represents paced users rather than a closed loop that saturates the
// connection pool. Same tiered VU ramp as the read script: 500 -> 1000 ->
// 2000 concurrent clients, holding each level TIER_HOLD seconds. The per-VU
// seq counter means every request inserts a fresh row (ids never collide
// across iterations).
import http from "k6/http";
import { check, sleep } from "k6";

// Simulated think time between a virtual user's requests, in milliseconds.
// Each VU paces itself: one request every (THINK_MS + request duration), so
// the pool is exercised at a realistic user load instead of a saturated queue.
const THINK_MS = Number(__ENV.THINK_MS || 100);
const RAMP_S = Number(__ENV.RAMP_S || 3);
const TIER_HOLD = Number(__ENV.TIER_HOLD || 5);
const TIER1 = Number(__ENV.TIER1 || 500);
const TIER2 = Number(__ENV.TIER2 || 1000);
const TIER3 = Number(__ENV.TIER3 || 2000);

export const options = {
  scenarios: {
    ramp: {
      executor: "ramping-vus",
      stages: [
        { duration: `${RAMP_S}s`, target: TIER1 },
        { duration: `${TIER_HOLD}s`, target: TIER1 },
        { duration: `${RAMP_S}s`, target: TIER2 },
        { duration: `${TIER_HOLD}s`, target: TIER2 },
        { duration: `${RAMP_S}s`, target: TIER3 },
        { duration: `${TIER_HOLD}s`, target: TIER3 },
        { duration: `${RAMP_S}s`, target: 0 },
      ],
      gracefulRampDown: "5s",
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
  sleep(THINK_MS / 1000);
}
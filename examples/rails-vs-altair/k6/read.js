// Rails vs Altair — READ workload.
//
// GETs a random seeded row (ids 1..10000) from {BASE_URL}/items/:id and
// asserts a 200. Each virtual user pauses THINK_MS between requests (default
// 100 ms), so the load represents paced users rather than a closed loop that
// saturates the connection pool. The VU count ramps through three tiers —
// 500, then 1000, then 2000 concurrent clients — holding each level for
// TIER_HOLD so both the median and the tail are measured at each concurrency.
import http from "k6/http";
import { check, sleep } from "k6";

const PAGES = 10000;
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

export default function () {
  const id = Math.floor(Math.random() * PAGES) + 1;
  const res = http.get(`${__ENV.BASE_URL}/items/${id}`);
  check(res, { "status is 200": (r) => r.status === 200 });
  sleep(THINK_MS / 1000);
}
// Rails vs Altair — READ workload.
//
// GETs a random seeded row (ids 1..10000) from {BASE_URL}/items/:id and
// asserts a 200. The virtual-user load ramps through three tiers — 500, then
// 1000, then 2000 concurrent clients — holding each level for TIER_HOLD so
// both the median and the tail are measured at each concurrency.
import http from "k6/http";
import { check } from "k6";

const PAGES = 10000;
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

export default function () {
  const id = Math.floor(Math.random() * PAGES) + 1;
  const res = http.get(`${__ENV.BASE_URL}/items/${id}`);
  check(res, { "status is 200": (r) => r.status === 200 });
}
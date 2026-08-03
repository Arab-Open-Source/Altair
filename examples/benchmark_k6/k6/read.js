// Altair benchmark - read load.
//
// GETs a random seeded row (ids 1..10000) from {BASE_URL}/items/:id and
// asserts a 200. Run after scripts/seed.sh has populated the tables.
import http from "k6/http";
import { check } from "k6";

const PAGES = 10000;
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
  const id = 1 + Math.floor(Math.random() * PAGES);
  const res = http.get(`${__ENV.BASE_URL}/items/${id}`);
  check(res, { "status is 200": (r) => r.status === 200 });
}
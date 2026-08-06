// Altair benchmark - read load.
//
// GETs a random seeded row (ids 1..10000) from {BASE_URL}/items/:id and
// asserts a 200. Run after scripts/seed.sh has populated the tables.
//
// Two modes (MODE env), mirroring write.js:
//   warmup - ramping-vus 1 -> VUS over WARMUP seconds plus a 3s settle
//   load   - constant-vus at VUS for DURATION seconds (the measured run)
import http from "k6/http";
import { check } from "k6";

const PAGES = 10000;
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

export default function () {
  const id = 1 + Math.floor(Math.random() * PAGES);
  const res = http.get(`${__ENV.BASE_URL}/items/${id}`);
  check(res, { "status is 200": (r) => r.status === 200 });
}

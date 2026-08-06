// Hello World load test — compares Go vs Altair on a plain text endpoint.
//
// Profile: 1000 virtual users, 100ms sleep between requests, 2 minutes each.
// Each VU fires GET / as fast as the 100ms sleep allows.
//
// Usage:
//   k6 run -e BASE_URL=http://127.0.0.1:4201 k6/hello.js
//   k6 run -e BASE_URL=http://127.0.0.1:4202 k6/hello.js
//
// Or use run.sh which runs both sequentially and exports summaries.
import http from "k6/http";
import { check, sleep } from "k6";

const VUS = Number(__ENV.VUS || 1000);
const DURATION = Number(__ENV.DURATION || 120);
const SLEEP = Number(__ENV.SLEEP || 0.1);

export const options = {
  scenarios: {
    constant: {
      executor: "constant-vus",
      vus: VUS,
      duration: `${DURATION}s`,
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.005"],
    http_req_duration: ["p(95)<500"],
  },
};

export default function () {
  const res = http.get(`${__ENV.BASE_URL}/`);
  check(res, {
    "status is 200": (r) => r.status === 200,
    "body is Hello, World!": (r) => r.body === "Hello, World!",
  });
  sleep(SLEEP);
}

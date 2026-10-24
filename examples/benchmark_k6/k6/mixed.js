// Altair benchmark - mixed realistic load.
//
// Every iteration picks 80% read / 20% write, the way a real CRUD service
// actually skews. Reads GET a random seeded row; writes POST a new item.
// Run the seed once before starting, then leave the table alone — the
// mixed run exercises both paths against live data.
//
//   k6 run -e BASE_URL=http://127.0.0.1:4103 -e VUS=100 -e DURATION=60 k6/mixed.js
import http from "k6/http";
import { check, sleep } from "k6";

const PAGES = 10000;
const READ_RATIO = Number(__ENV.READ_RATIO || 0.8);
const VUS = Number(__ENV.VUS || 100);
const DURATION = Number(__ENV.DURATION || 60);
const THINK = Number(__ENV.THINK || 0);

export const options = {
  scenarios: {
    load: {
      executor: "constant-vus",
      vus: VUS,
      duration: `${DURATION}s`,
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.005"],
  },
};

export default function () {
  if (Math.random() < READ_RATIO) {
    const id = 1 + Math.floor(Math.random() * PAGES);
    const res = http.get(`${__ENV.BASE_URL}/items/${id}`);
    check(res, { "read is 200": (r) => r.status === 200 });
  } else {
    const payload = JSON.stringify({
      name: `mix-${__VU}-${Math.floor(Math.random() * 1e9)}`,
      price: (Math.random() * 1000).toFixed(2),
    });
    const res = http.post(`${__ENV.BASE_URL}/items`, payload, {
      headers: { "Content-Type": "application/json" },
    });
    check(res, { "write is 201": (r) => r.status === 201 });
  }
  if (THINK > 0) sleep(THINK);
}

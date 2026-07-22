// Realistic load test against the actual /watermark endpoint, as opposed
// to the synthetic /stress-* endpoints. Run from your laptop against the
// public ALB URL, or from a Job inside the cluster against the Service.
//
// Install k6: https://k6.io/docs/get-started/installation/
// Run:        k6 run --vus 20 --duration 2m k6-load-test.js -e TARGET=http://<alb-dns-name>

import http from "k6/http";
import { check, sleep } from "k6";

const TARGET = __ENV.TARGET || "http://watermark-app.watermark.svc.cluster.local";

// A tiny valid PNG, base64-encoded, used as the upload payload.
const TINY_PNG_B64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";

export const options = {
  stages: [
    { duration: "30s", target: 20 },
    { duration: "60s", target: 50 }, // ramp hard enough to push p95 latency up
    { duration: "30s", target: 0 },
  ],
};

export default function () {
  const imageBytes = http.file(
    Uint8Array.from(atob(TINY_PNG_B64), (c) => c.charCodeAt(0)),
    "test.png",
    "image/png"
  );

  const res = http.post(`${TARGET}/watermark`, { image: imageBytes });
  check(res, { "status is 200": (r) => r.status === 200 });

  sleep(0.1);
}

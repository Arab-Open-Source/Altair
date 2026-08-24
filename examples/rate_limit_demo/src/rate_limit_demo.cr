# Rate Limit Demo — a working Altair application with rate limiting.
#
# Demonstrates the sliding-window rate limiter with both memory and Redis
# backends, per-path rules, and trusted proxy handling. Run from this
# directory:
#
# ```
# crystal run src/rate_limit_demo.cr
# ```
#
# then open http://localhost:3000 — the pages controller answers with
# rate-limit headers. Try:
#
# ```
# # Global limit: 100/minute, login: 5/minute, api: 30/minute
# curl -i localhost:3000/
# curl -i localhost:3000/login
# curl -i localhost:3000/api/data
# curl -i localhost:3000/free
#
# # Hit the login limit (6th request gets 429):
# for i in $(seq 1 6); do curl -s -o /dev/null -w "%{http_code}\n" localhost:3000/login; done
#
# # With Redis (shared across processes):
# # ALTAIR_REDIS_URL=redis://localhost:6379 crystal run src/rate_limit_demo.cr
# ```
require "altair"
require "./config/application"
require "./app/controllers/application_controller"
require "./app/controllers/pages_controller"

RateLimitDemo.run!

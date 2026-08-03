# Puma config for the benchmark. The runner passes one worker per host CPU
# (BENCH_WORKERS) and BENCH_THREADS threads per worker, with the Active Record
# pool sized the same in config/database.yml. CRuby's GVL means threads help
# I/O-bound throughput only up to a point; the pool in the runner keeps the DB
# budget at the same 200 Altair is granted.
threads_count = ENV.fetch("BENCH_THREADS", "5")
threads threads_count.to_i, threads_count.to_i

workers ENV.fetch("BENCH_WORKERS", "1").to_i if ENV["BENCH_WORKERS"].to_i > 1
preload_app!

port ENV.fetch("PORT", 4201)
environment ENV.fetch("RAILS_ENV", "production")
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
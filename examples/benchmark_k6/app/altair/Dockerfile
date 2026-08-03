# Altair benchmark image. Build context is the Altair repo root so the
# path dependency in shard.yml resolves; see docker-compose.yml.
FROM crystal:1.21.0
WORKDIR /repo
COPY . .
WORKDIR /repo/examples/benchmark_k6/app/altair
RUN shards install --production
RUN crystal build --release --no-debug src/bench.cr -o /usr/local/bin/bench
EXPOSE 4000
CMD ["bench"]
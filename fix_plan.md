# Altair Performance Remediation Plan

This plan is intended for an AI agent tasked with fixing latency and tail-latency issues in Altair while preserving existing framework behavior and without sacrificing safety or durability for better benchmark numbers.

## 0. Mandatory Working Rules

Before making any changes:

1. Read `AGENTS.md` in full and adhere to it.
2. Run `git status --short` and `git diff --stat` and record any existing changes.
3. Local changes exist under `examples/benchmark_k6` along with their results. Do not delete them and do not perform an unintended reset or overwrite.
4. Do not modify benchmark files while fixing the framework unless the current step explicitly requires it, and document the reason for every modification.
5. Do not use README measurements or historical results as a baseline. Create a new baseline from an explicit commit, preserving the configuration, Crystal version, and results for every run.
6. Do not interpolate SQL values. All values must remain as bind parameters and all identifiers must go through `quote_identifier`.
7. Do not silently change the semantics of callbacks, transactions, or durability. Any behavioral change requires a spec, a `CHANGELOG.md` entry, and documentation.
8. A benchmark is not considered successful if the average improves while p99 or p99.9 regresses.

## 1. Baseline and Initial Verification

### 1.1 Preserve the Baseline

Execute and persist the output outside of git or in a temporary file:

```bash
git status --short
git diff --stat
crystal --version
crystal tool format --check src spec examples
crystal spec
```

If `crystal spec` fails due to cache or a compiler environment issue:

- Try a cache under `/tmp`.
- Record the full error and the version.
- Run targeted specs where possible.
- Do not attribute test failures to the framework before isolating the environmental cause.

### 1.2 Functional Baseline

Run at minimum:

- All `record` specs.
- `spec/record/connection_spec.cr`.
- `spec/record/permit_gate_spec.cr`.
- `spec/concurrency/semaphore_spec.cr`.
- Controller/server integration specs.
- The PostgreSQL contract suite if `ALTAIR_TEST_PG_URL` is available.

Record the number of examples, pending cases, and execution time.

### 1.3 Explainable Performance Baseline

Add temporary tooling or instrumentation, then measure each workload in isolation:

- `/health` without DB.
- `GET` by primary key.
- Simple `POST` insert.
- Simple update.
- Simple delete.
- Write with validation.
- Write with callbacks.
- Delete with `dependent: :destroy` and `:delete_all`.
- SQLite and PostgreSQL independently.

For each workload, record:

- Throughput.
- p50, p90, p95, p99, p99.9, and max.
- Failed requests and timeouts.
- Pool open / idle / in-flight counts.
- Checkout wait time.
- SQL execution time.
- Request parsing and rendering time.
- CPU, RSS, and GC metrics where available.

## 2. Phase 1: Make Latency Measurable

Do not start micro-optimizations before delay sources are separable.

### 2.1 Separate Checkout Time from SQL Time

Enhance instrumentation in `Altair::Record::Connection` to expose at least:

- Checkout wait time.
- Statement execution time within the connection.
- Result decoding / reading time.
- Transaction begin / commit / rollback time.
- Adapter name and operation type (`query`, `insert`, `update`, `delete`).

Maintain compatibility with `on_query` where possible. If a new API is required, add a separate API such as `on_query_event` instead of breaking existing consumers.

The query timer must not start before pool checkout, and pool wait time must not be reported as "SQL duration".

### 2.2 Measure Failures and Timeouts

Every event must record completion or failure in an `ensure` block, without logging sensitive values or bind parameters.

Add tests that prove:

- The hook fires on success.
- The hook fires on exception.
- Checkout wait is not included in SQL duration.
- A transaction accounts for checkout exactly once.
- No connection or permit leak occurs on exception.

### 2.3 Pool Metrics

Expose or instrument:

- Open connections.
- Idle connections.
- In-flight connections.
- Pool limit.
- Number of waiters where feasible.
- Number of pool timeouts.
- Number of gate timeouts.

Metrics must be optional and must not add allocations or clock reads on the default path when disabled.

## 3. Phase 2: Timeouts and Backpressure

### 3.1 Actually Enforce `db_query_timeout`

`config.db_query_timeout` currently exists but is not enforced. Fix it in an adapter-aware way:

- PostgreSQL: Apply a statement timeout per connection or per transaction in a way that does not taint the next connection consumer, and handle reset on release.
- SQLite: Distinguish between query timeout and busy timeout. Do not claim that a busy timeout stops a general query; apply only what the driver actually supports, or raise a clear configuration error if the option is not enforceable for a given adapter.
- Do not use a thread that arbitrarily kills a query and leaves the connection in an invalid state.
- On timeout, close or discard the connection if the driver may leave the transaction or protocol in an unsafe state.

Add specs for:

- A query that exceeds the timeout.
- Connection returned to the pool after a timeout.
- Transaction rollback after a timeout.
- A timeout cannot leave the connection as `idle in transaction`.
- PostgreSQL contract spec when PostgreSQL is available.

### 3.2 Checkout Deadline

Separate:

- The pool's `db_checkout_timeout`.
- The admission gate wait timeout.
- The overall request deadline.

Add explicit configuration, e.g. `db_admission_timeout` or equivalent, so a request does not wait indefinitely inside the FIFO gate.

When a deadline is exceeded:

- Release any acquired permit.
- Do not enter the pool if the deadline has elapsed.
- Return an exception that can be mapped to 503/429 per a documented policy.
- Do not log sensitive bodies or headers.

### 3.3 Fix `PermitGate` Semantics

Review `PermitGate` and `Semaphore` and define a clear contract:

- The gate must actually bound active DB work.
- A limit larger than the pool must not be silently meaningless. Either apply a documented clamp or add boot-time validation that fails fast.
- The queue may be FIFO, but do not claim bounded latency without a timeout.
- Swapping the semaphore while requests are in flight must not lose permits or stall fibers.
- Add tests for cancellation / timeout, exceptions, and concurrent reconfiguration.

Do not make the admission gate global across different applications or databases if that conflates capacities; review global class state and add clear ownership.

## 4. Phase 3: Remove Internal Contention

### 4.1 Fix `Altair::Record.connection`

Implement a fast path that does not take a mutex after initialization:

- Fast read of the already-initialized connection.
- Mutex only on first creation or on close / reopen.
- Safe double-checked initialization on first touch.
- No use of a value that may become dangling after `close_connection`.

Add specs for:

- Concurrent first-touch initialization opens exactly one pool.
- Hundreds of fibers obtain the same connection / pool object.
- Close followed by reopen does not race.
- Transactions are unaffected.

Measure mutex operations before and after under a highly concurrent workload.

### 4.2 Review Other Locks

Review:

- Transaction maps.
- N+1 detector.
- Query handlers.
- Checkout handlers.
- Pool mutex inside `crystal-db`.

Do not remove synchronization from mutable state. The goal is to reduce lock scope, not to hide a race condition.

## 5. Phase 4: Prepared Statements and SQL Path

### 5.1 Real PostgreSQL Prepared Statements

Verify the capabilities of the current `lib/pg` / `crystal-pg` driver. Implement named prepared statements per physical connection with:

- A stable, safe name derived from the query fingerprint.
- A bounded cache or a clear eviction policy.
- Invalidation on connection reconnect.
- No sharing of statements across physical connections.
- A safe fallback when the query is dynamic or the driver does not support it.

Do not make every SQL string variable solely due to differing placeholder counts unless necessary.

Add tests or protocol-level verification proving that a repeated query does not send a full Parse / Describe on every execution, where the driver allows it.

Compare:

- Statement cache off.
- Current default behavior.
- Named prepared cache.

Compare throughput and p99, not just the average.

### 5.2 Reduce SQL Generation and Allocations

In model macros:

- Keep INSERT SQL as stable as possible and generate it at compile time.
- Cache quoted table / column names.
- Do not rebuild identical placeholder lists on every request.
- Preserve dirty tracking for UPDATE.
- Do not weaken bind safety.

Add a small benchmark for the `create` and `update` paths that measures allocations where possible.

## 6. Phase 5: Fix the Write Path

### 6.1 Parse JSON Once

Update `HTTP::Request` and the controller API so that:

- JSON is parsed lazily or at most once.
- Controllers consume `request.json` or a typed body accessor.
- JSON scalars are not coerced to strings unless the application explicitly accesses `params`.
- Malformed JSON produces documented, consistent behavior.

Add specs proving:

- JSON parsing occurs once.
- Nested JSON remains accessible.
- Form params are unaffected.
- Precedence among route / query / form / JSON params is unchanged.

### 6.2 Uniqueness Validation

Improve validation so that:

- It is documented as an optimization, not a guarantee.
- It suggests or verifies a unique index in the schema.
- It does not execute a query when the value is unchanged on update.
- It benefits from a stable prepared statement.
- It handles a constraint violation as an appropriate validation outcome.

Add a spec for skipping the uniqueness query on a no-op update, and a race spec for two records on PostgreSQL.

### 6.3 Transaction Overhead

Review the policy for each operation:

- Plain insert / update without callbacks: a single statement where possible.
- Plain delete without callbacks or dependent behavior: no extra transaction if that is safe.
- Callbacks and dependent behavior: preserve atomicity.
- Do not let a callback open an unnecessary nested transaction.

Add query-count specs for each path while preserving rollback semantics.

### 6.4 Dependent Deletion

Preserve `dependent: :destroy` callback semantics, but improve the remaining cases:

- `:delete_all`: a single bulk DELETE.
- `:nullify`: a single bulk UPDATE.
- `:destroy`: document and measure the per-child cost.
- Avoid a savepoint per child when a parent transaction already exists and the destroy callback can execute without an additional transaction wrapper.
- Add protection for a parent with thousands of children, with instrumentation that exposes the amplification.

## 7. Phase 6: SQLite Write Path

### 7.1 Writer Admission

Add an explicit policy for SQLite:

- An option such as `db_max_active_writes` or equivalent.
- A conservative default that does not allow unbounded writer contention.
- No unnecessary blocking of reads when WAL is in use.
- No optimization that silently reduces durability.

### 7.2 Durability and PRAGMA Configuration

Make critical options configurable, such as:

- `journal_mode`.
- `synchronous`.
- `busy_timeout`.
- WAL checkpoint policy.

Defaults must remain safe and documented. Add adapter specs that assert the actual applied values, not just the configuration.

### 7.3 SQLite Tests

Test:

- Concurrent writes.
- Read / write concurrency under WAL.
- Busy timeout.
- Writer timeout.
- Connection cleanup after an SQLite error.
- No unexpected `SQLITE_BUSY` under bounded load.

## 8. Phase 7: Pool Sizing and General HTTP Latency

### 8.1 Pool Defaults

Review the relationship between:

- `db_initial_pool_size`.
- `db_max_idle_pool_size`.
- `db_max_pool_size`.

Do not present `max_idle=2` with `max_pool=10` as a warm pool without measurement evidence. Either make max idle close to max pool for sustained workloads, or document that reaping is intentional and provide a configuration profile for burst workloads.

Add a pool-churn benchmark that measures connection opens / closes per minute.

### 8.2 Request Logger

Make request logging capable of:

- Being disabled in production.
- Sampling.
- Using a distinct log level for health checks.
- Not stalling request fibers due to a slow sink.

Add a `/health` benchmark with the logger enabled vs. disabled.

### 8.3 Static Middleware

Improve static serving so that it:

- Does not read the entire file into memory.
- Uses streaming or a sendfile-compatible path.
- Adds cache headers and ETag where appropriate.
- Does not hit the filesystem on every API request when the static path prefix is known.

Add benchmarks for small and large files with p99 and RSS.

### 8.4 Request Body Handling

Do not read or parse the body beyond what the route requires. Preserve max body size and chunked-request protection. Add tests that the body is not consumed twice.

## 9. Correctness and Regression Testing

Every fix requires a spec before or alongside the fix. The suite must cover:

- Connection initialization races.
- Connection close / reopen races.
- Checkout timeout.
- Query timeout.
- Gate timeout and permit release.
- Query timing separation.
- Query hooks on failure.
- PostgreSQL named preparation.
- Single JSON parse.
- No-op update.
- Uniqueness / index behavior.
- Callback transaction rollback.
- Dependent deletion.
- SQLite concurrent writes.
- Static streaming.
- Logger disabled / sampled.

After each phase, run:

```bash
crystal tool format --check src spec examples
crystal spec
crystal run lib/ameba/bin/ameba.cr -- src spec examples --format silent
```

Run the PostgreSQL contract suite with `ALTAIR_TEST_PG_URL`. Do not treat its pending state as full success for the PostgreSQL path.

## 10. Final Benchmark Protocol

Establish a fixed benchmark matrix:

### Workloads

- Health / no DB.
- PostgreSQL read.
- PostgreSQL single-row insert.
- PostgreSQL update.
- PostgreSQL delete.
- SQLite read.
- SQLite write.
- Validation write.
- Callback write.
- Large cascade delete.

### Configurations

- Small pool.
- Medium pool.
- Large pool.
- Admission gate off.
- Gate equal to pool.
- Gate smaller than pool.
- Prepared cache off / current.
- Prepared cache on.
- Logger / static enabled.
- Logger / static disabled.

### Protocol

- Same commit and same binary for every run.
- Same CPU / memory limits.
- PostgreSQL separate from the host where possible.
- Separate warm-up phase excluded from final percentiles.
- Fixed sustained phase.
- At least five runs per configuration.
- Report median and range across runs.
- Do not compare locally modified applications without recording the change.
- Preserve raw k6 JSON, server logs, and DB metrics.

### Acceptance Targets

Do not use absolute numbers before establishing a baseline, but the following must hold:

- No query exceeds the configured timeout and holds the pool indefinitely.
- No gate waiter waits without a deadline.
- No connection leak after a query / transaction timeout or exception.
- p99 and p99.9 improve under pool saturation compared to the baseline.
- Write p99 does not regress under normal load.
- SQLite does not collapse into busy / timeout under the supported load.
- No throughput regression outside the agreed margin.
- All specs, formatter, and Ameba checks are green.

## 11. Documentation and Delivery

Update:

- `CHANGELOG.md` under `[Unreleased]`.
- `docs/architecture/performance-audit.md`, clearly separating historical findings from findings that have actually been closed.
- Record and configuration documentation.
- The benchmark README so that it matches the actual scripts and results.

At the end of execution, deliver a report containing:

1. List of modified files.
2. Each issue and whether it was fixed or deferred, with rationale.
3. Before / after for p50 / p95 / p99 / p99.9 / max.
4. Query count, checkout wait, and SQL time.
5. Number of open connections and connection churn.
6. SQLite and PostgreSQL results separately.
7. Test commands and their outputs.
8. Any environmental constraints or pending specs.

The task is not considered complete once specs pass; measurements must demonstrate that tail latency is now predictable and that the write path no longer holds the pool or adds unnecessary round trips.

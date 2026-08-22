# Development console

The development server prints a boxed banner once at boot and one aligned line per request. The banner and the log are designed to be scanned — methods and status codes are colored, slow requests are highlighted, and everything adapts to the terminal.

## Boot banner

On `altair server` the console shows:

```
╭──────────────────────────────────────────────╮
│                Altair v0.2.2                 │
├──────────────────────────────────────────────┤
│ Environment   Development                    │
│ Address       http://localhost:3000          │
│ PID           15244                          │
│ Routes        5                              │
│ Middleware    5                              │
│ Crystal       1.21.0                         │
│ Started in    12.3ms                         │
╰──────────────────────────────────────────────╯
```

The banner is printed to `STDOUT` outside the log stream. `Address` shows `localhost` when the server binds to `0.0.0.0`. `Started in` measures the time from `Application#start` to the banner.

## Request log

Each request logs one line through `config.logger` (`Log.for("altair")`):

```
17:33:04  GET      /                     200    0.1ms
17:33:05  POST     /posts                201    1.2ms
17:33:06  DELETE   /posts/4              204    0.2ms
```

Columns are aligned (`method.ljust(7)`, `path.ljust(22)`, `status.rjust(3)`), so the output scans as a table. Long paths are truncated with a leading ellipsis (`…/very/long/path`).

### Colors

Methods and status codes are colored by family when the terminal supports it:

- **Methods:** GET green, POST blue, PUT yellow, PATCH magenta, DELETE red, OPTIONS cyan
- **Status:** 2xx green, 3xx blue, 4xx yellow, 5xx red

Colors auto-detect `STDOUT.tty?` and respect `NO_COLOR=1` and `TERM=dumb`. Force them on or off:

```crystal
class Blog < Altair::Application
  config.logger_colors = true  # nil = auto, true/false = forced
end
```

### Slow requests

Requests slower than `config.slow_request_threshold` (default `20.milliseconds`) are highlighted in yellow and suffixed with `[SLOW]`:

```
17:33:04  GET      /dashboard            200  124.3ms [SLOW]
```

Tune or disable the threshold:

```crystal
config.slow_request_threshold = 50.milliseconds
```

Set it to `0.milliseconds` to highlight every request, or to a large value to never highlight.

### Timestamps and counter

```crystal
config.logger_timestamps = true       # HH:MM:SS prefix (default true)
config.logger_request_counter = true  # #0001 prefix (default false)
config.logger_compact = true          # compact single-line without alignment
```

Compact mode logs `GET / 200 0.1ms` without timestamps or padding — useful when piping to a file.

### Request ID

When the `RequestId` middleware assigns an identifier, it is appended:

```
17:33:04  GET      /posts                200    0.8ms (abc-123)
```

The same identifier is echoed back in the `X-Request-Id` response header.

## Error output

On unhandled exceptions (500) the console logs a highlighted block to `STDERR` via `config.logger.error`:

```
──────────────────────────────────────────────────

500 Internal Server Error

Route
GET /users/42

Controller
UsersController#show

Exception
NilAssertionError

Message
User not found

Location
src/controllers/users.cr:42

──────────────────────────────────────────────────
```

The HTML error page is still rendered in the browser when `config.debug` is true; the console block makes the same information visible without switching context.

## Configuration reference

| Property | Default | Meaning |
|----------|---------|---------|
| `logger` | `Log.for("altair")` | Where request lines are written |
| `logger_colors` | `nil` (auto) | Console colors (`nil` = auto, `true`/`false` = forced) |
| `logger_compact` | `false` | Compact lines without alignment |
| `logger_timestamps` | `true` | `HH:MM:SS` prefix |
| `logger_request_counter` | `false` | Sequential `#0001` prefix |
| `logger_show_client_ip` | `false` | Client IP prefix (hook for future wiring) |
| `slow_request_threshold` | `20ms` | Highlight threshold |

Swap `config.logger` for a `Log` with an `IO::Memory` backend in specs to capture and assert on the output.

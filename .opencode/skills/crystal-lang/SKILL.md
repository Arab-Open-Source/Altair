---
name: crystal-lang
description: Write, review, debug, build, test, and package code in the Crystal programming language (.cr files, shard.yml, spec files). Use this skill whenever the user mentions Crystal, .cr files, shards/shard.yml, "crystal build/run/spec", Ameba, fibers/channels in a Crystal context, or asks to scaffold/fix/optimize a Crystal project — even if they just paste Crystal code without naming the language explicitly. Also use it to explain Crystal's type system, macros, concurrency model, or to migrate/port Ruby code to Crystal.
license: MIT
compatibility: opencode
metadata:
  language: crystal
  category: programming-language
  crystal_version: "1.21"
  official_docs: https://crystal-lang.org/reference/
---

# Crystal Lang

Crystal is a general-purpose, object-oriented, **statically typed** language with **Ruby-inspired syntax** that compiles to fast native code via LLVM. Think "Ruby's feel, C's speed" — most idiomatic Ruby reads as valid-looking Crystal, but the compiler enforces types (usually via inference, rarely via explicit annotations).

As of this skill's writing, the current stable release line is **Crystal 1.21** (execution contexts enabled by default, `%W` string-array literals with interpolation). Crystal ships a new minor version roughly every 3 months and minor releases are backwards-compatible, so don't assume the user is on an old version unless their `shard.yml`/`.crystal-version` says otherwise.

## When to reach for this skill

- Writing new `.cr` files, CLI tools, web services (Kemal/Lucky/Amber-style), or libraries in Crystal
- Debugging Crystal compiler errors (type inference / union / nilable errors are the most common source of confusion)
- Setting up or editing `shard.yml` and dependency management with `shards`
- Writing or running `spec/` tests
- Reviewing Crystal code for idiomatic style, safety, or performance
- Porting/translating Ruby code to Crystal (and explaining what breaks)
- Explaining macros, generics, fibers/channels, or the type system to the user

## Quick command reference

```bash
crystal init app my_project      # scaffold a new app (or `lib` for a shard/library)
crystal build src/main.cr        # compile to a binary
crystal build --release src/main.cr  # optimized release build
crystal run src/main.cr          # compile + run in one step
crystal spec                     # run the test suite (spec/ directory)
crystal spec spec/foo_spec.cr    # run a single spec file
crystal tool format              # auto-format all .cr files (like `gofmt`)
crystal tool format --check      # check formatting without writing (good for CI)
crystal docs                     # generate API docs from source comments
crystal eval 'puts 1 + 1'        # evaluate a one-liner

shards init                      # create shard.yml in an existing folder
shards install                   # resolve + install dependencies into lib/
shards build                     # build binaries defined in shard.yml `targets`
shards update                    # update dependencies and shard.lock
```

Always run `crystal tool format` on generated/edited code before presenting it, and prefer `crystal build` (not just eyeballing) to confirm code actually compiles when you have the tool available — Crystal's compiler is the ground truth, not intuition, because type inference errors are easy to get subtly wrong.

## Project layout

```
my_project/
├── shard.yml          # project manifest (name, version, deps, targets)
├── shard.lock         # locked dependency versions (commit this)
├── src/
│   └── my_project.cr  # main entry point, usually requires other files
├── spec/
│   └── my_project_spec.cr
├── lib/                # installed shards (don't commit, add to .gitignore)
└── bin/                # compiled binaries (don't commit)
```

Minimal `shard.yml`:

```yaml
name: my_project
version: 0.1.0

authors:
  - Your Name <you@example.com>

targets:
  my_project:
    main: src/my_project.cr

dependencies:
  kemal:
    github: kemalcr/kemal
    version: ~> 1.5

crystal: ">= 1.19.0"
license: MIT
```

## Language essentials

### Types & inference
Types are inferred, not usually written. Variables get their type from every assignment site the compiler can see — if a variable is assigned both an `Int32` and later a `String` in reachable code paths, its type becomes the union `(Int32 | String)`.

```crystal
name = "Crystal"        # String
age = 12                # Int32
mixed = rand < 0.5 ? 1 : "one"   # (Int32 | String)
```

Explicit type annotations are needed for: instance variables the compiler can't infer from initialization, method parameters/return types on abstract methods, and empty collection literals (`values = [] of Int32`).

### Nil safety
There is no implicit `nil`. A method/var that can be nil must be typed as a **nilable union**, written with `?`:

```crystal
def find_user(id : Int32) : User?
  # returns User or nil
end

if user = find_user(1)
  puts user.name   # `user` is narrowed to `User` here (not nil) inside this branch
end
```

The `.not_nil!`, safe navigation `&.`, and `||`/`try` are the common tools for dealing with nilable values — avoid `.not_nil!` in code you write for the user unless they've already proven non-nilness, since it raises at runtime if wrong.

### Structs vs classes
`struct` is stack-allocated, value-semantics, immutable-by-convention, cheap to copy — good for small data like `Point`. `class` is heap-allocated, reference-semantics — the default choice for most objects.

### Modules, generics, and macros — do not conflate these
- **Modules** (`module Foo`) are namespaces and mixins (`include`/`extend`), same idea as Ruby.
- **Generics** (`class Box(T)`) are ordinary compile-time type parameters, resolved once per concrete type — analogous to Rust/C++ generics/templates.
- **Macros** (`macro`, `{{ }}`, `{% %}`) run at **compile time** and generate code/AST before type-checking happens. They are Crystal's answer to Ruby's metaprogramming (which can't work at runtime the same way, since Crystal has no runtime `method_missing`/`eval`). Reach for generics first; reach for macros only when you need to generate code shapes generics can't express (e.g. defining N methods from a list of names).

### Error handling
`begin/rescue/ensure/end`, same shape as Ruby:

```crystal
begin
  risky_call
rescue ex : IO::Error
  puts "IO failed: #{ex.message}"
ensure
  cleanup
end
```

## Concurrency

Crystal uses **fibers** (green threads) with cooperative scheduling, plus channels for CSP-style communication:

```crystal
channel = Channel(Int32).new

spawn do
  channel.send(compute_something)
end

result = channel.receive
```

As of Crystal 1.21, **execution contexts** (multi-threaded fiber scheduling introduced as preview in earlier 1.x releases) are enabled by default, so fibers can now genuinely run in parallel across OS threads, not just interleaved on one — be mindful of shared mutable state and prefer channels/`Mutex` over ad-hoc locking when reviewing concurrent code.

## Testing with spec

Crystal's stdlib testing framework mirrors RSpec:

```crystal
require "spec"
require "../src/my_project"

describe MyProject do
  describe "#greet" do
    it "returns a greeting with the given name" do
      MyProject.greet("World").should eq("Hello, World!")
    end

    it "raises on empty input" do
      expect_raises(ArgumentError) do
        MyProject.greet("")
      end
    end
  end
end
```

Run with `crystal spec`. Use `.should`, `.should_not`, and matchers like `eq`, `be_true`, `be_nil`, `be_a`, `contain`.

## Style conventions

- `snake_case` for methods, local variables, files
- `PascalCase` for types (classes, modules, structs, enums)
- `SCREAMING_SNAKE_CASE` for constants
- 2-space indentation, no semicolons
- Always run `crystal tool format` rather than hand-formatting
- [Ameba](https://github.com/crystal-ameba/ameba) is the de-facto community linter (not in stdlib — it's a separate shard); suggest adding it as a dev dependency if the user wants static analysis beyond what the compiler already enforces

## Common gotchas (especially coming from Ruby)

- **No runtime `method_missing`/monkey-patch-at-runtime**: reopening a class (`class String; def shout; end; end`) works, but it's resolved at **compile time**, not dynamically per-object.
- **Union types leak into control flow**: a method returning `(A | B)` forces the caller to handle both branches (via `case`/`is_a?`/pattern narrowing) before calling a method only `A` has.
- **Everything must type-check across all code paths**, including rarely-hit branches — Crystal has no "it'll probably be fine at runtime" escape hatch the way dynamic Ruby does.
- **Empty collection literals need a type**: `[]` alone is an error; write `[] of String`.
- **Macros are not generics and not runtime reflection**: don't reach for a macro to solve something a generic or a simple method already solves.
- **Integer types are sized** (`Int32`, `Int64`, `UInt8`, ...) — overflow behavior and division semantics differ from Ruby's arbitrary-precision `Integer`; use `Int64`/`BigInt` explicitly when a Ruby port needs it.

## Dependency management with shards

Dependencies in `shard.yml` can point to GitHub/GitLab, a git URL, or a local `path:`. After editing `shard.yml`, always mention running `shards install` (or `shards update` if bumping a version) and note that `shard.lock` should be committed for applications (not usually needed to be strict for libraries, since libraries declare version ranges).

```yaml
dependencies:
  kemal:
    github: kemalcr/kemal
    version: ~> 1.5
  local_lib:
    path: ../local_lib
```

## Where to go deeper

Point the user to the official docs when a question goes beyond this skill's scope:
- Language reference: https://crystal-lang.org/reference/
- Standard library API docs: https://crystal-lang.org/api/
- Shards (package manager) docs: https://crystal-lang.org/reference/the_shards_command/
- Release notes / changelog: https://crystal-lang.org/blog/

When compiler error messages are pasted in, read them carefully — Crystal's error messages usually name the exact conflicting types and the two code locations involved, which is almost always enough to pinpoint the fix without guessing.

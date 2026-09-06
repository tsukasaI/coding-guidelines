# Go

Specializes `principles.md` for Go. Baseline: current stable Go, modules only.

## Project layout

- Follow go.dev/doc/modules/layout. Start flat: a small module SHOULD be a
  single package at the repo root. Split packages only when a boundary is real.
- Binaries live in `cmd/<name>/main.go`; one directory per binary. A module
  with a single binary and little shared code MAY keep `main.go` at the root.
- Code that must not be imported by other modules goes in `internal/`. Default
  new packages to `internal/` and promote them deliberately.
- NEVER create a `pkg/` directory. It is not part of the official layout and
  adds a meaningless path segment. (enforced: lefthook layout-ban job on the
  `pkg/**` glob; `depguard` bans import paths, not directory names, so it
  cannot catch this. See `templates/lefthook.yml.example`.)
- Package names MUST be short, lower-case, singular nouns (`order`, not
  `orders`, `orderutils`, `common`, `helpers`). Name packages after what they
  provide, not what they contain.
- NEVER stutter: `order.Service`, not `order.OrderService`. (enforced:
  `revive.var-naming`)

Ref: go.dev/doc/modules/layout; Google Go Style Guide (package names).

## Composition and dependency injection

- Constructors are plain functions: `NewServer(cfg Config, store OrderStore) *Server`.
  All wiring happens in `main` (or a `run(ctx, args)` it delegates to) — the
  composition root. No DI container, no service locator, no `init` wiring.
- Code-generated wiring (`google/wire`) MAY be considered only when the
  dependency graph is genuinely too large to wire by hand — and note that
  google/wire itself was archived in August 2025 and is unmaintained. In
  practice: restructure the graph before reaching for a tool.
- NEVER use package-level mutable state (global `var db *sql.DB`, registries
  mutated in `init`). Pass dependencies explicitly. Why: globals create hidden
  coupling and order-dependent bugs, and make parallel tests impossible.
  (enforced: `gochecknoglobals`, `gochecknoinits`)
- `context.Context` MUST be the first parameter of any function that does I/O
  or can block: `func (s *Server) Get(ctx context.Context, id ID)`. NEVER
  store a context in a struct field. (enforced: `revive.context-as-argument`,
  `containedctx`)

```go
// Bad: hidden global, wired nowhere
var store = postgres.NewStore(os.Getenv("DSN"))

// Good: composition root wires everything explicitly
func main() {
    cfg := config.Load()                    // parse env once, here
    store := postgres.NewStore(cfg.DSN)
    srv := api.NewServer(cfg.API, store)    // *Server, concrete
    log.Fatal(srv.ListenAndServe())
}
```

Ref: Google Go Style Guide "Global state"; go.dev/wiki/CodeReviewComments (contexts).

## Interfaces (ports)

- Interfaces MUST be defined in the package that *consumes* them, not the
  package that implements them. The implementing package returns concrete
  types (usually pointers to structs); callers narrow to the interface they
  need. This is the Go form of "consumer owns the port".
- Keep interfaces small — one to three methods. Compose small interfaces
  rather than growing one.
- NEVER define an interface before there is a consumer that needs the
  abstraction (a second implementation, or a test fake at a genuine seam).
  "Might need to mock it later" is not a consumer.

```go
// Bad: producer-side, exhaustive interface next to the implementation
package postgres
type Store interface { /* 14 methods mirroring the struct */ }

// Good: consumer defines exactly what it uses
package api
type OrderStore interface {
    Order(ctx context.Context, id order.ID) (order.Order, error)
    Save(ctx context.Context, o order.Order) error
}
func NewServer(cfg Config, store OrderStore) *Server { ... }
```

Ref: go.dev/wiki/CodeReviewComments#interfaces; Google Go Style Guide (interfaces).

## Domain modelling

- Wrap boundary primitives in defined types: `type UserID string`,
  `type Cents int64`. Conversions are explicit, so mixed-up arguments become
  compile errors.
- Enforce invariants in constructors that return `(T, error)`; unexported
  fields keep other packages from forging values. The zero value stays
  obtainable regardless (`var e Email`, zero-valued struct fields) — make it
  valid, or treat zero as invalid and check for it where zeros can leak in
  (decoding, forgotten field initialization).

```go
// Good: parse once at the boundary, trust the type afterwards
type Email struct{ s string }

func ParseEmail(raw string) (Email, error) {
    if !strings.Contains(raw, "@") {
        return Email{}, fmt.Errorf("parse email %q: missing @", raw)
    }
    return Email{s: raw}, nil
}
```

- Go has no sum types. Model closed variants with a small sealed interface
  (unexported method) and a type switch, or a defined constant type with
  `iota`. Do not simulate inheritance with struct embedding.

```go
// Good: sealed — only this package can add variants
type OrderState interface{ orderState() }

type Pending struct{}
type Shipped struct{ At time.Time }

func (Pending) orderState() {}
func (Shipped) orderState() {}

// Bad: exported marker method — any package can implement it,
// so a type switch over the variants can never be exhaustive
type OrderState interface{ OrderState() }
```
- Domain packages MUST NOT import `net/http`, `database/sql`, or any driver;
  adapters convert between wire/storage representations and domain types.
  (enforced: `depguard`, scoped to non-adapter packages via the `files:`
  glob in `templates/golangci.yml.example`)

## Error handling

- Errors are values. Handle every error: return it, act on it, or — rarely
  and with a comment — explicitly discard with `_`. NEVER silently drop one.
- Wrap with `%w` when adding context, so callers can use `errors.Is`/`errors.As`:
  `fmt.Errorf("load order %s: %w", id, err)`. Add context that the caller
  doesn't already have; do not repeat the callee's words. (enforced:
  `errorlint`)
- Error strings MUST be lower-case and unpunctuated (they get wrapped).
  (enforced: `revive.error-strings`)
- Expected, branchable failures get sentinel errors (`var ErrNotFound =
  errors.New("not found")`) or dedicated error types; callers branch with
  `errors.Is`/`errors.As`, NEVER by string matching. (enforced, naming only:
  `errname`; the matching discipline itself has no linter, code review still
  has to catch a stray `strings.Contains(err.Error(), ...)`)
- Translate at layer boundaries: adapters map driver errors (`sql.ErrNoRows`)
  to domain errors (`order.ErrNotFound`); transport maps domain errors to
  status codes. Driver errors MUST NOT escape the adapter.
- Handle an error exactly once. Log-and-return duplicates the failure in the
  logs and robs the caller of the decision. Return it; log at the top.
- `panic` is for programmer errors only (broken invariant, impossible branch).
  NEVER panic on bad input or I/O failure. Do not use `recover` as a general
  try/catch; a top-level HTTP handler recovery middleware is the exception.

```go
// Bad: log-and-return, no wrapping, string branching upstream
if err != nil {
    log.Printf("db error: %v", err)
    return err
}

// Good — service: wrap with context, pass the error up
func (s *Service) Get(ctx context.Context, id order.ID) (order.Order, error) {
    o, err := s.store.Order(ctx, id)
    if err != nil {
        return order.Order{}, fmt.Errorf("get order %s: %w", id, err)
    }
    return o, nil
}

// Good — HTTP handler: translate the known domain error to the protocol
o, err := svc.Get(r.Context(), id)
if errors.Is(err, order.ErrNotFound) {
    http.Error(w, "order not found", http.StatusNotFound)
    return
}
```

Ref: go.dev/blog/go1.13-errors; go.dev/wiki/CodeReviewComments (error strings,
handle errors); Google Go Style Guide (errors).

## Testing

- Test files live next to the code. Prefer the external test package
  (`package order_test`) so tests exercise only the exported API. Use the
  internal package form only for genuinely unexported algorithms. (enforced:
  `testpackage`)
- Use table-driven tests with subtests for input/output matrices:

```go
func TestParseEmail(t *testing.T) {
    tests := []struct {
        name    string
        in      string
        wantErr bool
    }{
        {"valid", "a@b.co", false},
        {"missing at", "abc", true},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            _, err := ParseEmail(tt.in)
            if gotErr := err != nil; gotErr != tt.wantErr {
                t.Fatalf("ParseEmail(%q) error = %v, wantErr %v", tt.in, err, tt.wantErr)
            }
        })
    }
}
```

- Prefer fakes (in-memory `OrderStore` with real map-backed behavior) over
  expectation-based mocks; prefer real implementations over fakes when cheap
  (real `bytes.Buffer`, real filesystem via `t.TempDir()`).
- Mark helpers with `t.Helper()`. Use `t.Cleanup` over deferred teardown in
  helpers. Use `t.Context()` for test-scoped contexts. (enforced: `thelper`)
- On failure, report the input, got, and want (`got X, want Y`). Test failures
  are for humans debugging; make them self-explanatory.
- NEVER make test order matter, and NEVER share mutable package-level state
  between tests — that is the other reason globals are banned. (enforced,
  partial: `paralleltest` and `tparallel` catch missing `t.Parallel()`, not
  the shared-state case itself; code review still has to catch that.)

Ref: Google Go Style Guide (best practices: test doubles); go.dev/wiki/TestComments.

## Tooling

- `gofumpt` MUST replace `gofmt`: a strict superset (20+ extra rules) that
  stays backwards-compatible — a `gofumpt`-formatted file always passes
  plain `gofmt` too, so adopting it is a one-time no-churn switch.
- `golangci-lint` v2 config MUST use `linters.default: none` with an
  explicit `enable:` list, not `default: all` with disables. An explicit
  list is auditable; a broad default with exclusions silently changes scope
  on every golangci-lint upgrade. `gofumpt` is a *formatter* in v2
  (`formatters.enable`), not a linter, it cannot appear in `linters.enable`.
  The full current list, including the architectural-rule linters below, is
  `templates/golangci.yml.example`.
- v2 merged `gosimple` and `stylecheck` into `staticcheck`; do not enable
  them separately. `staticcheck` does NOT default to its full check set,
  `settings.staticcheck.checks: ["all"]` must be explicit.
- `govet.settings.enable: [shadow]` catches shadowed variables, but the
  shadow analyzer is known to false-positive on common Go error-handling
  patterns (golangci-lint#1008). Keep it enabled anyway per the maximal-
  strictness stance; suppress individual false positives with
  `//nolint:govet` plus a reason (see `nolintlint` below), don't disable
  the check.
- The pre-commit hook fails on any reported issue, not just ones above a
  severity threshold, see "Maximal strictness stance" in
  `patterns/tooling.md`.
- Suppressions (`//nolint:...`) MUST carry a reason
  (`//nolint:errcheck // reason`); enforced by `nolintlint`. Ties to
  `security.md`'s suppression audit-trail rule: an unreadable-reason
  suppression cannot be reviewed or expired.

Ref: golangci-lint.run (v2 configuration model); github.com/mvdan/gofumpt;
github.com/golangci/golangci-lint/issues/1008 (govet shadow false positives).

## Anti-patterns AI agents produce in Go

1. **Interface-first cargo cult**: an interface for every struct, defined
   producer-side, with one implementation and a generated mock. Delete the
   interface; depend on the concrete type until a consumer needs a seam.
2. **Java-shaped layouts**: `pkg/`, `models/`, `services/`, `controllers/`,
   `utils/`. Go packages are named by what they provide (`order`, `postgres`,
   `api`), not by structural role.
3. **Log-and-return** (often at every layer): each error appears N times in
   logs with no decision made anywhere. Wrap with `%w` and return; log once
   at the top of the call chain.
4. **Goroutines without lifecycle**: `go func(){...}()` with no context
   cancellation, no way to wait, no error path. Every goroutine needs an
   owner: pass `ctx`, wait via `sync.WaitGroup`/`errgroup.Group`, and return
   its error.
5. **Premature `%v`/`interface{}`/`any` generics**: reaching for `any` and
   reflection (or type parameters) where a concrete type or a small interface
   works. Write the concrete version first.

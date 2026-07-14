# HTTP

Specializes `principles.md` for HTTP servers and clients. Load with the
language file for the task. API shapes are schema-first — the OpenAPI spec is
the contract and types are generated from it (`patterns/codegen.md`).

## Server

- A handler is an adapter: parse the request into domain/application types
  (schema-checked), call one application port, translate the result to the
  protocol. Handlers contain NO business rules — the test is that swapping
  HTTP for gRPC would rewrite only handlers.
- Routes are registered in the composition root; handlers get their
  dependencies as constructor/factory arguments like everything else.
- Middleware is for cross-cutting concerns only: auth extraction, request
  logging, tracing, panic/exception recovery, rate limiting. NEVER put
  domain decisions in middleware.
- Domain-error → status-code translation lives in ONE place per transport (a
  single map/function next to the handlers), not scattered per handler.
- Timeouts are explicit: set server read/header/write/idle timeouts, and give
  every request a deadline that propagates (context / AbortSignal). Defaults
  are unbounded in most stacks — unbounded is a production incident.
- Shut down gracefully: stop accepting, drain in-flight requests against a
  deadline, then exit (Go `http.Server.Shutdown`; axum
  `with_graceful_shutdown`; close the platform server handle in Node).

```go
// Good: handler = parse → port → translate
func (h *Handler) placeOrder(w http.ResponseWriter, r *http.Request) {
    draft, err := parseOrderDraft(r.Body) // schema-checked, returns domain type
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    o, err := h.checkout.Place(r.Context(), draft)
    if err != nil {
        h.writeError(w, err) // the one domain-error → status map
        return
    }
    writeJSON(w, http.StatusCreated, toOrderResponse(o))
}
```

## Client

- An HTTP client is an adapter behind a consumer-owned port. Application code
  depends on `PaymentGateway`, not on a URL or an SDK type.
- Every client sets an explicit timeout. NEVER ship a client with the
  stack's default (usually infinite) timeout.
- Responses are a boundary: check the status, parse the body against a
  schema/generated type, translate failures into the port's error values.
  NEVER cast wire data.
- Retry only idempotent requests (GET/PUT/DELETE, or POST with an idempotency
  key), with a bounded attempt count and exponential backoff plus jitter;
  honor `Retry-After`. Retrying a non-idempotent request duplicates the
  side effect.
- Propagate the caller's deadline and trace context into outgoing requests;
  a client call without a deadline can outlive the request that needed it.

## Tools

| Language | Server | Client |
|---|---|---|
| Go | `net/http` ServeMux (Go 1.22+ method+wildcard routing); reach for chi/echo only for needs ServeMux can't meet | `net/http` Client with `Timeout`; generated typed client via oapi-codegen |
| Rust | axum (tower middleware, `IntoResponse`, `with_graceful_shutdown`) | reqwest with `.timeout(..)`; generated client via progenitor |
| TypeScript | Fastify (JSON-schema-validated routes) or Hono; validation per `languages/typescript.md` boundaries | `fetch` + `AbortSignal.timeout(..)`; typed client via openapi-fetch |

Ref: go.dev/blog/routing-enhancements; docs.rs/axum; fastify.dev; hono.dev.

## Anti-patterns AI agents produce around HTTP

1. **Business logic in the handler** (or worse, middleware): inventory checks
   and pricing inline between `parse` and `write`. Handlers translate;
   applications decide.
2. **Retry-everything wrappers**: blanket retries around POSTs without
   idempotency keys — duplicated orders under load. Classify idempotency
   before adding a single retry.
3. **No timeouts anywhere**: default clients and servers with unbounded
   waits; one slow dependency stalls the fleet. Every hop gets a deadline.
4. **Transport types leaking inward**: `*http.Request`, framework context
   objects, or generated DTOs passed into application/domain code. Parse at
   the edge; pass domain types.
5. **God API client**: one hand-written `apiClient` module with a method per
   endpoint and ad-hoc types. Generate the typed client from the spec and
   wrap only what the app consumes behind its port.

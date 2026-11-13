# HTTP

Specializes `principles.md` for HTTP servers and clients. Load with the
language file for the task. API shapes are schema-first — the OpenAPI spec is
the contract and types are generated from it (`patterns/codegen.md`).

## Server

- A handler is an adapter: parse the request into domain/application types
  (schema-checked), call one application port, translate the result to the
  protocol. Handlers MUST NOT contain business rules — the test is that swapping
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

Ref: Go `http.Server` timeout fields (https://pkg.go.dev/net/http#Server) and
`Shutdown` (https://pkg.go.dev/net/http#Server.Shutdown); The complete guide
to Go net/http timeouts
(https://blog.cloudflare.com/the-complete-guide-to-golang-net-http-timeouts/);
axum `with_graceful_shutdown`
(https://docs.rs/axum/latest/axum/serve/struct.Serve.html#method.with_graceful_shutdown).
The handler-as-adapter and single error-map rules are house rules.

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

Ref: RFC 9110, idempotent methods (https://www.rfc-editor.org/rfc/rfc9110#idempotent.methods)
and Retry-After (https://www.rfc-editor.org/rfc/rfc9110#section-10.2.3);
Timeouts, retries, and backoff with jitter
(https://builder.aws.com/content/3EumjoZascWd1oZiEgL8ORlv3qE/timeouts-retries-and-backoff-with-jitter);
The Idempotency-Key HTTP Header Field, an Internet-Draft
(https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/);
Go `context` (https://pkg.go.dev/context) for deadline propagation; reqwest
`ClientBuilder::timeout`
(https://docs.rs/reqwest/latest/reqwest/struct.ClientBuilder.html); MDN
`AbortSignal.timeout()`
(https://developer.mozilla.org/en-US/docs/Web/API/AbortSignal/timeout_static).
Trace-context propagation and the consumer-owned client port are house rules.

## Tools

| Language | Server | Client |
|---|---|---|
| Go | `net/http` ServeMux (Go 1.22+ method+wildcard routing); reach for chi/echo only for needs ServeMux can't meet | `net/http` Client with `Timeout`; generated typed client via oapi-codegen |
| Rust | axum (tower middleware, `IntoResponse`, `with_graceful_shutdown`) | reqwest with `.timeout(..)`; generated client via progenitor |
| TypeScript | Fastify (JSON-schema-validated routes) or Hono; validation per `languages/typescript.md` boundaries | `fetch` + `AbortSignal.timeout(..)`; typed client via openapi-fetch |

Ref: Routing Enhancements for Go 1.22 (https://go.dev/blog/routing-enhancements);
axum (https://docs.rs/axum); Fastify (https://fastify.dev/); Hono
(https://hono.dev/).

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

# MemoryAdapter Interface (Day 1 Contract — frozen)

> **Stability**: this contract is frozen from v1.0 onward. Breaking changes require a major version bump and an adapter migration plan.

A `MemoryAdapter` is any module that curator can delegate writes and reads to. MemPalace is the default adapter. Future adapters (e.g., a team-scoped adapter for v2.3) must implement this same contract.

## Lifecycle

Every adapter MUST expose the following operations. Inputs and outputs are JSON; protocol is MCP over stdio, http, or mock.

### `ping() → {result: "pong"}`

Liveness check. MUST respond within 3 seconds or the caller treats it as unreachable.

### `search(params: {query: string, wing?: string, hall?: string, limit?: int}) → {result: Array<Drawer>}`

Semantic search. Returns up to `limit` (default 5) drawers ordered by relevance. Fields:

```json
{
  "id": "drawer-uuid",
  "wing": "wing-name",
  "hall": "hall_facts | hall_events | hall_discoveries | hall_preferences | hall_advice",
  "room": "topic-name",
  "text": "verbatim content",
  "ts": "ISO-8601",
  "metadata": {
    "device_id": "laptop-k3x7",
    "content_hash": "sha256-hex"
  }
}
```

If no results, `result` is an empty array, not null.

### `write(params: {type: string, payload: object, metadata?: object}) → {result: {id: string}}`

Store a new drawer. `type` is the curator memory type (feedback, pattern, capture, architecture_decision). `payload.text` is the required field; all other fields are adapter-specific.

`metadata` MUST include:
- `content_hash` (SHA-256 hex) — idempotency key. Second write with same hash is a no-op and returns the original `id`.
- `device_id` — string, device identifier.

If the write succeeds, the response `result.id` is a stable identifier for the drawer.

### `delete(params: {id: string}) → {result: {deleted: boolean}}`

Optional for v1. MemPalace adapter returns `{deleted: false}` if unsupported.

## Error contract

All errors are returned as `{error: {code: string, message: string}}`. Codes:

- `UNREACHABLE` — adapter process down or network partition
- `TIMEOUT` — exceeded `CURATOR_MCP_TIMEOUT` seconds
- `INVALID_PARAMS` — request malformed
- `DUPLICATE` — write attempted with existing content_hash; NOT a failure, adapter MAY return normal `result` with original id
- `INTERNAL` — adapter-specific failure

Curator treats `UNREACHABLE` and `TIMEOUT` as retryable. `INVALID_PARAMS` and `INTERNAL` are terminal (log and drop).

## Concurrency

Adapters MUST NOT assume single-writer. Two curator hooks on different devices can call `write` concurrently with different content. They MAY call `write` with the same `content_hash`; the adapter MUST deduplicate by hash.

## Namespace parameter (reserved for v2.3)

All operations accept an optional `namespace: string` parameter. In v1, the MemPalace adapter ignores it. In v2.3, a team adapter uses it to partition drawers by team. Curator always sends `namespace: null` in v1.

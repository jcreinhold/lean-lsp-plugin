# Upstream issue draft — LSP client leaks language-server workers (no `didClose` / no idle-document eviction)

Drafted for filing against [anthropics/claude-code](https://github.com/anthropics/claude-code). Not yet posted. Edit to
taste and submit; trim the plugin-specific framing if filing generically.

---

**Title:** LSP integration never closes documents (`textDocument/didClose`), leaking language-server worker processes
until OOM

**Labels:** bug, lsp

## Summary

Claude Code's LSP client appears to open documents (`textDocument/didOpen`) when it touches a file but never sends
`textDocument/didClose` when it is done, and it has no idle-document eviction. For language servers that fork one OS
process per open document, this leaks processes without bound. With the Lean language server this reached **51 leaked
`lean --worker` processes** in a single session; on a cold/failing mathlib build each worker re-elaborates from source
and holds ~2 GB resident, producing a transient **~100 GB** memory footprint and heavy swapping that degraded the whole
machine.

## Environment

- Claude Code with the LSP tool (`goToDefinition` / `hover` / `findReferences` / `documentSymbol`) over a plugin
  `lspServers` registration.
- Language server: Lean 4's server, launched via `lake serve` (the
  [`lean-lsp-plugin`](https://github.com/jcreinhold/lean-lsp-plugin)).
- macOS (also expected on Linux); large mathlib-based project (~thousands of modules).

## Why this is a client problem (root cause)

Lean's LSP watchdog forks one `lean --worker` process per opened document and reaps a worker **only** on
`textDocument/didClose`, a header change, or a crash — there is no idle eviction or worker cap by design (see
`src/lean/Lean/Server/Watchdog.lean`: the `didClose` handler is the sole non-crash reaper; there is no idle timer). This
is standard for the Lean server and is correct *if the client closes documents*. So the unbounded accumulation is
governed entirely by the client: if Claude Code does not send `didClose` (or otherwise cap/evict open documents), the
workers pile up. Other one-process-per-document servers will leak the same way.

## Reproduction

1. Open Claude Code in a large Lean/mathlib project with the Lean LSP plugin installed.
2. Have Claude navigate across many `.lean` files (hover / go-to-definition / find-references over dozens of files).
3. In another terminal, watch `ps -o pid,rss,command -ax | grep 'lean --worker'`.
4. Observe the worker count grow monotonically and never shrink, even long after a file is no longer in use. Each worker
   holds a full server environment; total RSS climbs into tens of GB (worse on a non-green build, where workers
   re-elaborate from source instead of loading cached `.olean` files).

## Expected behavior

One of:

- Send `textDocument/didClose` for documents the client is finished with, **or**
- Evict idle open documents after a threshold (send `didClose` for the least-recently-used / oldest-idle documents,
  bounding the number of concurrently open documents), **or**
- Expose a configurable cap on concurrently open LSP documents.

Any of these lets per-document language servers release resources.

## Actual behavior

Documents opened by the LSP tool are never closed; worker processes accumulate for the lifetime of the session.

## Current workaround (and why it is not enough)

The `lean-lsp-plugin` now ships a supervisor (`bin/lean-lsp-supervisor`) that wraps `lake serve`, caps each worker's
memory (`-M`), and periodically reaps idle workers in its own process subtree. This is mitigation, not a fix:

- it bounds *each* worker and reaps idle ones heuristically (by CPU inactivity), but it cannot see LSP `didOpen`/
  `didClose` traffic, so it is guessing at liveness that the client knows exactly;
- it is plugin-specific; every other one-process-per-document language server would need its own equivalent.

The clean fix is for the client to manage document lifetime.

## Pointers

- Lean watchdog source: `~/.elan/toolchains/<toolchain>/src/lean/Lean/Server/Watchdog.lean` (worker spawn on `didOpen`;
  `terminateFileWorker` only from `didClose` / header-change / crash; no idle eviction).
- Plugin mitigation: `lean-lsp-plugin` `bin/lean-lsp-supervisor` and its README section "Bounding and reaping Lean
  workers".

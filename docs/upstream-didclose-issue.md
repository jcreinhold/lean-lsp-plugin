# Upstream bug report draft — Claude Code

Filled out against Claude Code's `🐛 Bug Report` form (anthropics/claude-code). Each heading below maps to a field in
that form; copy section-for-section. Not yet posted. Confirm the environment fields (marked ⚠) before submitting.

---

## Title

```
[BUG] LSP integration never sends textDocument/didClose, leaking language-server workers until OOM
```

## Labels

`bug`

## Preflight Checklist

- [x] I have searched existing issues and this hasn't been reported yet ⚠ (re-check at submit time)
- [x] This is a single bug report
- [x] I am using the latest version of Claude Code ⚠ (confirm `claude --version` is current)

## What's Wrong?

Claude Code's LSP client opens documents (`textDocument/didOpen`) when it touches a file but never sends
`textDocument/didClose` when it is done with them, and it has no idle-document eviction. For language servers that fork
one OS process per open document, this leaks processes without bound.

With the Lean language server (`lake serve`, via the lean-lsp-plugin) this reached **51 leaked `lean --worker`
processes** in a single session. On a cold or failing build each worker re-elaborates from source and holds ~2 GB
resident, so the leak produced a transient **~100 GB** memory footprint and heavy swapping that degraded the whole
machine. The worker count grows monotonically as Claude navigates across files and never drops, even long after a file
is no longer in use.

This is a client-side problem. The Lean server reaps a per-document worker only on `didClose`, a file-header change, or
a crash — by design it has no idle eviction and no worker cap (see `Lean/Server/Watchdog.lean`: the `didClose` handler
is the only non-crash reaper). That is correct *if the client closes documents*. Since Claude Code does not, the workers
accumulate. Any one-process-per-document language server will leak the same way.

## What Should Happen?

Claude Code should bound the documents it holds open in the language server, via any of:

- send `textDocument/didClose` for documents it has finished with; or
- evict idle open documents after a threshold (close the least-recently-used ones), bounding the number open at once; or
- expose a configurable cap on concurrently open LSP documents.

Any of these lets per-document servers release their resources, so worker count and memory stay bounded.

## Error Messages/Logs

(No crash/stack trace — the symptom is unbounded resource growth. Representative `ps` output as workers accumulate:)

```shell
$ ps -o pid,rss,command -ax | grep 'lean --worker' | wc -l
51
$ ps -o pid,rss,command -ax | grep 'lean --worker'
 60123 2113344 .../bin/lean --worker file:///proj/A.lean
 60291 1987776 .../bin/lean --worker file:///proj/B.lean
 ... (49 more, none ever removed) ...
# total RSS across the leaked workers reached ~100 GB; heavy swapping (100k+ pageouts)
```

## Steps to Reproduce

1. Open Claude Code in a large Lean + mathlib project with a Lean LSP plugin installed (e.g.
   `claude plugin install lean-lsp-plugin@lean-lsp-plugin`), launched from the project root.
2. Have Claude navigate across many `.lean` files — hover / go-to-definition / find-references over dozens of files.
3. In another terminal, watch the worker processes:
   ```
   watch -n5 'ps -o pid,rss,command -ax | grep "lean --worker" | grep -v grep'
   ```
4. Observe the worker count grow monotonically and never shrink, even long after each file is no longer in use. Total
   RSS climbs into the tens of GB (worse on a non-green build, where workers elaborate from source rather than loading
   cached `.olean` files). No `textDocument/didClose` is ever sent for the navigated files.

A minimal stand-in for any project: any language server registered via a plugin `lspServers` block that spawns a child
process per opened document will show the same unbounded growth, because the leak is in document lifecycle, not in Lean.

## Claude Model

Not sure / Multiple models — the behavior is model-independent (it's in the LSP client, not the model).

## Is this a regression?

I don't know

## Last Working Version

(leave blank — not known to have worked differently)

## Claude Code Version

```
2.1.158 (Claude Code)
```

⚠ Re-run `claude --version` at submit time and update if newer.

## Platform

⚠ Set to your platform (Anthropic API / AWS Bedrock / Google Vertex AI). Not relevant to the bug.

## Operating System

macOS (also expected on Linux — the leak is in document lifecycle, not OS-specific).

## Terminal/Shell

⚠ Set to your terminal.

## Additional Information

- **Root cause pointer.** Lean watchdog source: `~/.elan/toolchains/<toolchain>/src/lean/Lean/Server/Watchdog.lean`. A
  worker is spawned on `didOpen`; `terminateFileWorker` is invoked only from the `didClose` handler, a header-change
  restart, or crash detection. There is no idle-eviction timer and no worker cap. So aggregate worker count is governed
  entirely by whether the client sends `didClose`.
- **Severity multiplier.** On a cold/red build each worker elaborates from source (~2 GB) instead of memory-mapping
  shared `.olean` files (a few hundred MB), so the leak is far worse mid-build.
- **Current workaround (and why it isn't enough).** The lean-lsp-plugin now ships a supervisor
  (`bin/lean-lsp-supervisor`, https://github.com/jcreinhold/lean-lsp-plugin) that wraps `lake serve`, caps each worker's
  memory (`-M`), and periodically reaps idle workers in its own process subtree. This is mitigation only: it cannot see
  `didOpen`/`didClose` traffic, so it guesses at liveness (by CPU inactivity) that the client knows exactly, and every
  other one-process-per-document language server would need its own equivalent. The clean fix is client-side document
  lifecycle management.

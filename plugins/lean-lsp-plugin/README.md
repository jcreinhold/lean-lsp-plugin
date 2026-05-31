# lean-lsp-plugin

A [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin that registers the **Lean 4 language server** as a
native LSP, giving Claude code intelligence on `.lean` files: hover types, go-to-definition, find-references,
diagnostics, and document symbols.

The server is Lean's own — the plugin launches it (under a small supervisor, see below) with `lake serve`, so it uses
your project's toolchain and dependencies. No separate language-server binary to install.

## Supported extensions

`.lean` → language id `lean`

## Requirements

- A Lean toolchain managed by [elan](https://github.com/leanprover/elan), so that `lake` is available. The plugin
  invokes `lake serve`.
- **`lake` must be on the `PATH` that Claude Code inherits** (not just your interactive shell). elan installs a `lake`
  shim, typically at `~/.elan/bin/lake`; make sure `~/.elan/bin` is on your login-shell `PATH`. Verify with
  `command -v lake`.
- The plugin must run with the working directory at a Lake project root (the directory containing `lakefile.toml` or
  `lakefile.lean`). Open Claude Code from the project root.

## Installation

```bash
claude plugin marketplace add jcreinhold/lean-lsp-plugin
claude plugin install lean-lsp-plugin@lean-lsp-plugin
```

Restart Claude Code so the plugin and its LSP server load. The Lean language server then attaches automatically whenever
Claude touches a `.lean` file.

## Warm the build first

Lean's server elaborates from source when object files (`.olean`) are missing, which makes the first responses slow —
especially against mathlib. Warm the cache and build once:

```bash
lake exe cache get   # if your project depends on mathlib
lake build
```

After that, LSP responses are fast because the server reads prebuilt `.olean` files.

## Bounding and reaping Lean workers

Lean's language server forks one `lean --worker` process per open document and holds it until the editor sends an LSP
`didClose` for that file. Claude Code's LSP client does not currently send `didClose` for files it has stopped using,
and Lean's server has no idle-worker eviction of its own, so workers accumulate. On a cold or failing mathlib build each
worker re-elaborates from source and can hold ~2 GB; left unbounded, dozens of leaked workers have reached ~100 GB of
memory and heavy swapping.

To contain this, the plugin does not run `lake serve` directly — it runs it under a small POSIX-`sh` supervisor
(`bin/lean-lsp-supervisor`) that:

- passes a per-worker memory ceiling (`-M`) that Lean forwards to every worker, so one runaway file fails with a memory
  error instead of exhausting the machine;
- periodically reaps `lean --worker` processes **in its own `lake serve` subtree** that have shown no CPU activity for a
  while (reaping an idle worker is safe — Lean respawns it lazily only if you query that file again);
- on shutdown (or when Claude Code closes the connection) terminates its whole subtree, so nothing is left orphaned.

The supervisor only ever touches workers it launched; a separate editor (e.g. VS Code) or another Claude session running
Lean is never affected.

Defaults are conservative and everything is overridable via environment variables:

| Variable | Default | Effect |
| --- | --- | --- |
| `LEAN_LSP_WORKER_MAX_MB` | `4096` | per-worker memory ceiling, passed as `lean --worker -M` |
| `LEAN_LSP_WORKER_JOBS` | _(unset)_ | per-worker thread cap, passed as `-j` (omitted when unset) |
| `LEAN_LSP_REAP_IDLE_SECS` | `300` | reap a worker after this many seconds with no CPU progress |
| `LEAN_LSP_REAP_INTERVAL_SECS` | `60` | how often the reaper checks |
| `LEAN_LSP_REAP_DISABLE` | `0` | set to `1` to disable idle reaping (the `-M` cap and shutdown cleanup still apply) |

This is mitigation, not a cure: the root fix is for the LSP client to send `didClose` (or evict idle documents), which
is an upstream Claude Code change. Keeping the build warm and green also helps a lot — a worker that loads prebuilt
`.olean` files sits at a few hundred MB instead of re-elaborating at gigabytes.

## Relationship to `lean-host-mcp`

This plugin is deliberately narrow: it provides standard LSP navigation and diagnostics and nothing more. For richer,
Lean-specific tooling — interactive proof state, tactic attempts, mathlib search (loogle / leansearch), premise
selection — use an MCP server such as [`lean-host-mcp`](https://github.com/jcreinhold/lean-host-mcp) alongside it. The
two are complementary: the LSP handles "where is this / what is this / what's broken," the MCP handles "what is the goal
and how do I close it."

## How it works

The plugin is one `lspServers` block in [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) plus the
supervisor script it points at:

```json
"lspServers": {
  "lean": {
    "command": "${CLAUDE_PLUGIN_ROOT}/bin/lean-lsp-supervisor",
    "args": [],
    "extensionToLanguage": { ".lean": "lean" },
    "startupTimeout": 120000
  }
}
```

Claude Code spawns the supervisor and speaks the Language Server Protocol to it over stdio; the supervisor passes that
byte stream straight through to `lake serve` (it never reads or rewrites LSP traffic) and adds only the worker bounding
and reaping described above. `lake` is still resolved via the inherited `PATH`. The long `startupTimeout` (120 s)
accommodates Lean's slow cold start.

## License

MIT — see [LICENSE](LICENSE).

# lean-lsp-plugin — developer guide

This repository is a single-plugin Claude Code marketplace. It registers the Lean 4 language server as a native LSP for
`.lean` files. It ships **no skills, agents, commands, or hooks** — the payload is one `lspServers` declaration plus a
supervisor script that the declaration launches in place of `lake` directly.

## Layout

This mirrors the official `claude-plugins-official` LSP plugins exactly (a marketplace with a `plugins/` subdirectory),
which is what makes `lspServers` actually load.

- `.claude-plugin/marketplace.json` — **load-bearing.** The `plugins[0].lspServers` block is what makes the plugin do
  anything. All metadata (version, author, category) lives in this entry. `source` points at the subdirectory
  `./plugins/lean-lsp-plugin`.
- `plugins/lean-lsp-plugin/` — the plugin directory (the `source` subtree, copied verbatim into the plugin cache, so
  `CLAUDE_PLUGIN_ROOT` resolves here): `README.md`, `LICENSE`, and `bin/`. **No `plugin.json`** (matches the official LSP
  plugins; metadata is in the marketplace entry).
- `plugins/lean-lsp-plugin/bin/lean-lsp-supervisor` — the LSP `command`. **Must live under the `source` subtree** —
  `${CLAUDE_PLUGIN_ROOT}` is the cached copy of that subtree, so a supervisor at the repo root is never bundled and the
  LSP fails with `ENOENT ... posix_spawn '.../bin/lean-lsp-supervisor'`. Runs `lake serve` and keeps its `lean --worker`
  subtree bounded (per-worker `-M` cap, idle reaping, shutdown sweep). POSIX `sh`; see its header for the why.
- `docs/upstream-didclose-issue.md` — drafted bug report for the root-cause client gap (no `didClose`).
- `Makefile` + `test/` — dev tasks and the test suite. `test/run.sh` has pure-`sh` unit tests (it sources the supervisor
  with `LEAN_LSP_SUPERVISOR_NOMAIN=1` to load its functions without launching a server) and a `lake`+ `python3`-gated
  integration smoke test (`test/lsp_smoke.py`). Not plugin payload.
- Root `README.md`, `LICENSE`, `CLAUDE.md` — repo-level docs. `AGENTS.md` symlinks here.

## Rules

- **`source` must point at the subdirectory, not `"./"`.** With a root source, `lspServers` is not registered at runtime
  (the LSP tool reports "No LSP server available for .lean"). Every official LSP plugin uses a `./plugins/<name>`
  subdirectory source; match that.
- `lspServers` lives only in `marketplace.json`, in the plugin entry. There is no `plugin.json`; do not add one carrying
  `lspServers` — that key is ignored there.
- Keep the `lspServers` config to the fields Claude Code supports: `command`, `args`, `extensionToLanguage`,
  `startupTimeout`. Other keys (`env`, `rootDir`, `rootMarkers`, `initializationOptions`) are not recognized.
- `command` is `${CLAUDE_PLUGIN_ROOT}/bin/lean-lsp-supervisor` (Claude Code substitutes the var; relative paths are not
  supported there). The supervisor still resolves `lake` via `PATH`, so the portability rule holds — do not hardcode an
  absolute path to `lake`; document the `PATH` requirement in the README. Worker-bounding policy is env-driven, not in
  `args` (keep `args` empty) so there is one source of truth.
- The supervisor must stay **stdio-transparent**: it never reads, writes, or buffers the LSP byte stream; `lake serve`
  inherits its stdin/stdout/stderr (the `<&0` redirect on the backgrounded `lake serve` is load-bearing — without it a
  non-interactive shell sends an async command's stdin to `/dev/null` and the server exits at once). It is POSIX `sh`
  (macOS ships bash 3.2): no arrays, `[[`, `=~`, or `<(…)`. After editing it, run `make lint` and `make test`
  (`make test` covers stdio transparency, `-M` propagation, idle reaping, and the shutdown sweep end-to-end).
- Keep this plugin narrow. Lean-specific proof tooling belongs in an MCP server, not here.

## Validating changes

```bash
make lint        # sh -n + shellcheck + shfmt -d on the shell sources
make test        # unit tests; integration smoke test if lake + python3 are present
make validate    # jq + claude plugin validate
# or directly:
jq empty .claude-plugin/marketplace.json
claude plugin validate .
claude plugin validate --strict .
```

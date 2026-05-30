# lean-lsp-plugin — developer guide

This repository is a single-plugin Claude Code marketplace. It registers the Lean 4
language server as a native LSP for `.lean` files. It ships **no skills, agents, commands,
or hooks** — the entire payload is one `lspServers` declaration.

## Layout

This mirrors the official `claude-plugins-official` LSP plugins exactly (a marketplace with
a `plugins/` subdirectory), which is what makes `lspServers` actually load.

- `.claude-plugin/marketplace.json` — **load-bearing.** The `plugins[0].lspServers` block
  is what makes the plugin do anything. All metadata (version, author, category) lives in
  this entry. `source` points at the subdirectory `./plugins/lean-lsp-plugin`.
- `plugins/lean-lsp-plugin/` — the plugin directory: `README.md` + `LICENSE` only. **No
  `plugin.json`** (matches the official LSP plugins; metadata is in the marketplace entry).
- Root `README.md`, `LICENSE`, `CLAUDE.md` — repo-level docs. `AGENTS.md` symlinks here.

## Rules

- **`source` must point at the subdirectory, not `"./"`.** With a root source, `lspServers`
  is not registered at runtime (the LSP tool reports "No LSP server available for .lean").
  Every official LSP plugin uses a `./plugins/<name>` subdirectory source; match that.
- `lspServers` lives only in `marketplace.json`, in the plugin entry. There is no
  `plugin.json`; do not add one carrying `lspServers` — that key is ignored there.
- Keep the `lspServers` config to the fields Claude Code supports: `command`, `args`,
  `extensionToLanguage`, `startupTimeout`. Other keys (`env`, `rootDir`, `rootMarkers`,
  `initializationOptions`) are not recognized.
- `command` stays `"lake"` (resolved via `PATH`) so the plugin is portable. Do not hardcode
  an absolute path; document the `PATH` requirement in the README instead.
- Keep this plugin narrow. Lean-specific proof tooling belongs in an MCP server, not here.

## Validating changes

```bash
jq empty .claude-plugin/marketplace.json
jq empty .claude-plugin/plugin.json
claude plugin validate .
claude plugin validate --strict .
```

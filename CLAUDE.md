# lean-lsp-plugin — developer guide

This repository is a single-plugin Claude Code marketplace. It registers the Lean 4
language server as a native LSP for `.lean` files. It ships **no skills, agents, commands,
or hooks** — the entire payload is one `lspServers` declaration.

## Layout

- `.claude-plugin/marketplace.json` — **load-bearing.** The `plugins[0].lspServers` block
  is what makes the plugin do anything. The marketplace name, the single plugin name, and
  the repo name are all `lean-lsp-plugin`; the plugin's `source` is `"./"` (repo root).
- `.claude-plugin/plugin.json` — metadata only (name, version, author, license, keywords).
  It must **not** contain `lspServers`; that key is only honored in `marketplace.json`.
- `README.md` — user-facing install and usage.
- `AGENTS.md` — symlink to this file.

## Rules

- `lspServers` lives only in `marketplace.json`. Do not move or duplicate it into
  `plugin.json` — it will not take effect there.
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

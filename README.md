# lean-lsp-plugin

A [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin that registers the
**Lean 4 language server** as a native LSP, giving Claude code intelligence on `.lean`
files: hover types, go-to-definition, find-references, diagnostics, and document symbols.

The server is Lean's own — the plugin launches it with `lake serve`, so it uses your
project's toolchain and dependencies. No separate language-server binary to install.

## Supported extensions

`.lean` → language id `lean`

## Requirements

- A Lean toolchain managed by [elan](https://github.com/leanprover/elan), so that `lake`
  is available. The plugin invokes `lake serve`.
- **`lake` must be on the `PATH` that Claude Code inherits** (not just your interactive
  shell). elan installs a `lake` shim, typically at `~/.elan/bin/lake`; make sure
  `~/.elan/bin` is on your login-shell `PATH`. Verify with `command -v lake`.
- The plugin must run with the working directory at a Lake project root (the directory
  containing `lakefile.toml` or `lakefile.lean`). Open Claude Code from the project root.

## Installation

```bash
claude plugin marketplace add jcreinhold/lean-lsp-plugin
claude plugin install lean-lsp-plugin@lean-lsp-plugin
```

Restart Claude Code so the plugin and its LSP server load. The Lean language server then
attaches automatically whenever Claude touches a `.lean` file.

## Warm the build first

Lean's server elaborates from source when object files (`.olean`) are missing, which makes
the first responses slow — especially against mathlib. Warm the cache and build once:

```bash
lake exe cache get   # if your project depends on mathlib
lake build
```

After that, LSP responses are fast because the server reads prebuilt `.olean` files.

## Relationship to `lean-host-mcp`

This plugin is deliberately narrow: it provides standard LSP navigation and diagnostics and
nothing more. For richer, Lean-specific tooling — interactive proof state, tactic attempts,
mathlib search (loogle / leansearch), premise selection — use an MCP server such as
[`lean-host-mcp`](https://github.com/jcreinhold/lean-host-mcp) alongside it. The two are
complementary: the LSP handles "where is this / what is this / what's broken," the MCP
handles "what is the goal and how do I close it."

## How it works

The entire plugin is one `lspServers` block in
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json):

```json
"lspServers": {
  "lean": {
    "command": "lake",
    "args": ["serve"],
    "extensionToLanguage": { ".lean": "lean" },
    "startupTimeout": 120000
  }
}
```

Claude Code spawns `lake serve` and speaks the Language Server Protocol to it over stdio.
The long `startupTimeout` (120 s) accommodates Lean's slow cold start.

## License

MIT — see [LICENSE](LICENSE).

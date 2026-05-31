# lean-lsp-plugin

A [Claude Code](https://docs.claude.com/en/docs/claude-code) marketplace providing a single plugin: **native Lean 4
LSP**. It registers Lean's own language server (launched with `lake serve`) so Claude gets code intelligence on `.lean`
files — hover types, go-to-definition, find-references, diagnostics, and document symbols.

The plugin lives in [`plugins/lean-lsp-plugin/`](plugins/lean-lsp-plugin/); the LSP configuration is in
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json). It runs `lake serve` under a small supervisor that
bounds per-worker memory and reaps idle `lean --worker` processes (see the plugin README for the environment-variable
knobs).

## Install

```bash
claude plugin marketplace add jcreinhold/lean-lsp-plugin
claude plugin install lean-lsp-plugin@lean-lsp-plugin
```

Restart Claude Code so the LSP server loads. See
[`plugins/lean-lsp-plugin/README.md`](plugins/lean-lsp-plugin/README.md) for requirements (the `lake`/elan `PATH`
requirement, warming the build, and the relationship to the `lean-host` MCP).

## License

MIT — see [LICENSE](LICENSE).

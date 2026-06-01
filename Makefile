# lean-lsp-plugin — developer tasks.
SH_FILES := plugins/lean-lsp-plugin/bin/lean-lsp-supervisor test/run.sh

.PHONY: help test test-unit test-integration lint fmt validate

help:
	@echo "make test              unit + integration tests"
	@echo "make test-unit         fast unit tests (no lake/python required)"
	@echo "make test-integration  integration smoke test (needs lake + python3)"
	@echo "make lint              sh -n + shellcheck + shfmt -d"
	@echo "make fmt               shfmt -w"
	@echo "make validate          jq + claude plugin validate"

test:
	@sh test/run.sh all

test-unit:
	@sh test/run.sh unit

test-integration:
	@sh test/run.sh integration

lint:
	@for f in $(SH_FILES); do sh -n "$$f" || exit 1; done; echo "sh -n: ok"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -s sh $(SH_FILES) && echo "shellcheck: clean"; \
	else echo "shellcheck: not installed (skipped)"; fi
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d $(SH_FILES) >/dev/null && echo "shfmt: clean" \
		|| { echo "shfmt: needs formatting — run 'make fmt'"; exit 1; }; \
	else echo "shfmt: not installed (skipped)"; fi

fmt:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w $(SH_FILES) && echo "shfmt -w: applied"; \
	else echo "shfmt: not installed"; exit 1; fi

validate:
	@jq empty .claude-plugin/marketplace.json && echo "jq: marketplace.json valid"
	@if command -v claude >/dev/null 2>&1; then claude plugin validate .; \
	else echo "claude CLI: not found (skipped)"; fi

#!/bin/sh
# Test runner for lean-lsp-plugin. Invoked by `make test`.
#
#   test/run.sh             unit tests + integration (integration skips without lake)
#   test/run.sh unit        fast unit tests only (no lake, no python)
#   test/run.sh integration integration smoke test only (needs lake + python3)
#
# Unit tests source bin/lean-lsp-supervisor with the NOMAIN sentinel, which loads
# its functions without starting a server, then exercise the pure logic directly.

# SC2034: SNAPSHOT/LAKE_PID/REAP_* are assigned here and read by the supervisor
# functions we source. SC1090: the source path is computed at runtime. These
# directives must precede the first command to apply file-wide.
# shellcheck disable=SC2034,SC1090
set -u

here=$(cd -- "$(dirname -- "$0")" && pwd)
repo=$(dirname -- "$here")
# CLAUDE_PLUGIN_ROOT is the installed copy of the plugin's `source` dir
# (plugins/lean-lsp-plugin), so the supervisor lives under that subtree, not the
# repo root. Mirror that here so the test exercises the real layout.
plugin_root="$repo/plugins/lean-lsp-plugin"
sup="$plugin_root/bin/lean-lsp-supervisor"

pass=0
fail=0
ok() {
	pass=$((pass + 1))
	printf 'ok   - %s\n' "$1"
}
no() {
	fail=$((fail + 1))
	printf 'not ok - %s\n' "$1"
}
eq() { # desc expected actual
	if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want [$2] got [$3])"; fi
}
is_true() { # desc cmd...
	d=$1
	shift
	if "$@"; then ok "$d"; else no "$d"; fi
}
is_false() { # desc cmd...
	d=$1
	shift
	if "$@"; then no "$d"; else ok "$d"; fi
}

unit() {
	echo "# unit (no lake required)"
	# Load the supervisor's functions only (NOMAIN stops it before launch).
	LEAN_LSP_SUPERVISOR_NOMAIN=1 . "$sup"

	# parent_of / in_our_subtree walk this synthetic tree:
	#   100 -> 200 -> 300   (200,300 are under 100)   400 -> 1   (outside)
	SNAPSHOT='PID PPID
100 1
200 100
300 200
400 1'
	eq "parent_of: child -> parent" "100" "$(parent_of 200)"
	eq "parent_of: unknown -> empty" "" "$(parent_of 999)"

	LAKE_PID=100
	is_true "in_our_subtree: direct child" in_our_subtree 200
	is_true "in_our_subtree: grandchild" in_our_subtree 300
	is_false "in_our_subtree: unrelated process" in_our_subtree 400
	is_false "in_our_subtree: pid absent from snapshot" in_our_subtree 999

	eq "idle_ticks_next: unchanged increments" "3" "$(idle_ticks_next 0:05 0:05 2)"
	eq "idle_ticks_next: changed resets" "0" "$(idle_ticks_next 0:05 0:09 2)"
	eq "idle_ticks_next: first sighting resets" "0" "$(idle_ticks_next '' 0:09 0)"

	REAP_INTERVAL_SECS=5
	REAP_IDLE_SECS=10
	is_false "reap_due: 1 tick (5s) below threshold" reap_due 1
	is_true "reap_due: 2 ticks (10s) meets threshold" reap_due 2
	is_true "reap_due: 3 ticks (15s) past threshold" reap_due 3

	STATE_FILE=$(mktemp)
	printf '200 0:05 3\n300 1:02 0\n' >"$STATE_FILE"
	eq "prev_cputime_of: recorded worker" "0:05" "$(prev_cputime_of 200)"
	eq "idle_ticks_of: recorded worker" "3" "$(idle_ticks_of 200)"
	eq "prev_cputime_of: unrecorded worker" "" "$(prev_cputime_of 999)"
	rm -f "$STATE_FILE"
}

integration() {
	echo "# integration (requires lake + python3)"
	if ! command -v lake >/dev/null 2>&1; then
		echo "ok   - SKIP integration: lake not on PATH"
		return 0
	fi
	if ! command -v python3 >/dev/null 2>&1; then
		echo "ok   - SKIP integration: python3 not found"
		return 0
	fi
	if CLAUDE_PLUGIN_ROOT="$plugin_root" python3 "$here/lsp_smoke.py"; then
		ok "integration smoke test"
	else
		no "integration smoke test"
	fi
}

case "${1:-all}" in
unit) unit ;;
integration) integration ;;
all)
	unit
	integration
	;;
*)
	echo "usage: $0 [unit|integration|all]" >&2
	exit 2
	;;
esac

echo
echo "summary: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

#!/usr/bin/env python3
# Integration smoke test for bin/lean-lsp-supervisor.
#
# Spawns the supervisor on a throwaway, mathlib-free Lake project, talks real LSP
# to it over stdio, and checks the four behaviours that matter:
#   A. stdio is transparent      — `initialize` gets a response with capabilities
#   B. the memory cap propagates — the spawned worker carries `-M`
#   C. idle workers are reaped   — an untouched worker disappears after the idle window
#   D. shutdown sweeps the tree  — SIGTERM leaves no process from the supervisor's subtree
#
# Requires `lake` (with a usable default toolchain) and python3. Exits non-zero if
# any check fails. Invoked by test/run.sh; needs CLAUDE_PLUGIN_ROOT in the env.

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

PLUGIN_ROOT = os.environ["CLAUDE_PLUGIN_ROOT"]
SUPERVISOR = os.path.join(PLUGIN_ROOT, "bin", "lean-lsp-supervisor")

results = []


def check(name, passed):
    results.append((name, bool(passed)))
    print(("ok   -" if passed else "not ok -"), name, flush=True)


def is_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def ps_rows():
    out = subprocess.run(
        ["ps", "-o", "pid,ppid,command", "-ax"], capture_output=True, text=True
    ).stdout
    rows = []
    for line in out.splitlines()[1:]:
        parts = line.split(None, 2)
        if len(parts) >= 2:
            try:
                rows.append((int(parts[0]), int(parts[1]), parts[2] if len(parts) > 2 else ""))
            except ValueError:
                pass
    return rows


def descendants(root):
    kids = {}
    for pid, ppid, _ in ps_rows():
        kids.setdefault(ppid, []).append(pid)
    seen, stack = set(), [root]
    while stack:
        for kid in kids.get(stack.pop(), []):
            if kid not in seen:
                seen.add(kid)
                stack.append(kid)
    return seen


def main():
    proj = tempfile.mkdtemp(prefix="lean-lsp-it-")
    with open(os.path.join(proj, "lakefile.toml"), "w") as f:
        f.write('name = "ItTest"\ndefaultTargets = ["ItTest"]\n\n[[lean_lib]]\nname = "ItTest"\n')
    toolchain = os.environ.get("LEAN_LSP_TEST_TOOLCHAIN")
    if toolchain and os.path.exists(toolchain):
        shutil.copyfile(toolchain, os.path.join(proj, "lean-toolchain"))
    with open(os.path.join(proj, "ItTest.lean"), "w") as f:
        f.write("def x := 1\n")

    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.elan/bin") + ":" + env.get("PATH", "")
    env["LEAN_LSP_REAP_IDLE_SECS"] = "10"
    env["LEAN_LSP_REAP_INTERVAL_SECS"] = "5"
    env["LEAN_LSP_WORKER_MAX_MB"] = "3000"

    proc = subprocess.Popen(
        [SUPERVISOR], cwd=proj, env=env,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )

    buf, lock = bytearray(), threading.Lock()

    def pump():
        while True:
            b = proc.stdout.read(1)
            if not b:
                break
            with lock:
                buf.extend(b)

    threading.Thread(target=pump, daemon=True).start()

    def send(obj):
        data = json.dumps(obj).encode()
        proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(data) + data)
        proc.stdin.flush()

    def saw(text, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            with lock:
                if text.encode() in buf:
                    return True
            time.sleep(0.2)
        return False

    def workers():
        return [(pid, cmd) for pid, _, cmd in ps_rows() if "--worker" in cmd and proj in cmd]

    try:
        # A. stdio transparency
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"processId": os.getpid(), "rootUri": "file://" + proj, "capabilities": {}}})
        check("A. initialize response received over stdio", saw('"capabilities"', 90))
        send({"jsonrpc": "2.0", "method": "initialized", "params": {}})

        # B. worker spawns and carries the -M cap
        send({"jsonrpc": "2.0", "method": "textDocument/didOpen",
              "params": {"textDocument": {"uri": "file://" + proj + "/ItTest.lean",
                                          "languageId": "lean", "version": 1, "text": "def x := 1\n"}}})
        time.sleep(8)
        first = workers()
        check("B. worker spawned for the opened document", len(first) >= 1)
        check("B. worker carries the -M memory cap", any("-M3000" in c for _, c in first))

        # C. idle reaping (idle window is 10s; wait it out)
        time.sleep(20)
        check("C. idle worker reaped", len(first) >= 1 and len(workers()) < len(first))

        # D. shutdown sweeps a live worker subtree
        with open(os.path.join(proj, "ItTest2.lean"), "w") as f:
            f.write("def y := 2\n")
        send({"jsonrpc": "2.0", "method": "textDocument/didOpen",
              "params": {"textDocument": {"uri": "file://" + proj + "/ItTest2.lean",
                                          "languageId": "lean", "version": 1, "text": "def y := 2\n"}}})
        time.sleep(8)
        subtree = descendants(proc.pid)
        check("D. subtree present before shutdown", len(subtree) >= 1)
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
        time.sleep(3)
        check("D. supervisor exited on SIGTERM", proc.poll() is not None)
        check("D. whole subtree swept (no orphans)", not any(is_alive(p) for p in subtree))
    finally:
        try:
            proc.kill()
        except Exception:
            pass
        subprocess.run(["pkill", "-f", proj], stderr=subprocess.DEVNULL)
        shutil.rmtree(proj, ignore_errors=True)

    failed = [n for n, ok in results if not ok]
    print()
    print("integration: %d/%d checks passed" % (len(results) - len(failed), len(results)), flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

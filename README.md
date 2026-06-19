# Codex CLI Intel Mac SIGTRAP Fix

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20x86__64-lightgrey)]()

> One-command fix for the `zsh: trace trap codex` crash on Intel-based Macs.

---

## Problem

Running OpenAI Codex CLI on an Intel Mac (x86_64) results in a SIGTRAP crash:

```
$ codex
• Working (11s • esc to interrupt)

zsh: trace trap  codex
```

The macOS crash report shows:

```
Exception Type:  EXC_BREAKPOINT (SIGTRAP)
Termination Reason: Trace/BPT trap: 5
```

## Root Cause

Codex CLI embeds the **V8 JavaScript engine** for its Code Mode / tool execution runtime. V8 requires executable memory allocation (JIT compilation), which on macOS means the binary must carry these entitlements:

| Entitlement | Required For |
|---|---|
| `com.apple.security.cs.allow-jit` | JIT compilation in hardened runtime |
| `com.apple.security.cs.allow-unsigned-executable-memory` | W^X memory for V8 code stubs |

The distributed x86_64 binary's **entitlements blob is malformed**, causing macOS to silently ignore it. When V8 calls `SetPermissions()` to allocate executable pages, the kernel denies the request and delivers `SIGTRAP`.

**Crash stack:**

```
v8::base::OS::SetPermissions(void*, size_t, v8::base::OS::MemoryPermission)
v8::internal::CodeRange::InitReservation(...)
v8::internal::Heap::SetUp
v8::internal::Isolate::Init
v8::internal::Isolate::InitWithSnapshot
v8::Isolate::New
codex_code_mode::runtime::spawn_runtime
```

**Affected versions:** 0.138.0 through 0.141.0 (possibly earlier/later).

**Affected platforms:**

| Platform | Status |
|---|---|
| Intel Mac (x86_64) | :red_circle: Affected |
| Apple Silicon (arm64) | :green_circle: Not affected |
| Windows / Linux | :green_circle: Not affected |

## Fix

The binary is re-signed ad-hoc with correct entitlements:

```bash
codesign --force --sign - --entitlements <entitlements.plist> \
  ~/.codex/packages/standalone/releases/<VERSION>-x86_64-apple-darwin/bin/codex
```

## Usage

```bash
git clone https://github.com/hattori7243/codex-intel-fix.git
cd codex-intel-fix
chmod +x fix-codex.sh
./fix-codex.sh
```

**After each Codex CLI update**, run the script again. It is idempotent — already-fixed binaries are skipped.

## How It Works

1. Locates all installed x86_64 Codex binaries under `~/.codex/packages/standalone/releases/`
2. Checks whether `allow-unsigned-executable-memory` is present (the missing one)
3. Ad-hoc re-signs any binary that lacks it, adding both required entitlements

The fix is local and does **not** modify any Codex source or config files.

## References

This workaround was discovered and verified by the Codex CLI community. The root cause was identified in:

- [openai/codex#27358](https://github.com/openai/codex/issues/27358) — macOS 15.7.7: root cause analysis and initial `codesign` workaround
- [openai/codex#27862](https://github.com/openai/codex/issues/27862) — macOS 26.5.1: detailed crash report and intermittent failure pattern
- [openai/codex#28893](https://github.com/openai/codex/issues/28893) — Confirmed `allow-unsigned-executable-memory` is required in addition to `allow-jit`
- [openai/codex#29000](https://github.com/openai/codex/issues/29000) — Same issue on latest 0.141.0

## License

MIT

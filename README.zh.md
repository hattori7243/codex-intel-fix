# Codex CLI Intel Mac SIGTRAP 修复

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20x86__64-lightgrey)]()

> 一行命令修复 Intel Mac 上 Codex CLI 的 `zsh: trace trap codex` 崩溃问题。

---

## 问题

在 Intel Mac (x86_64) 上运行 OpenAI Codex CLI 时，进程被 SIGTRAP 信号杀死：

```
$ codex
• Working (11s • esc to interrupt)

zsh: trace trap  codex
```

macOS 崩溃报告显示：

```
Exception Type:  EXC_BREAKPOINT (SIGTRAP)
Termination Reason: Trace/BPT trap: 5
```

## 根因

Codex CLI 内嵌了 **V8 JavaScript 引擎**（用于 Code Mode / 工具执行运行时）。V8 需要分配可执行内存（JIT 编译），这要求二进制文件在 macOS 上必须具备以下 entitlements：

| Entitlement | 用途 |
|---|---|
| `com.apple.security.cs.allow-jit` | 允许 hardened runtime 下进行 JIT 编译 |
| `com.apple.security.cs.allow-unsigned-executable-memory` | 允许 V8 创建 W^X 内存页用于代码桩 |

OpenAI 发布的 x86_64 二进制文件的 **entitlements blob 存在格式问题**，导致 macOS 静默忽略其中的内容。当 V8 调用 `SetPermissions()` 尝试分配可执行内存页时，内核拒绝该操作，向进程投递 `SIGTRAP`。

**崩溃调用栈：**

```
v8::base::OS::SetPermissions(void*, size_t, v8::base::OS::MemoryPermission)
v8::internal::CodeRange::InitReservation(...)
v8::internal::Heap::SetUp
v8::internal::Isolate::Init
v8::internal::Isolate::InitWithSnapshot
v8::Isolate::New
codex_code_mode::runtime::spawn_runtime
```

**受影响版本：** 0.138.0 至 0.141.0（可能也包括更早或更高版本）。

**平台影响：**

| 平台 | 状态 |
|---|---|
| Intel Mac (x86_64) | :red_circle: 受影响 |
| Apple Silicon (arm64) | :green_circle: 不受影响 |
| Windows / Linux | :green_circle: 不受影响 |

## 修复方案

对二进制文件进行 ad-hoc 重签，补上正确的 entitlements：

```bash
codesign --force --sign - --entitlements <entitlements.plist> \
  ~/.codex/packages/standalone/releases/<VERSION>-x86_64-apple-darwin/bin/codex
```

## 使用方法

```bash
git clone https://github.com/hattori7243/codex-intel-fix.git
cd codex-intel-fix
chmod +x fix-codex.sh
./fix-codex.sh
```

**每次 Codex CLI 自动更新后**，重新运行此脚本即可。脚本是冪等的——已修复的二进制会被自动跳过。

## 工作原理

1. 扫描 `~/.codex/packages/standalone/releases/` 下所有 x86_64 版本的 Codex 二进制文件
2. 检查是否缺少 `allow-unsigned-executable-memory` entitlement（这是分发版本所缺失的）
3. 对缺失该 entitlement 的二进制文件进行 ad-hoc 重签，补上两个必需的 entitlements

整个过程不修改 Codex 的任何源码或配置文件，完全本地操作。

## 方案来源

此修复方案由 Codex CLI 社区发现并验证，根因分析首发于以下 issue：

- [openai/codex#27358](https://github.com/openai/codex/issues/27358) — macOS 15.7.7：根因定位和初始 `codesign` workaround
- [openai/codex#27862](https://github.com/openai/codex/issues/27862) — macOS 26.5.1：详细崩溃报告和间歇性故障模式分析
- [openai/codex#28893](https://github.com/openai/codex/issues/28893) — 确认 `allow-unsigned-executable-memory` 为必需 entitlement（非仅 `allow-jit`）
- [openai/codex#29000](https://github.com/openai/codex/issues/29000) — 最新版本 0.141.0 上的相同问题

## 许可证

MIT

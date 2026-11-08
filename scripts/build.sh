#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：iOS IPA 需要在 macOS + Theos 环境编译。当前系统不是 macOS。" >&2
  exit 2
fi

if [[ -z "${THEOS:-}" || ! -f "$THEOS/makefiles/common.mk" ]]; then
  echo "错误：未检测到有效 THEOS 环境。请先安装 Theos 并设置 THEOS。" >&2
  exit 2
fi

command -v make >/dev/null || { echo "错误：缺少 make。" >&2; exit 2; }

make clean
make package FINALPACKAGE=1 PACKAGE_FORMAT=ipa

mkdir -p "$ROOT/dist"
shopt -s nullglob
packages=("$ROOT"/packages/*.tipa "$ROOT"/packages/*.ipa)
if (( ${#packages[@]} == 0 )); then
  echo "错误：编译结束但 packages/ 中没有找到 IPA/TIPA。" >&2
  exit 3
fi

cp "${packages[0]}" "$ROOT/dist/RebootTools-Shortcuts.tipa"
echo "构建完成：$ROOT/dist/RebootTools-Shortcuts.tipa"

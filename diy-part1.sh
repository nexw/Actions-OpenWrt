#!/bin/bash
#
# diy-part1.sh — 在 update feeds 之前执行（cwd = openwrt/）
# 用途：补充 feed / 把单包仓库放进 package/
#
set -e

echo "current directory : $(pwd)"

# ---- 额外 feed（按需启用）----
# src-git OpenClash https://github.com/vernesong/OpenClash   # 旧配置未选用，暂不引入以缩短构建时间

# ---- 单包仓库（不是 feed，必须直接放进 package/）----
# 注意：上游旧脚本写的是 `cd #GITHUB_WORKSPACE/package`（注释掉了路径），
#       实际 cd 到 $HOME，导致 argon 主题从未被真正编进固件。这里修正。
for repo in \
    "https://github.com/jerrykuku/luci-theme-argon.git luci-theme-argon" \
    "https://github.com/jerrykuku/luci-app-argon-config.git luci-app-argon-config" ; do
    set -- $repo
    url="$1"; dir="$2"
    if [ ! -d "package/$dir" ]; then
        git clone --depth 1 "$url" "package/$dir"
    fi
done

echo "diy-part1 done"

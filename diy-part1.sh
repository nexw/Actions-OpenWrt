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

# ---- 本仓库自带的本地包：做成 src-link feed ----
# 结构：packages/<category>/<pkg>（feed 的标准布局：分类目录/包目录）
# 为什么不用 `cp -r packages/* openwrt/package/`：实测直接拷进 package/ 时，
# make defconfig 不会给它们生成 config 符号（tmp/.config-package.in 里根本没有
# config PACKAGE_luci-app-*，而且连一条 build-dependency 警告都没有）——
# 像是包压根没进扫描范围。改走 feeds 机制（所有 feed 包都这样装）最稳。
if [ -d "$GITHUB_WORKSPACE/packages" ]; then
    [ -f feeds.conf ] || cp feeds.conf.default feeds.conf
    if ! grep -q '^src-link nrlocal ' feeds.conf; then
        echo "src-link nrlocal $GITHUB_WORKSPACE/packages" >> feeds.conf
    fi
    echo "已注册本地 feed: nrlocal -> $GITHUB_WORKSPACE/packages"
    grep -n nrlocal feeds.conf
fi

echo "diy-part1 done"

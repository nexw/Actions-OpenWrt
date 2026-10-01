#!/bin/bash
#
# diy-part2.sh — 在 update/install feeds 之后、make defconfig 之前执行
#                （cwd = $GITHUB_WORKSPACE，openwrt 树在 ./openwrt）
# 用途：应用本仓库 patches/ 下的机型补丁 + 少量默认值调整
#
set -e

OPENWRT="$GITHUB_WORKSPACE/openwrt"
echo "current directory : $(pwd)"
echo "openwrt tree      : $OPENWRT"

# ---- 1. 应用机型补丁（NRadio C8 / WT9104）----
for p in "$GITHUB_WORKSPACE"/patches/*.patch; do
    [ -e "$p" ] || continue
    echo "applying $(basename "$p")"
    git -C "$OPENWRT" apply --verbose "$p"
done

# ---- 2. 默认值调整（可选）----
# 默认 LAN IP / 主机名 / 时区统一交给 files/etc/uci-defaults/99-nradio-c8-defaults
# 如需在 config_generate 里改，可在此 sed：
# sed -i 's/192.168.1.1/192.168.66.1/g' "$OPENWRT/package/base-files/files/bin/config_generate"
# sed -i 's/OpenWrt/C8/g' "$OPENWRT/package/base-files/files/bin/config_generate"

echo "diy-part2 done"

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

# ---- 3. 本地包与包元数据缓存 ----
# diy-part1 在 feeds 之前把 packages/ 拷进了 openwrt/package/。这里：
#   a) 确认包真的就位（早点报错，别等 2.5 小时）
#   b) 清掉 tmp/ 下的包元数据缓存 —— 否则 make defconfig 可能还在用旧索引，
#      把本地包的 CONFIG_PACKAGE_* 当成未知符号静默删掉（实测踩过：
#      luci-app-wtmodem / luci-app-cellscan 被 defconfig 丢掉，但没任何报错）
for p in "$GITHUB_WORKSPACE"/packages/*/; do
    [ -d "$p" ] || continue
    name=$(basename "$p")
    if [ ! -f "$OPENWRT/package/$name/Makefile" ]; then
        echo "错误：openwrt/package/$name/Makefile 不存在（diy-part1 没拷进来？）" >&2
        exit 1
    fi
    echo "local package ok: $name"
done
# .packagedirs 是「包目录文件列表」缓存；如果它是在本地包拷进来之前生成的，
# 扫描阶段就永远看不到我们的包（连一个警告都不会有，症状就是 config 符号缺失）。
rm -f "$OPENWRT/tmp/.packageinfo" "$OPENWRT/tmp/.config-package.in" \
      "$OPENWRT/tmp/.targetinfo" "$OPENWRT/tmp/.config-target.in" \
      "$OPENWRT/tmp/.packagedirs" "$OPENWRT/tmp/.packagedirs.tmp" \
      "$OPENWRT/tmp/.targetdirs" "$OPENWRT/tmp/.targetinfo.tmp"
echo "已清理 tmp/ 包元数据与包目录缓存（下次 make defconfig 会重新扫描）"

echo "diy-part2 done"

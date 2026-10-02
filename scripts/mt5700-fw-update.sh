#!/usr/bin/env bash
# 在 NRadio C8（或任何把 MT5700M-CN 装在内部的路由器）上刷写 5G 模组固件。
#
# 原理：厂家官方固件（A 槽）里自带模组升级器 /usr/bin/UpdateWizard_MT5700，
# 但它是 32 位 ARM 静态程序，OpenWrt（aarch64）没有 AArch32 支持跑不了，
# 因此用 Debian arm64 的 qemu-arm-static 来执行。
#
# 用法:
#   scripts/mt5700-fw-update.sh <固件.bin> [路由器IP]
#   scripts/mt5700-fw-update.sh 后台升级MT5700M-CN_UPDATE_1.2.4.0-SP1C01-sec.bin
#
# 注意：模组升级有风险（中途断电可能变砖），且没有回退包时无法降级。
# 若升级失败、模组停在下载模式，可用 cpe-pwr GPIO 断电重启恢复：
#   echo 0 > /sys/class/gpio/cpe-pwr/value; sleep 5; echo 1 > /sys/class/gpio/cpe-pwr/value
set -euo pipefail

BIN="${1:-}"
HOST="${2:-192.168.66.1}"
[ -n "$BIN" ] || { echo "用法: $0 <固件.bin> [路由器IP]"; exit 1; }
[ -f "$BIN" ] || { echo "找不到固件: $BIN"; exit 1; }

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
SSH=(ssh "${SSH_OPTS[@]}" "root@$HOST")
REMOTE_BIN="/tmp/$(basename "$BIN")"
CACHE="${HOME}/.cache/mt5700"

q() { "${SSH[@]}" "$@"; }

echo "==> 目标设备: root@$HOST"
q true || { echo "SSH 连不上设备"; exit 1; }

# 1) 准备 qemu-arm-static（arm64 静态，可模拟 32 位 ARM 用户态）
QEMU="${CACHE}/qemu-arm-static"
if [ ! -x "$QEMU" ]; then
    echo "==> 下载 qemu-arm-static (Debian arm64)"
    mkdir -p "$CACHE"
    DEB="${CACHE}/qemu-user-static.deb"
    URL="https://deb.debian.org/debian/pool/main/q/qemu/qemu-user-static_7.2+dfsg-7+deb12u18+b3_arm64.deb"
    if [ ! -f "$DEB" ]; then
        curl -fL --progress-bar -o "$DEB" "$URL" || { echo "下载失败（可手动下载该 deb 放到 $DEB）"; exit 1; }
    fi
    TMP="$(mktemp -d)"
    ( cd "$TMP" && ar x "$DEB" && tar xf data.tar.xz ./usr/bin/qemu-arm-static )
    cp "$TMP/usr/bin/qemu-arm-static" "$QEMU"
    rm -rf "$TMP"
fi

# 2) 校验固件并推送到设备
echo "==> 固件: $BIN"
echo "    sha256: $(shasum -a 256 "$BIN" | cut -d' ' -f1)"
echo "==> 推送 qemu 与固件到设备 /tmp"
cat "$QEMU" | q "cat > /tmp/qemu-arm-static && chmod +x /tmp/qemu-arm-static"
cat "$BIN"  | q "cat > '$REMOTE_BIN'"
q "sha256sum '$REMOTE_BIN'"

# 3) 取厂家升级器（来自 A 槽原厂固件分区，只读挂载）
q '
set -e
if [ ! -x /tmp/uw ]; then
    P7=/dev/mmcblk0p7
    mkdir -p /mnt/mmcblk0p7
    grep -q " /mnt/mmcblk0p7 " /proc/mounts || mount -o ro "$P7" /mnt/mmcblk0p7 2>/dev/null || true
    if [ -x /mnt/mmcblk0p7/usr/bin/UpdateWizard_MT5700 ]; then
        cp /mnt/mmcblk0p7/usr/bin/UpdateWizard_MT5700 /tmp/uw && chmod +x /tmp/uw
        echo "已从原厂分区取出升级器"
    else
        echo "警告: 未找到 /mnt/mmcblk0p7/usr/bin/UpdateWizard_MT5700"
        echo "      （若两侧槽位都刷成了 OpenWrt，需要自行提供该文件）"
        exit 1
    fi
fi
'

# 4) 停掉会打扰模组的服务、断开 WAN、注册下载模式 PID
echo "==> 停服务 / 断 WAN（LAN、WiFi、SSH 不受影响）"
q '
/etc/init.d/mt5700-sim stop 2>/dev/null
/etc/init.d/cron stop 2>/dev/null
for p in mt5700-sim-check mt5700-status mt5700-wan-check; do pkill -f $p 2>/dev/null; done
ifdown wan 2>/dev/null
# 下载模式 3466:3302 需要 option 驱动认领（注册后会立即探测已存在接口）
echo "3466 3302" > /sys/bus/usb-serial/drivers/option1/new_id 2>/dev/null
echo "准备完成"
'

# 5) 运行升级器（后台 + 日志）
echo "==> 启动升级器（模组将切到下载模式，全程约 5~15 分钟）"
q '
rm -f /tmp/uw.log
setsid /tmp/qemu-arm-static /tmp/uw "'"$REMOTE_BIN"'" /PRINTLOG -s /sys/bus/usb/devices/1-1 > /tmp/uw.log 2>&1 < /dev/null &
echo "已启动"
'

echo "==> 监控日志（Ctrl-C 可离开，升级在设备后台继续）"
for _ in $(seq 1 120); do
    sleep 15
    q 'cat /tmp/uw.log 2>/dev/null' | tail -4
    if q 'grep -q "Program takes" /tmp/uw.log 2>/dev/null'; then
        break
    fi
done

echo
echo "==> 升级器输出"
q 'cat /tmp/uw.log'

# 6) 恢复服务并核对版本
echo "==> 恢复服务"
q '
/etc/init.d/mt5700-sim start 2>/dev/null
/etc/init.d/cron start 2>/dev/null
sleep 3
/usr/bin/mt5700-at --raw "AT^VERSION?" 2>/dev/null | tr -d "\r" | grep -E "INTS|EXTS" || true
/usr/bin/mt5700-wan-check || true
'
echo "==> 如果版本已更新，可检查网口模式: /usr/bin/mt5700-passthrough --status"

#!/usr/bin/env bash
# c8-backup.sh — 从 NRadio C8（WT9104）拉取"只读"备份到本机
# 用法: ./scripts/c8-backup.sh [root@192.168.66.1] [--full]
# 说明: 默认只备份引导/身份/系统关键分区（约 420MB），--full 追加 6.7GB 的 rootfs_2nd。
#       全程只读：dd / tar / cat，不写目标机任何位置。
set -euo pipefail

HOST="${1:-root@192.168.66.1}"
FULL=0
[[ "${2:-}" == "--full" ]] && FULL=1

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${C8_BACKUP_DIR:-$HOME/c8-backup-$STAMP}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 "$HOST")
mkdir -p "$OUT"/{boot,dt,etc,logs}
echo "==> 目标: $HOST   输出: $OUT"

run() { "${SSH[@]}" "$1"; }

echo "==> 0/7 环境快照"
run 'cat /proc/version; echo; cat /etc/os-release; echo; uptime' > "$OUT/logs/env.txt"
run 'fw_printenv 2>/dev/null' > "$OUT/boot/uboot-env.txt" || true
run 'cat /proc/partitions' > "$OUT/boot/partitions.txt"
run 'lsblk 2>/dev/null || true' > "$OUT/boot/lsblk.txt" 2>/dev/null || true
run 'lsmod' > "$OUT/logs/lsmod.txt"
run 'ubus call system board 2>/dev/null' > "$OUT/logs/ubus-board.json" || true

echo "==> 1/7 分区表（GPT 头/表 + 尾备份头）"
run 'dd if=/dev/mmcblk0 bs=512 count=34 2>/dev/null'   > "$OUT/boot/gpt-head.bin"
SECT=$(run 'cat /sys/block/mmcblk0/size' | tr -d '\r')
TAIL=$(( SECT - 34 ))
run "dd if=/dev/mmcblk0 bs=512 skip=$TAIL count=34 2>/dev/null" > "$OUT/boot/gpt-tail.bin"

echo "==> 2/7 引导/身份分区（p2 u-boot-env / p3 factory / p4 bdinfo / p5 fip）"
pull() { # pull <part> <name> [size]
  echo "    - $2 ($1)"
  run "dd if=/dev/$1 bs=1M 2>/dev/null | gzip -1" > "$OUT/boot/$2.gz"
}
pull mmcblk0p2 u-boot-env
pull mmcblk0p3 factory
pull mmcblk0p4 bdinfo
pull mmcblk0p5 fip

echo "==> 3/7 A 槽（kernel / rootfs，出厂固件，用于回滚）"
pull mmcblk0p6 kernel
pull mmcblk0p7 rootfs
echo "==> 4/7 B 槽 kernel_2nd"
pull mmcblk0p8 kernel_2nd
if [[ $FULL -eq 1 ]]; then
  echo "==> 4b/7 rootfs_2nd（6.7GB，较慢）"
  pull mmcblk0p9 rootfs_2nd
fi
pull mmcblk0p10 app_data

echo "==> 5/7 设备树（原件 + 反编译）"
run 'cat /sys/firmware/fdt' > "$OUT/dt/fdt.dtb"
if command -v dtc >/dev/null && [[ -s "$OUT/dt/fdt.dtb" ]]; then
  dtc -I dtb -O dts -o "$OUT/dt/fdt.dts" "$OUT/dt/fdt.dtb" 2>/dev/null || true
fi
run 'tar -C /proc -cf - device-tree' > "$OUT/dt/device-tree.tar"

echo "==> 6/7 配置与厂商用户态"
run 'tar -C /etc -cf - config board.d rc.button hotplug.d init.d uci-defaults' > "$OUT/etc/etc-config.tar"
run 'tar -C / -cf - root 2>/dev/null | head -c 200000000' > "$OUT/etc/root-scripts.tar" 2>/dev/null || true
run 'tar -C /usr/share -cf - modem' > "$OUT/etc/usr-share-modem.tar"
run 'tar -C /www -cf - 5700' > "$OUT/etc/www-5700.tar" 2>/dev/null || true
run 'uci show' > "$OUT/etc/uci-all.txt"

echo "==> 7/7 5G 模块基线（只读 AT，经模块自带 TCP）"
run 'python3 - <<'"'"'PY'"'"'
import socket,time
cmds=["ATI","AT+CGSN","AT+CIMI","AT^ICCID?","AT+CPIN?","AT+CSQ","AT^HCSQ?","AT^MONSC",
      "AT^HFREQINFO?","AT^CHIPTEMP?","AT^DSFLOWQRY","AT+CGDCONT?","AT+CGPADDR","AT+CEREG?",
      "AT+CGATT?","AT^SETMODE?","AT^TDPCIELANCFG?","AT^TDPMCFG?","AT+CEUS?","AT^C5GOPTION?",
      "AT^FASTDORM?","AT^SIMSQ?","AT+CPMS?","AT^VERSION?"]
try:
    s=socket.create_connection(("192.168.8.1",20249),5); s.settimeout(4)
    for c in cmds:
        s.sendall((c+"\r\n").encode()); time.sleep(0.9); buf=b""
        try:
            while True:
                d=s.recv(16384); buf+=d
                if b"OK" in buf or b"ERROR" in buf: break
        except Exception: pass
        print("### "+c); print(buf.decode("utf-8","replace").strip())
    s.close()
except Exception as e:
    print("AT-over-TCP 不可达:",e)
PY' > "$OUT/logs/modem-at-baseline.txt" 2>&1 || true

echo "==> 生成校验清单"
( cd "$OUT" && find . -type f ! -name SHA256SUMS -exec shasum -a 256 {} \; | sort -k2 > SHA256SUMS )
cat > "$OUT/README.md" <<EOF
# C8 只读备份
- 目标机: $HOST
- 时间: $(date -Iseconds)
- 模式: $( [[ $FULL -eq 1 ]] && echo full || echo minimal )
- 内容: boot/(GPT+引导与身份分区+A/B 槽), dt/(DTB), etc/(配置与厂商用户态), logs/(模块 AT 基线)
- 校验: \`shasum -a 256 -c SHA256SUMS\`
- 注意: 本目录含设备隐私（MAC/IMEI/密钥），**不得入库/外发**。
EOF
du -sh "$OUT"; echo "完成: $OUT"

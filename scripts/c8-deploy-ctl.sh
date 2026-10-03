#!/usr/bin/env bash
#
# c8-deploy-ctl.sh — 把 fanctl / ledctl 手动部署到 NRadio C8 设备
#
# 用途：镜像里没带这两个服务时（例如构建用的是旧 commit），直接把仓库里的
#       包内容推到设备上；overlay 若在 sysupgrade 后丢了，重跑一次即可。
#
# 源目录（2026-10-03 起 fanctl / ledctl 已从 files/ 迁入 apk 包）：
#   packages/c8/fanctl/files/...、packages/c8/ledctl/files/...
#   （files/ 现在只剩 mt5700-* 与 uci-defaults，与本脚本无关）
#
# 特点：
#   - 只覆盖「代码」（usr/bin/*、etc/init.d/*），不动你已调优的参数
#   - /etc/config/{fancontrol,ledschedule} 缺失时用仓库默认值创建；
#     已存在则只**补齐缺失项**（例如新增的 kernel_driver），已有值一律不覆盖
#   - 最后 enable + restart 两个服务并打印 status
#
# 用法：
#   scripts/c8-deploy-ctl.sh                 # 默认 root@192.168.66.1
#   scripts/c8-deploy-ctl.sh root@192.168.66.1
#
set -euo pipefail

R="${1:-root@192.168.66.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FANCTL="$ROOT/packages/c8/fanctl/files"
LEDCTL="$ROOT/packages/c8/ledctl/files"
SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$R")
SEC=main

for d in "$FANCTL" "$LEDCTL"; do
	[ -d "$d/usr/bin" ] || { echo "找不到 $d/usr/bin（仓库布局变了？）" >&2; exit 1; }
done

# 把 'option key 值' / 'list key 值' 解析成 TAB 分隔的 kind/key/value
parse_cfg() {
    awk -F"'" '
        /^[[:space:]]*option[[:space:]]/ {
            k = $1; sub(/^[[:space:]]*option[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
            printf "option\t%s\t%s\n", k, $2; next
        }
        /^[[:space:]]*list[[:space:]]/ {
            k = $1; sub(/^[[:space:]]*list[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
            printf "list\t%s\t%s\n", k, $2; next
        }
    ' "$1"
}

# 注意：镜像里这些文件在 git 里曾是 644（缺可执行位），刷机后 /usr/bin/ledctl
# 之类会 "Permission denied"。这里统一按仓库内容重放，顺带把 mt5700-* 的工具
# 与 init.d 的可执行位补齐（chmod 755）。
# ---- 1. 代码文件 ----
# 源目录 | 设备路径。含 etc/hotplug.d/ntp/30-ledschedule（NTP 校时后 reload 的钩子），
# 少了它 ledschedule 的“事件驱动”在时钟跳变时就不完整。
echo "==> 部署代码到 $R"
for spec in "$FANCTL|usr/bin/fanctl" \
            "$LEDCTL|usr/bin/ledctl" \
            "$FANCTL|etc/init.d/fancontrol" \
            "$LEDCTL|etc/init.d/ledschedule" \
            "$LEDCTL|etc/hotplug.d/ntp/30-ledschedule"; do
	src="${spec%%|*}"; f="${spec##*|}"
	printf '    %-38s' "/$f"
	"${SSH[@]}" "mkdir -p /$(dirname "$f") && cat > /$f && chmod 755 /$f" < "$src/$f"
	echo ok
done

# ---- 2. UCI 配置：缺失才补 ----
deploy_config() {
	local cfg="$1" file="$2" kind k v added="" n
	printf '    %-28s' "/etc/config/$cfg"

	if ! "${SSH[@]}" "[ -f /etc/config/$cfg ]"; then
		"${SSH[@]}" "cat > /etc/config/$cfg && uci -q commit $cfg" < "$file"
		echo "已创建（仓库默认值）"
		return
	fi

	while IFS=$'\t' read -r kind k v; do
		[ -n "${k:-}" ] || continue
		case "$kind" in
		option)
			# 设备上已有非空值就不动
			# shellcheck disable=SC2016,SC2029
			n=$("${SSH[@]}" "[ -n \"\$(uci -q get $cfg.$SEC.$k)\" ] && echo 0 || { uci set $cfg.$SEC.$k='$v'; uci -q commit $cfg; echo 1; }")
			[ "$n" = 1 ] && added="$added $k"
			;;
		list)
			# shellcheck disable=SC2016,SC2029
			n=$("${SSH[@]}" "cur=\$(uci -q get $cfg.$SEC.$k 2>/dev/null || echo); case \" \$cur \" in *\" $v \"*) echo 0 ;; *) uci add_list $cfg.$SEC.$k='$v'; uci -q commit $cfg; echo 1 ;; esac")
			[ "$n" = 1 ] && added="$added $k"
			;;
		esac
	done < <(parse_cfg "$file")

	echo "补齐:${added:-无（已是最新）}"
}

echo "==> 同步 UCI 配置（不覆盖已有值）"
deploy_config fancontrol  "$FANCTL/etc/config/fancontrol"
deploy_config ledschedule "$LEDCTL/etc/config/ledschedule"

# ---- 2.5 修补可执行位（历史镜像里 files/ 有 644 的文件）----
echo "==> 修补可执行位"
FIX=""
for f in etc/init.d/fancontrol etc/init.d/ledschedule etc/init.d/mt5700-mode \
         etc/init.d/mt5700-usbserial etc/init.d/mt5700-wan \
         usr/bin/fanctl usr/bin/ledctl usr/bin/mt5700-passthrough \
         usr/bin/mt5700-wan-check usr/bin/mt5700-at usr/bin/mt5700-status \
         usr/bin/mt5700-sms usr/bin/mt5700-simsel usr/bin/mt5700-sim-check \
         usr/bin/mt5700-modem-restart; do
    FIX="$FIX /$f"
done
"${SSH[@]}" "chmod 755 $FIX" && echo "    ok"

# ---- 3. 启用并启动 ----
echo "==> 启用服务"
"${SSH[@]}" '
	sh -n /usr/bin/fanctl && sh -n /usr/bin/ledctl
	for s in mt5700-usbserial mt5700-mode mt5700-sim mt5700-wan \
	         fancontrol ledschedule mt5700sms; do
		/etc/init.d/$s enable >/dev/null 2>&1 || true
	done
	/etc/init.d/modeminfo enable >/dev/null 2>&1 || true
	# 若模块在但 WAN 没拿到地址（多见于刷机后 boot 脚本没跑起来），补跑一次
	if [ -e /dev/ttyUSB1 ] && ! ip -4 addr show eth1 2>/dev/null | grep -q "inet "; then
		echo "    WAN 无地址，补跑模块启动脚本…"
		for s in mt5700-usbserial mt5700-mode mt5700-sim mt5700-wan; do
			/etc/init.d/$s start >/dev/null 2>&1 || true
		done
		sleep 8
	fi
	/etc/init.d/modeminfo restart >/dev/null 2>&1 || /etc/init.d/modeminfo start >/dev/null 2>&1 || true
	/etc/init.d/fancontrol  restart >/dev/null 2>&1 || true
	/etc/init.d/ledschedule restart >/dev/null 2>&1 || true
	sleep 3
	echo "    fancontrol  : $(/etc/init.d/fancontrol status 2>&1)"
	echo "    ledschedule : $(/etc/init.d/ledschedule status 2>&1)"
	echo
	echo "----- fanctl status -----"
	fanctl status
	echo
	echo "----- ledctl status -----"
	ledctl status
'
# 这几条单独取，避免在远程单引号块里再嵌引号
echo
echo "----- 模块 / 短信 -----"
printf '  modconf  : %s\n' "$("${SSH[@]}" 'cat /tmp/modconf.conf 2>/dev/null' || true)"
printf '  WAN      : %s\n' "$("${SSH[@]}" "ip -4 addr show eth1 2>/dev/null | sed -n 's/.*inet \\([0-9.]*\\).*/\\1/p'" || true)"
printf '  未读短信 : %s\n' "$("${SSH[@]}" '/usr/bin/mt5700-sms count 2>/dev/null' || true)"

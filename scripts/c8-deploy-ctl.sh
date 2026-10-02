#!/usr/bin/env bash
#
# c8-deploy-ctl.sh — 把 fanctl / ledctl 手动部署到 NRadio C8 设备
#
# 用途：镜像里没带这两个脚本时（例如构建用的是旧 commit），直接把仓库里的
#       files/ 覆盖到设备上；overlay 若在 sysupgrade 后丢了，重跑一次即可。
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
SRC="$(cd "$(dirname "$0")/.." && pwd)/files"
SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$R")
SEC=main

[ -d "$SRC/usr/bin" ] || { echo "找不到 $SRC/usr/bin" >&2; exit 1; }

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

# ---- 1. 代码文件 ----
echo "==> 部署代码到 $R"
for f in usr/bin/fanctl usr/bin/ledctl etc/init.d/fancontrol etc/init.d/ledschedule; do
	printf '    %-28s' "/$f"
	"${SSH[@]}" "cat > /$f && chmod 755 /$f" < "$SRC/$f"
	echo ok
done

# ---- 2. UCI 配置：缺失才补 ----
deploy_config() {
	local cfg="$1" file="$SRC/etc/config/$1" kind k v added="" n
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
deploy_config fancontrol
deploy_config ledschedule

# ---- 3. 启用并启动 ----
echo "==> 启用服务"
"${SSH[@]}" '
	sh -n /usr/bin/fanctl && sh -n /usr/bin/ledctl
	/etc/init.d/fancontrol  enable >/dev/null 2>&1 || true
	/etc/init.d/ledschedule enable >/dev/null 2>&1 || true
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

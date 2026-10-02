#!/bin/sh
#
# mt5700-cellscan.sh —— 展锐 MT5700M 邻区扫描（AT^MONNC）
#
# 上游 luci-app-cellscan 是移远专用（写 at+qscan 到 /dev/ttyUSB2，解析 +QSCAN），
# 对 MT5700M 完全不可用。本脚本用展锐的邻区监视指令重写数据源：
#
#   AT^MONNC   -> ^MONNC: <RAT>,<EARFCN>,<PCI(hex)>,<RSRP>,<RSRQ>,<SINR>   邻区
#   AT^MONSC   -> 服务小区（本脚本把它也列成第一行，标成“服务”）
#   AT^EONS=2  -> 运营商码（46000/46001/... → 中文名）
#
# 输出 /tmp/kpcellinfo —— 纯 CSV（luci-app-cellscan 的 controller 按此解析）：
#   mode,operator,band,earfcn,pci,rsrp,rsrq
#
# 用法：mt5700-cellscan.sh [5|4]     5=只看 NR，4=只看 LTE，不带=全部
#
set -u

AT_PORT=${AT_PORT:-1}          # sendat 的端口序号 → /dev/ttyUSB1（本机 AT 口）
OUT=/tmp/kpcellinfo
LOCK=/tmp/cellscanlock
RUNTIME=/tmp/cellscan_run_time

usage() { echo "usage: $0 [5|4]" >&2; exit 1; }

filter=""
case "${1:-}" in
	5|5g|NR) filter="NR" ;;
	4|4g|LTE) filter="LTE" ;;
	"") : ;;
	*) usage ;;
esac

# 并发保护（扫描是即时的 AT 读，不需要上游那种 40s 缓存）
if [ -e "$LOCK" ]; then
	old=$(cat "$LOCK" 2>/dev/null)
	[ -n "$old" ] && kill -9 "$old" 2>/dev/null
	rm -f "$LOCK"
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT INT TERM

at() { sendat "$AT_PORT" "$1" 2>/dev/null; }

# ---- 运营商码 → 名称（与面板 zinfo_mt5700.sh 保持一致）----
operator_name() {
	case "$1" in
		46000|46002|46004|46007|46008|46020) echo "中国移动" ;;
		46001|46006|46009)                   echo "中国联通" ;;
		46003|46005|46011)                   echo "中国电信" ;;
		46015)                               echo "中国广电" ;;
		*)                                   echo "未知运营商" ;;
	esac
}

# ---- EARFCN → 频段名（沿用上游映射表）----
earfcn_to_band() {
    local earfcn=$1
    local bands=""
    # 4G LTE
    if [ $earfcn -ge 0 ] && [ $earfcn -le 41589 ]; then
        if [ $earfcn -ge 0 ] && [ $earfcn -le 599 ]; then
            bands="Band 1"
        elif [ $earfcn -ge 1200 ] && [ $earfcn -le 1949 ]; then
            bands="Band 3"
        elif [ $earfcn -ge 2400 ] && [ $earfcn -le 2649 ]; then
            bands="Band 5"
        elif [ $earfcn -ge 3450 ] && [ $earfcn -le 3799 ]; then
            bands="Band 8"
        elif [ $earfcn -ge 36200 ] && [ $earfcn -le 36349 ]; then
            bands="Band 34"
        elif [ $earfcn -ge 37750 ] && [ $earfcn -le 38249 ]; then
            bands="Band 38"
        elif [ $earfcn -ge 38250 ] && [ $earfcn -le 38649 ]; then
            bands="Band 39"
        elif [ $earfcn -ge 38650 ] && [ $earfcn -le 39649 ]; then
            bands="Band 40"
        elif [ $earfcn -ge 39650 ] && [ $earfcn -le 41589 ]; then
            bands="Band 41"
        fi
    # 以下是5G NR的
    elif [ $earfcn -ge 422000 ] && [ $earfcn -le 434000 ]; then
        bands="n1"
    elif [ $earfcn -ge 361000 ] && [ $earfcn -le 376000 ]; then
        bands="n3"
    elif [ $earfcn -ge 173800 ] && [ $earfcn -le 178800 ]; then
        bands="n5"
    elif [ $earfcn -ge 185000 ] && [ $earfcn -le 192000 ]; then
        bands="n8"
    elif [ $earfcn -ge 499200 ] && [ $earfcn -le 537999 ]; then
        bands="n41"
    elif [ $earfcn -ge 620000 ] && [ $earfcn -le 680000 ]; then
        bands="n78/n77"
    elif [ $earfcn -ge 693334 ] && [ $earfcn -le 733333 ]; then
        bands="n79"
    # 5G NR重复频段检查
    elif [ $earfcn -ge 158200 ] && [ $earfcn -le 164200 ]; then
        bands="n20"
    fi
    if [ $earfcn -ge 151600 ] && [ $earfcn -le 160600 ]; then
        [ -n "$bands" ] && bands="${bands}/"
        bands="${bands}n28"
    fi
    
    if [ -z "$bands" ]; then
        bands="Unknown Band"
    fi
    
    echo "$bands"
}

# ---- 组装输出 ----
: > "$OUT"
date +%s > "$RUNTIME"

# 运营商：从 EONS 拿 MCC+MNC（^EONS: 2,46000,"...",...）
opcode=$(at 'AT^EONS=2' | sed -n 's/^\^EONS: *2,*\([0-9]\{5,6\}\).*/\1/p' | head -1)
[ -n "$opcode" ] || opcode=$(at 'AT^MONSC' | sed -n 's/^\^MONSC: *[A-Za-z0-9]*,\([0-9]*\),\([0-9]*\).*/\1\2/p' | head -1)
operator=$(operator_name "$opcode")

emit() {   # $1=RAT $2=EARFCN $3=PCI(hex 或十进制) $4=RSRP $5=RSRQ $6=标签
	[ -n "$1" ] || return 0
	case "$1" in
		NR|nr)  mode="NR" ;;
		LTE|lte) mode="LTE" ;;
		*)      mode="$1" ;;
	esac
	[ -n "$filter" ] && [ "$mode" != "$filter" ] && return 0
	[ -n "$2" ] || return 0
	band=$(earfcn_to_band "$2")
	case "$3" in
		""|-) pci="-" ;;
		*[!0-9A-Fa-f]*) pci="$3" ;;
		*) pci=$((0x$3)) ;;
	esac
	[ -n "$band" ] || band="-"
	# CSV：mode,operator,band,earfcn,pci,rsrp,rsrq   （mode 带“服务/邻区”后缀便于阅读）
	echo "$mode($6),$operator,$band,$2,$pci,${4:--},${5:--}" >> "$OUT"
}

# 服务小区（^MONSC: RAT,MCC,MNC,EARFCN,...,PCI,...,RSRP,RSRQ,SINR）
at 'AT^MONSC' | sed -n 's/^\^MONSC: *//p' | while IFS= read -r l; do
	rat=$(echo "$l"  | cut -d, -f1)
	earfcn=$(echo "$l" | cut -d, -f4)
	pci=$(echo "$l"   | cut -d, -f7)
	case "$rat" in
		NR*|nr*) rsrp=$(echo "$l" | cut -d, -f9);  rsrq=$(echo "$l" | cut -d, -f10) ;;
		*)       rsrp=$(echo "$l" | cut -d, -f8);  rsrq=$(echo "$l" | cut -d, -f9)  ;;
	esac
	emit "$rat" "$earfcn" "$pci" "$rsrp" "$rsrq" "服务"
done

# 邻区（^MONNC: RAT,EARFCN,PCI(hex),RSRP,RSRQ,SINR）
at 'AT^MONNC' | sed -n 's/^\^MONNC: *//p' | while IFS= read -r l; do
	rat=$(echo "$l"    | cut -d, -f1)
	earfcn=$(echo "$l" | cut -d, -f2)
	pci=$(echo "$l"    | cut -d, -f3)
	rsrp=$(echo "$l"   | cut -d, -f4)
	rsrq=$(echo "$l"   | cut -d, -f5)
	emit "$rat" "$earfcn" "$pci" "$rsrp" "$rsrq" "邻区"
done

n=$(( $(wc -l < "$OUT") ))
logger -t cellscan "扫描完成：$n 个小区（filter=${filter:-全部}，operator=$operator）"

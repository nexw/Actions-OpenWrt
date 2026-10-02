#
# luci-app-cellscan —— 邻区扫描（NRadio C8 / MT5700M 适配版）
#
# 上游：https://github.com/newton-miku/luci-app-cellscan （GPL-3.0）
#       另有 Manper 树里的同名副本（zhongweijie95/NRadio-CPE-NO2）
#
# 上游只支持移远模组：向 /dev/ttyUSB2 写 `at+qscan` 再解析 `+QSCAN`，
# 且 controller 里 MT5700 会落到空模板。本仓库改动：
#   * controller：增加 MT5700 分支；/tmp/kpcellinfo 从“伪造 +QSCAN 行”改为纯 CSV
#   * 扫描脚本换成 root/usr/share/modem/mt5700-cellscan.sh（AT^MONNC 展锐邻区指令）
#   * 去掉上游的 model/cbi/cellscan.lua —— 它和 controller 同名 module，是死代码
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-cellscan
PKG_VERSION:=1.01
PKG_RELEASE:=3

PKG_LICENSE:=GPL-3.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=newton_miku (upstream) / MT5700M port in this repo

LUCI_TITLE:=LuCI 邻区扫描 (展锐 MT5700M 适配版)
LUCI_DESCRIPTION:=基站/邻区扫描：用 AT^MONNC 读取邻区，配合 EARFCN→频段映射展示 \
	mode/operator/band/earfcn/pci/rsrp/rsrq。
LUCI_PKGARCH:=all
# 上游还依赖 lua-cjson，本移植版只用 luci 自带的 Lua，不再需要
LUCI_DEPENDS:=+luci-compat

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
#
# ⚠️ 这行注释不是装饰，必须有：
# include/scan.mk 生成包列表时用的是
#   find -L <dir> -name Makefile | xargs grep -aHE 'call (Build/DefaultTargets|BuildPackage|KernelPackage)'
# 即在 Makefile 文本里 grep "call BuildPackage" 字样。本包的包定义在 luci.mk 里
# （$(eval $(call BuildPackage,...))），自己文件里没有这段文字就会被整份过滤掉，
# 表现为 make defconfig 完全不知道这个包存在：tmp/.config-package.in 里没有
# config PACKAGE_<name>、连一条警告都没有。删了这行包就会“消失”。

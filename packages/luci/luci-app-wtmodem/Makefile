#
# luci-app-WTModem —— 蜂窝模组面板（NRadio C8 / MT5700M 适配裁剪版）
#
# 来源：https://github.com/zhongweijie95/NRadio-CPE-NO2
#       feeds/luci/applications/luci-app-WTModem（Manper rebuild，Apache-2.0）
#       原始蜂窝程序源自 https://github.com/Zy143L/luci-app-zmodem
#
# 本仓库做了**裁剪**（见 README.md 的 “本仓库改动” 一节）：
#   - 保留：LuCI 只读面板（luasrc/）+ 采集脚本（zinfo_mt5700.sh / atcmd.sh 等）
#           + 纯 shell 的载波聚合解析（5700_get_zbjh.sh）
#   - 去除：全部预编译 ELF（sendat/QFirehose/RMUnlock/sms_tool2/bdinfo*/moimei/mopdu
#           /libbdinfo.so*）、移远专用数据面守护（rm520n.sh/500U.sh/mt5700m.sh/
#           netmodeled.sh）、运营商专用脚本、原 init.d/modeminit
#   - 替换：sendat 用 /usr/bin/mt5700-at 重新实现（无源码二进制 → 可维护脚本），
#           新增 /etc/init.d/modeminfo 只负责发布 /tmp/modconf.conf 与 /tmp/sim_sel
#
# 这样数据面（IP 直通）仍由本仓库的 mt5700-* 与 /etc/config/network 负责，
# 面板不碰 GPIO、不改网络，避免与现网配置互相打架。
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wtmodem
PKG_VERSION:=1.3
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Manper (upstream rebuild) / NRadio C8 port in this repo

LUCI_TITLE:=LuCI 蜂窝模组面板 (MT5700M 适配版)
LUCI_DESCRIPTION:=内置蜂窝控制器：模组状态/信号/小区/温度/SIM/APN/IMEI 与 AT 指令调试。 \
	裁剪版，只做只读展示；数据面由本仓库的 mt5700-* 负责。
LUCI_PKGARCH:=all
# luasrc/ 存在时 luci.mk 会自动补 +luci-lua-runtime；这里显式声明另一半个兼容层
LUCI_DEPENDS:=+luci-compat +luci-lib-nixio

include $(TOPDIR)/feeds/luci/luci.mk

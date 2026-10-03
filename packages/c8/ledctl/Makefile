#
# ledctl —— NRadio C8 (WT9104 / C8-688) 面板指示灯控制 + 夜间定时熄灯
#
# 为什么做成 apk 包：同 packages/c8/fanctl/Makefile 的说明（files/ 不被 apk 记账、
# 无版本无依赖、/etc/config 需要 conffile）。
#
# 配置生效路径（procd 触发器，非重启）：
#   uci commit ledschedule  → /etc/config/ledschedule 变更 → procd 触发 reload
#   ledctl off|on|auto|blink → 改完 /var/run/ledschedule.state 后显式
#                              /etc/init.d/ledschedule reload
#   NTP 校时（时间跳变）    → /etc/hotplug.d/ntp/30-ledschedule → reload
#   以上三条最终都落到 procd_send_signal → ledctl daemon 收 SIGHUP 原地重算唤醒时刻。
#
include $(TOPDIR)/rules.mk

PKG_NAME:=ledctl
PKG_VERSION:=1.1.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=JohnnyLo <johnny@nexwy.me>

# 纯 shell，目标无关
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/ledctl
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=面板指示灯控制 / 夜间定时熄灯（NRadio C8，procd 托管）
  URL:=https://github.com/nexw/Actions-OpenWrt
  DEPENDS:=+kmod-leds-gpio +kmod-ledtrig-network
endef

define Package/ledctl/description
 NRadio C8 (WT9104 / C8-688) 的面板/netdev 指示灯控制与夜间定时熄灯。

 控制 blue:power / blue:indicator-0 / blue:indicator-1 / blue:wlan 四颗 GPIO 灯，
 默认 00:00-06:00 全off。关灯前会快照每颗灯的 trigger/device_name，开灯时先让
 /etc/init.d/led 按 /etc/config/system 重建、再按快照精确还原，往返一致。

 守护进程是事件驱动的：只在「时段边界 / 手动覆盖到期 / 配置变更 / NTP 校时」
 醒来，不做固定间隔轮询（option max_sleep 是防时钟跳变的最长休眠上限，默认 1 h）。

 网口(RJ45)灯由 MT7531 LED 引脚驱动，当前固件没有软件通路，auto_eth_leds 为空操作，
 将来 DTS + 内核补齐后无需改配置即自动纳入。
endef

define Package/ledctl/conffiles
/etc/config/ledschedule
endef

define Package/ledctl/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/etc/init.d $(1)/etc/config $(1)/etc/hotplug.d/ntp
	$(INSTALL_BIN) ./root/usr/bin/ledctl $(1)/usr/bin/ledctl
	$(INSTALL_BIN) ./root/etc/init.d/ledschedule $(1)/etc/init.d/ledschedule
	$(INSTALL_CONF) ./root/etc/config/ledschedule $(1)/etc/config/ledschedule
	$(INSTALL_BIN) ./root/etc/hotplug.d/ntp/30-ledschedule $(1)/etc/hotplug.d/ntp/30-ledschedule
endef

$(eval $(call BuildPackage,ledctl))

# call BuildPackage - OpenWrt buildroot signature
#
# ⚠️ 上面这行注释不是装饰，必须有：include/scan.mk 生成包列表时用的是
#   find -L <dir> -name Makefile | xargs grep -aHE 'call (Build/DefaultTargets|BuildPackage|KernelPackage)'
# 即在 Makefile 文本里 grep "call BuildPackage" 字样。本包的包定义写在自己的
# $(eval $(call BuildPackage,...)) 里，所以本来就命中；但**不要删掉**这行注释，
# 它与 packages/luci/* 保持同一约定（那边定义在 luci.mk 里，删了就整包消失）。

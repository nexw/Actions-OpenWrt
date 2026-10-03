# Actions-OpenWrt — NRadio C8（WT9104 / C8-688）固件

基于 [immortalwrt](https://github.com/immortalwrt/immortalwrt) 的 GitHub Actions 自动构建，
目标设备 **NRadio C8**（ODM 板名 `WT9104`，SKU `C8-688`，UI 型号 `C8-668GL`）。

## 硬件

| 项 | 值 |
|---|---|
| SoC | MediaTek MT7981（2× Cortex-A53） |
| 内存 / 存储 | 1 GB DDR + 8 GB eMMC（GPT，A/B 双槽） |
| 交换 | MT7531（lan1/2/3 + lan4=2.5G）+ gmac1 2.5G（WAN，接 5G 模块） |
| 5G 模块 | **TD Tech MT5700M-CN**（USB `3466:3301`，UNISOC 体系） |
| 模块接口 | 2× cdc_ncm（`eth2`，备用数据面）+ 5× usbserial（`ttyUSB0..4`，**AT = ttyUSB1 @115200**） |
| 模块控制 | 串口 AT 或模块自带 **AT-over-TCP `192.168.8.1:20249`**（数据面 `eth1` 可达） |
| 按键 / LED | `reset`(pio1) + `wps`(pio9)；LED：status(10)/cmode5(11)/cmode4(12)/wifi(34) |
| 其它 GPIO | cpe-pwr(31)、cpe-sel0(29)、cpe-sel1(30)、fan-hw(27)、fan-fg(28)、PWM 风扇(25 kHz) |

> ⚠️ 该模块**只有 NCM / 私有串口两种 USB 组合，没有 QMI/MBIM/ECM**，因此不能走 `uqmi/umbim`
> 原生拨号；模块自己做 NAT/DHCP，路由器 `eth1` 以 `proto dhcp` 接入（单层可控，非单层 NAT）。
> 如果想要单层 NAT，需要模块侧的 passthrough/DMZ 能力，属后续实验。

## 构建基线

- 源码：`immortalwrt/immortalwrt` **发行版 tag `v25.12.2`**（openwrt-25.12 分支的发行点；feeds 按 commit 固定，可复现）
- 机型：`CONFIG_TARGET_PROFILE="DEVICE_nradio_c8-668gl"`（上游已有该机型）
- 默认 **中文界面**：`default-settings-chn` + `LUCI_LANG_zh_Hans` + `luci-i18n-base-zh-cn`，
  并在 `files/` 里固定 `luci.main.lang=zh_cn`、时区 CST-8、国内 NTP；IPv6 走 odhcpd RA/NDP 中继
  （`dhcp.{wan,lan}.{ra,dhcpv6,ndp}=relay` + `wan.master=1`），LAN 客户端直接使用上游 `2409:…/64`
- **无线**：`files/` 首启固定 `country=CN`、2.4G `ch11/HE20`、5G `ch149/HE80`（实测环境最优）；
  出厂 eeprom 的 wifi MAC 非法（驱动每次启动随机 BSSID），按 label MAC 派生固定 BSSID
  （lan=label，wan=label+2，wifi 取 +1/+3）
- 包集**只保留稳定组网所需**（275 包）：argon 主题、`luci-app-commands`/`ttyd`（维护用）、
  MT5700 工具链（`kmod-usb-serial-option`、`kmod-usb-net-cdc-ncm`、`usbutils`、`picocom`、
  `python3-light`+`python3-pyserial`）、风扇 `kmod-hwmon-pwmfan`、overlay `f2fs-tools`/`kmod-fs-f2fs`/`kmod-fs-ext4`
- **明确不含**：Docker/容器、Samba4/KSMBD、USB 存储/automount、smartdns、ddns、upnp、wol、aria2、minidlna 等 NAS/娱乐组件

## 本仓库对上游的补丁（`patches/`）

| 补丁 | 内容 |
|---|---|
| `0001-nradio-c8-688-wt9104-dts.patch` | 按实机（官方 1.9.4.n2.c3 DTB + 现网 GPIO 表）修正：WiFi LED pio13→**34**；`cpe-sel0` 30→**29**、新增 **cpe-sel1(30)**；新增 **fan-hw(27)/fan-fg(28)** 与 `pwm-fan`（25 kHz，首级 50% 保底）；保留 `reset`/`wps` 按键 |
| `0002-nradio-c8-688-bdinfo-fac-mac.patch` | `02_network`：`bdinfo` 的 `fac_mac` 键去掉多余空格（否则 `get_mac_ascii` 匹配不到，MAC 读不出来）。**不改** `platform.sh` 的数据分区（上游 `rootfs_data` 找不到时会自动回退到 rootfs 分区内的 overlay 区，保持与上游一致） |

### 已实机验证（2026-10-01 首刷）

- 刷入后：`board_name=nradio,c8-668gl`、ImmortalWrt SNAPSHOT (kernel 6.18.52)、LAN `192.168.66.1`、WAN 从 5G 模块 DHCP 到 `192.168.8.134`
- DTS 全部生效：按键 `gpio-1 reset` / `gpio-9 wps`（IRQ 输入）已注册；LED `blue:power/indicator-0/indicator-1/wlan`（**wlan=pio34** 修正生效）；`gpio-export` 5 路 `cpe-pwr/sel0/sel1/fan-hw/fan-fg` 全部导出
- 5G 模块可控：`/dev/ttyUSB0..4` 自动就位，`mt5700-at` 正常应答（无 SIM 时 `AT+CPIN?` = `+CME ERROR: 10`，属预期）
- **overlay 持久化坑（重要）**：若原厂 GPT 没有 `rootfs_data` 分区，fstools 会走"分区内 loop"路径并要求 `mkfs.f2fs`；旧镜像缺该工具 → 回退 tmpfs（**重启丢配置**）。本机处置：
  1. 把原厂 `app_data`(p10) 改名为 `rootfs_data` 并缩到 96MB（`fstools` 对 ≤100MiB 的面积用 `mkfs.ext4`，镜像自带）；
  2. U-Boot `bootargs` 追加 `fstools_partname_fallback_scan=1 fstools_overlay_fstype=ext4`
     （`root=PARTLABEL=` 形式下，`partname.c` 默认跳过同名分区扫描，必须显式打开）
  3. 新版镜像已带 `f2fs-tools`+`kmod-fs-f2fs`：**全新安装**时（无 rootfs_data 分区）会自动用 6.5GB 的分区内 f2fs overlay，无需手工干预；若想在本机切到 6.5GB，执行 `fw_setenv bootargs`（清空）后重启即可。

`files/` 覆盖：
- `etc/uci-defaults/99-nradio-c8-defaults`：LAN `192.168.66.1`、hostname `C8`、时区 CST-8、
  IPv6 RA/NDP 中继、无线（国家码/信道/固定 BSSID）
- `etc/hotplug.d/usb/20-mt5700-serial`：把模块 5 个 `ff/06` 接口绑定到 usb-serial
- `usr/bin/mt5700-at`：只读 AT 状态探针（`mt5700-at --json` / `--transport tcp` / `--raw "AT+CSQ"`）
- `usr/bin/wifi-survey [秒]`：无线环境实测（信道占用率 + 邻区 + 客户端链路，判断频宽是否值得加宽）
- `etc/config/commands`：LuCI「系统 → 命令」的快捷命令（5G / 风扇 / LED / 短信）

本地 apk 包（`packages/`，经 `src-link nrlocal` 进 feeds；**不再放 `files/`**，设计见
`docs/RFC-002-led-fan-packaging.md`）：

| 包 | 内容 | 依赖 |
|---|---|---|
| `packages/luci/luci-app-wtmodem` | 蜂窝面板 | `+luci-compat +luci-lib-nixio` |
| `packages/luci/luci-app-cellscan` | 邻区扫描 | `+luci-compat` |
| `packages/c8/fanctl` | `usr/bin/fanctl` + `etc/init.d/fancontrol` + `etc/config/fancontrol` | `+kmod-hwmon-pwmfan +kmod-gpio-pwm` |
| `packages/c8/ledctl` | `usr/bin/ledctl` + `etc/init.d/ledschedule` + `etc/config/ledschedule` + `etc/hotplug.d/ntp/30-ledschedule` | `+kmod-leds-gpio +kmod-ledtrig-network` |

> 为什么必须做成包：`files/` 里的内容不被 apk 记账（实机 `apk info -W /usr/bin/fanctl`
> → `Could not find owner package`），没有版本、无法单独升级、无法声明依赖；
> `/etc/config/*` 也只有做成包的 conffile 才有正确的升级语义。

## 风扇温控（userspace 兜底）

DTS 里已有 `pwm-fan` 节点（`pwmchip0/pwm0`，25 kHz），但 `cpu-thermal` 的 `cooling-maps`
只绑了 WiFi、没绑风扇，**内核 governor 不会驱动风扇**。为不阻塞使用，仓库用 userspace
闭环补上这一段：

> ✅ **2026-10-03 实机复核（更正早期说法）**：25.12.2 起的镜像**确实带了**
> `kmod-hwmon-pwmfan`（**builtin**，`lsmod` 里看不到是正常现象）。实机
> `hwmon3: pwmfan` 在线，`fanctl status` 报 `mode: hwmon-pwmfan`、
> `pwm1 = 170/255 = 66% @ 73.0 ℃`。内核驱动会独占 `pwm0` 并默认停在
> `cooling-levels[0] = 50%`，所以**必须走 `hwmon` 通路** —— `kernel_driver`
> 的默认值 `hwmon` 正是为此而设，不要想当然改成直接写 `pwm0`。

- `usr/bin/fanctl`：读 `thermal_zone0` → 查曲线（线性插值）→ 写 PWM。
  带 **3 ℃ 迟滞**、单次最多降 **10%**（抑制转速突变啸叫）、**>95 ℃ 直接拉满**、
  **温度读失败时保守拉满**、开机自动补齐 `period/enable` 与 `fan-hw` 供电。
  两条通路（每个 tick 重解析，内核驱动中途上下线也能跟上）：
  | 情况 | 通路 | 写入 |
  |---|---|---|
  | 内核无 `pwmfan` 驱动 | `userspace-sysfs` | `/sys/class/pwm/pwmchip0/pwm0/duty_cycle`（ns） |
  | 内核已接管 `pwm0` | `hwmon`（默认） | `/sys/class/hwmon/*/pwm1`（0–255），**温控照旧生效** |
  | 内核已接管且 `kernel_driver='yield'` | `yield` | 不插手，交回内核 governor |

  > ⚠️ 带 `kmod-hwmon-pwmfan` 的镜像里内核会独占 `pwm0`，而 DTS 的 `cpu-thermal`
  > `cooling-maps` 只绑了 WiFi、没绑风扇 —— 所以**必须走 `hwmon` 通路**，否则风扇会
  > 死锁在内核初始化的 50%。只有将来给风扇绑了 cooling-map，才应该把
  > `kernel_driver` 改成 `yield`。
- `etc/init.d/fancontrol`：procd 托管（退出后 5 s 重启，1 h 内最多 5 次），`START=96`
  （在 95 的 `fanfallback` 之后接管）；带 `service_triggers()` + 实例级
  `reload_signal=HUP`，所以 `uci commit fancontrol` 会**原地重载**配置（进程不重启、
  温控不中断）。改造前是“改完必须手动 `/etc/init.d/fancontrol restart`”。
- `etc/config/fancontrol`：间隔、曲线、下限/上限、迟滞、降幅、硬阈值均可调；它是本包的
  **conffile**，升级时保留本地修改。
- 包依赖 `+kmod-hwmon-pwmfan +kmod-gpio-pwm` 由 `DEPENDS` 自动拉入（原来靠手写 `.config`）。

默认温度-转速曲线（实机实测：原先只有开机 50% 兜底时空载 ~77 ℃；启用本曲线后空载
稳定在 ~71–72 ℃、对应 68% 左右，余量留给 85 ℃ 以上）：

| 温度 | 45 ℃ | 55 ℃ | 60 ℃ | 65 ℃ | 70 ℃ | 75 ℃ | 80 ℃ | ≥85 ℃ |
|---|---|---|---|---|---|---|---|---|
| 占空比 | 25% | 30% | 38% | 48% | 60% | 72% | 88% | 100% |

常用操作：

```sh
fanctl status     # 模式 / CPU 温度 / 当前占空比 / 风扇供电 / 目标档位
fanctl curve      # 查看生效曲线
fanctl set 80     # 手动打到 80%（下一个温控循环会按曲线纠正）
fanctl auto       # 立刻交回自动温控（按当前温度设一次，之后由守护进程接管）
# 改配置：commit 即生效（procd 触发器 → SIGHUP → 原地重载），不再需要 restart
uci set fancontrol.main.interval='5' && uci commit fancontrol
logread -e fanctl        # 应看到 "配置已重载：interval=5s ..."
```

LuCI 里也预置了三个「风扇」快捷命令（`luci-app-commands` → 系统 → 命令）。

> **后续修法（需重新构建并实机验证）**：给 `cpu-thermal` 的 `cooling-maps` 增加风扇
> `cooling-device = <&fan ...>`，并把 `kernel_driver` 改成 `yield` 即可交回内核 governor；
> 但现成 trip 点只有 60/85/115 ℃，粒度较粗，暂不采用。
> 注：`patches/0001` 把 `fan-fg` 写成 `gpio-export,output=<1>`，实测为输出、读不到转速，
> 想要 tach 反馈需改成 input；本脚本因此不使用转速反馈。

## 指示灯控制（夜间定时熄灯）

默认 **00:00–06:00 关闭全部面板指示灯**，避免夜里影响睡眠。

| LED | sysfs | 引脚 | 平时由谁点亮 | 可控 |
|---|---|---|---|---|
| 电源/状态 | `blue:power` | pio10 | 开机时由 `/etc/diag.sh` → `set_state done` 点一次；之后由 `led_power`（`default-on`）接管 | ✅ |
| 组网模式 5 / 5G | `blue:indicator-0` | pio11 | `led_5g`（netdev 跟随 `eth1`） | ✅ |
| 组网模式 4 | `blue:indicator-1` | pio12 | 无（保持熄灭） | ✅ |
| WiFi | `blue:wlan` | pio34 | `led_wifi`（netdev 跟随 `phy1-ap0`） | ✅ |
| RJ45 网口灯 | — | MT7531 LED 引脚 | 硬件 link/act | ❌ 见下 |

**`blue:power` 的完整控制链（重要）**：

1. 硬件：MT7981 pinctrl `pio10`，DT flag `0x01` = `GPIO_ACTIVE_LOW`
   （与官方 DTB 的 `hc:blue:status` 一致），由 `leds-gpio` 接管为 `/sys/class/leds/blue:power`。
2. 开机：DT aliases 把 `led-boot`/`led-failsafe`/`led-running`/`led-upgrade` **全部指向 `&led_power`**，
   `/etc/init.d/done`(START=95) 调 `. /etc/diag.sh; set_state done`：先 `status_led_off`，
   再因为 `boot == running` 跳过 trigger 还原、直接 `status_led_on` → `trigger=none, brightness=1`。
3. 之后：内核 `trigger=none`，**它是「开机点一次就不再变」的静态灯**，被夜里关掉后
   也不会自己恢复（`diag` 只在开机跑）。
   > ⚠️ **2026-10-03 更正**：早期文档写「`/etc/config/system` 里 **没有** `blue:power` 的
   > led 段（`uci show system` 里 0 条）」已经过时 —— 实机现在有
   > `system.@led[2].sysfs='blue:power'` / `trigger='default-on'`，`ledctl status` 也报
   > `恢复来源=uci`。该段原本是设备端手工加的，现已固化进
   > `files/etc/uci-defaults/99-nradio-c8-defaults`（新装机自动生成 `system.led_power`，
   > 已有同名声明则跳过），所以 `/etc/init.d/led start` 也会重建它。
4. 现在：`ledctl`/`ledschedule` 会在 00:00–06:00 关它、到点再点亮，以及手动 `ledctl on/off`。

`ledschedule.main.leds` 里把 `blue:power` 写成 `blue:power|1`（带显式恢复亮度），
即使第 3 条那条 UCI 段丢了也能正确点亮 —— 这就是「`|亮度` 用于 `/etc/config/system`
未声明的灯」那个设计的兜底用途。

- `usr/bin/ledctl`：关灯时逐灯 `trigger=none` + `brightness=0`；开灯时**先让
  `/etc/init.d/led start` 按 `/etc/config/system` 重建 netdev 灯，再按熄灯前快照还原
  其余灯的 trigger/device_name**，所以开灯后与熄灯前完全一致（已实测往返一致）。
- `etc/init.d/ledschedule`：procd 托管，`START=97`（在 `led`(96) 之后）；带
  `service_triggers()` + 实例级 `reload_signal=HUP`。
- **事件驱动，不做固定间隔轮询**（v1.1 起，见 `docs/RFC-002-led-fan-packaging.md`）。
  守护进程只在四种情况下醒来重算：① 时段边界（支持跨零点）② 手动覆盖到期
  ③ 配置变更（`uci commit` → procd 触发器 → SIGHUP）④ 手动切灯
  （`ledctl off/on/auto/blink` 改完状态后显式 reload）。另外
  `etc/hotplug.d/ntp/30-ledschedule` 在 NTP 校时（时间跳变）后也会 reload。
  **不用 cron 也不用轮询**：原来那个 60 s 轮询是为了兜住“开机时刻 / NTP 跳变 /
  跨零点”，现在这三件事分别由“启动即评估 / ntp 热插拔 / 跨零点算术”直接解决。
  > 唯一例外是 `option max_sleep`（默认 3600 s）：`sleep` 走单调时钟，NTP 把墙上
  > 时间往回跳时最多晚一个上限才发现。设 `0` 即完全不限（纯事件驱动）。这是有意的
  > 取舍，不把时段正确性完全押在单一外部事件上。
- `etc/config/ledschedule`：时段、`max_sleep`、手动覆盖时长、受控 LED 列表均可调；
  改完 `uci commit` 即时生效（无需重启服务）。`option interval`（轮询间隔）已废弃，
  残留时守护进程会在日志里提示一次。

```sh
ledctl status      # 时段 / 模式 / 每个 LED 的 trigger、brightness、恢复来源
ledctl schedule    # 只看熄灯时段与当前应处状态
ledctl off         # 立刻关灯（手动覆盖）
ledctl on          # 立刻开灯（手动覆盖）
ledctl auto        # 取消手动覆盖，立即按时段执行
ledctl toggle
ledctl blink blue:power 20   # 让某颗灯闪 20 s，用来辨认面板上到底是哪一颗

# 改配置：commit 即生效（触发器原地重载，不用等下一个轮询周期）
uci set ledschedule.main.off_start='22:30' && uci commit ledschedule
logread -e ledctl            # 应看到 "已重载：22:30-07:00 关灯 ..."
```

手动覆盖不会一直卡住：到期时间 = `min(现在 + manual_hold 分钟, 下一个时段边界)`，
默认 60 分钟；`manual_hold=0` 表示保持到下一个时段边界。

时段支持跨零点（`option off_start '22:30'` + `option off_end '07:00'`）；
`off_start == off_end` 视为关闭该功能。LuCI 里也预置了 4 条「LED」快捷命令。

### 关于网口（RJ45）LED

网口灯由 **MT7531 交换芯片的 LED 引脚**驱动，**当前固件没有任何软件通路**，已实测确认：

1. 内核无 mt7530 LED 支持（`/proc/kallsyms` 里 59 个 `mt7530_*` 符号，LED 相关为 0）；
2. DTS 的 `switch@1f`（`mediatek,mt7531`）下没有 `leds` 子节点；
3. 没有 switch LED trigger 模块（`/sys/class/leds/*/trigger` 只有
   `none/timer/heartbeat/default-on/netdev/pattern/mmc0/phy*`；`.config` 里只开了
   `kmod-ledtrig-gpio`/`-network`）。

所以网口灯目前就是硬件默认的 link/act，**关不掉**。脚本已预留自动探测：`option auto_eth_leds '1'`
会扫描 `/sys/class/leds` 中名字或 `device_name` 匹配 `lan*/wan*/eth*` 的灯，将来 DTS + 内核
补齐后无需改配置就会自动纳入熄灯范围（现在为空操作）。

> 若要真正控制网口灯，需要：给 `switch@1f` 加 `leds` 子节点（`led@0/1/2` + `color`/`function`）
> 并确认内核带 MT7530 LED 支持，然后重新构建刷机验证。

## 使用

1. Actions 页手动触发 **OpenWrt Builder**（或 `repository_dispatch`）。
2. 构建完成后在 **Releases** 下载 `openwrt-mediatek-filogic-nradio_c8-668gl-squashfs-sysupgrade.bin`。
3. 刷机（设备当前固件为 Mwrt/Manper，`sysupgrade -F` 不行则用原厂 LuCI 上传升级）：
   ```sh
   scp ...-squashfs-sysupgrade.bin root@192.168.66.1:/tmp/
   ssh root@192.168.66.1 'sysupgrade -v /tmp/...-squashfs-sysupgrade.bin'
   ```
   写入目标是 **B 槽**（`kernel_2nd` + `rootfs_2nd`，即当前运行槽）。
4. **回滚**：A 槽（`kernel` + `rootfs`）保留原厂固件；U-Boot 变量 `boot_system` 决定槽位
   （现网为 `1` = `rootfs_2nd`；`0` 预期为 A 槽，切换前请在串口 `115200` 下确认）。
   串口救砖：`ttyS0` 115200；U-Boot 内 `tftpboot`（env 含 `ipaddr/serverip`）。

## 模块状态自查（刷机后）

```sh
mt5700-at                     # 串口 AT 状态（模块/SIM/网络/数据/模式）
mt5700-at --transport tcp --json
mt5700-at --raw 'AT^SIMSQ?'   # SIM 是否在位（第二字段 0=无卡）
picocom -b 115200 /dev/ttyUSB1
```

## 注意

- 仓库内**不含**设备隐私（IMEI/ICCID/MAC/序列号等已脱敏）；本地备份与原始转储不入库（见 `.gitignore`）。
- 推送前请运行 `scripts/scan-secrets.sh`。

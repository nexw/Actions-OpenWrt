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
  并在 `files/` 里固定 `luci.main.lang=zh_cn`、时区 CST-8、国内 NTP、`filter_aaaa=1`（LAN 无 IPv6 上游）
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
- `etc/uci-defaults/99-nradio-c8-defaults`：LAN `192.168.66.1`、hostname `C8`、时区 CST-8
- `etc/hotplug.d/usb/20-mt5700-serial`：把模块 5 个 `ff/06` 接口绑定到 usb-serial
- `usr/bin/mt5700-at`：只读 AT 状态探针（`mt5700-at --json` / `--transport tcp` / `--raw "AT+CSQ"`）

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

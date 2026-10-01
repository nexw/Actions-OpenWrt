# NRadio C8（WT9104 / C8-688）实机基线

采集时间：2026-10-01；方式：SSH 只读查询（无任何写操作）。
采集点：`root@192.168.66.1`（该机同时是 5G CPE 整机）。

## 1. 整机身份

| 项 | 值 | 证据 |
|---|---|---|
| 品牌/型号 | NRadio **C8**，SKU `C8-688`，ODM 板名 `WT9104` | eMMC `bdinfo` 分区：`board = WT9104`、`oem_pname = C8-688`、`oem_vendor = nradio` |
| DTB compatible | `HCMT7981-emmc`, `mediatek,mt7981-emmc-rfb` | `/proc/device-tree/compatible` |
| SoC | MT7981（2× Cortex-A53） | `/proc/cpuinfo` |
| RAM | 1 GB（空闲 ~460 MB）+ 512 MB swap | `/proc/meminfo` |
| eMMC | 8 GB，型号 `YF3000` | `/sys/block/mmcblk0/device/name` |
| 固件 | `Mwrt @Manper-5.1.0 by immortalwrt-21.02-SNAPSHOT`，内核 **5.4.255**（MTK SDK 血统），构建者 `zhouwei@manper`，构建 2024-02-25 | `/etc/os-release`、`/proc/version` |
| 运行 | 开机 **69 天**，load 0.00，SoC 温度 **76.8 °C** | `uptime`、`/sys/class/thermal/thermal_zone0/temp` |
| 包数 | 551（opkg） | `opkg list-installed | wc -l` |
| 出厂 MAC | `FC:83:C6:xx:xx:xx` | eMMC `bdinfo`：`fac_mac = FC:83:C6:xx:xx:xx`（现网实际用的是 `46:ab:61:16:7c:xx/yy`，见 §5 备注） |

## 2. 存储与引导（GPT）

`mmcblk0` = 7,573,504 KB，GPT 分区表（实测解析）：

| # | 标签 | 大小 | 备注 |
|---|---|---|---|
| 1 | `gpt` | 33 扇区 | |
| 2 | `u-boot-env` | 0.5 MB | `fw_env.config` 指向 `/dev/mmcblk0p2` @0x0，size 0x80000 |
| 3 | `factory` | 1 MB | 头部 `81 79 00 00 …`，WiFi EEPROM/校准数据 |
| 4 | `bdinfo` | 1 MB | **纯文本**：`fac_mac / fac_key / imei / speedctl / cpesel / board / device_code / oem_ptype / oem_pname / oem_vendor / cpe_accumulation` |
| 5 | `fip` | 2 MB | ARM Trusted Firmware/U-Boot 阶段产物 |
| 6 | `kernel` | 32 MB | **A 槽**，头部 `d0 0d fe ed` = FIT |
| 7 | `rootfs` | 256 MB | **A 槽**，头部 `hsqs` = squashfs |
| 8 | `kernel_2nd` | 128 MB | **B 槽** |
| 9 | `rootfs_2nd` | 6715.5 MB | **B 槽（当前运行）**：起始为 squashfs，其后为 f2fs overlay（`loop0` 的 backing_file = `/mmcblk0p9`，容量差 ≈ squashfs 大小 108.5 MB） |
| 10 | `app_data` | 256 MB | 持久数据位（未被 immortalwrt 使用，见 §6 风险） |

- 内核 cmdline：`root=PARTLABEL=rootfs_2nd rootfstype=squashfs,f2fs`（与 immortalwrt DTS 里 `root=PARTLABEL=rootfs_2nd` 完全一致）
- U-Boot 环境（可直接读写）：`baudrate=115200`、`bootdelay=2`、**`boot_system=1`**、`ethaddr`、`ipaddr=192.168.1.1`、`serverip=192.168.1.88`、`kp_model=WT9104`、`kp_soft_ver=109040106`。**无 `bootcmd`**（编译进 U-Boot），`boot_system` 即 A/B 槽选择开关。
- A 槽（p6+p7）中已存在完整出厂固件（FIT + squashfs）→ **A/B 双槽回滚可用**。
- 救砖通道：串口 `ttyS0` 115200（stdin/stdout）、U-Boot 内 tftp（env 含 ipaddr/serverip）。

## 3. 以太网拓扑

| 网卡 | 来源 | 角色 |
|---|---|---|
| `eth0` | SoC gmac0（fixed-link 2500base-x）→ mt7531 CPU port (port6) | LAN 桥 |
| `lan1/lan2/lan3` | mt7531 port1/2/3 | LAN |
| `BLUE4` | mt7531 **port5**（2500base-x，phy5） | 厂商配置里并入 br-lan；上游 DTS 标为 `lan4` |
| `eth1` | SoC gmac1（2500base-x，`phy-handle=<&phy21>`） | **WAN**：承载 5G 模块的 L2（模块管理 IP 192.168.8.1、DHCP、全部上行流量） |
| `eth2` | 5G 模块 USB `cdc_ncm`（1-1:2.0） | **自开机起 0 字节**（完全未使用） |
| `dheth0` | 虚拟 veth，peer 在 `dhns` netns（ifindex 18 不在本 netns） | 厂商私有 DNS/DHCP 命名空间通道，桥在 br-lan |
| `ra0/rax0` | 厂商 WiFi 驱动（`mt_wifi`） | 双频 AP，SSID `<已脱敏SSID>`，sae-mixed |

驱动栈：厂商私有 **`mt_wifi` + `mtk_warp`/`mtk_warp_proxy` + `mtkhnat`**；交换机由厂商驱动托管（`BLUE4` 暴露 `DEVTYPE=dsa`）；内核具备 `cdc_ether/cdc_mbim/cdc_ncm/qmi_wwan/rndis_host/option/usb_wwan` 全套模块。

## 4. 5G 模块（不是移远）

| 项 | 值 |
|---|---|
| 厂商/型号 | **TD Tech Ltd. MT5700M-CN**（USB `3466:3301`，iSerial `<模块序列号-已脱敏>`） |
| 固件 | `V200R001C20B014`；`AT^VERSION` → `1.1.4.0(SP1C01)`、`MT5700M Ver.A`、编译 2024-12-05、ROMSIZE 4Gbit |
| 命令体系 | `^` 系（`^HCSQ ^MONSC ^HFREQINFO ^CHIPTEMP ^DSFLOWQRY ^SYSCFGEX ^SIMSQ ^ICCID`），**`AT+QGMR` 返回 ERROR → 非 Quectel**；属展锐(UNISOC)风格 |
| USB 组合 | 7 接口：2× `cdc_ncm`（= 主机侧 `eth2`）+ 5× `ff/06` usbserial（`ttyUSB0..4`，**AT = `/dev/ttyUSB1`**）；`bNumConfigurations=2`（当前 config 2） |
| AT 通道 | ① 串口 `/dev/ttyUSB1` @115200（实测 `ATI` 正常）② **TCP `192.168.8.1:20249`**（模块自身管理 IP，经 `eth1` 可达） |
| IMEI / SIM | `<IMEI-已脱敏>`（与 `bdinfo` 中 `imei` 一致）；`+CPIN: READY`，IMSI `46015xxxxxxxxxx` → MCC/MNC 460-15 = **中国广电**；ICCID `898615xxxxxxxxxxxxxx` |
| 网络 | `^HCSQ?` → `"NR"`；`^MONSC` → NR、MCC/MNC 460/15、NCI `C286F8002`、**PCI 130**、TAC `0x14901D`、RSRP **-78 dBm**、RSRQ **-10 dB**、SINR **15 dB**；`^HFREQINFO` → **n41、2565.0 MHz、100 MHz、单载波**（`^CASCELLINFO?` 该固件 ERROR，无 CA 可读） |
| 数据 | CID 8：IPv4 **`10.6.223.136`（运营商 CGNAT）** + 原生 IPv6 `240a:…`；CID 5 = `ims`；APN 全部为空（走运营商默认）；`+CGEQOSRDP: 8,9`（QCI 9） |
| 温度 | `^CHIPTEMP?` 12 路：**56.3 ~ 65.0 °C** |
| 流量（累计） | `^DSFLOWQRY` 后两字段：**Tx ≈ 11.94 GB / Rx ≈ 153.07 GB** |
| 短信 | `+CPMS: "SM",46,50` → 46/50，接近写满 |
| 注册 | `+CEREG: 2,1`（已注册）、`+CGATT: 1` |

### 模块当前模式参数（**回滚基线，改动前请留存**）

| 命令 | 当前值 | 说明 |
|---|---|---|
| `AT^SETMODE?` | `4` | 厂商拨号脚本会写 `AT^SETMODE=4`；`=?` 不支持枚举 |
| `AT^TDPCIELANCFG?` | `2`（可写范围 0/1） | TD Tech PCIe-LAN/LAN 配置；脚本会写 `=2` |
| `AT^TDPMCFG?` | `1,0,0,0` | bit0 = pcie |
| `AT+CEUS?` | `0`（可写范围 0/1） | 厂商脚本在拨号时 `=1`、断开时 `=0` |
| `AT^C5GOPTION?` | `1,1,1` | |
| `AT^FASTDORM?` | `1,5` | 快速休眠 5s（时延尖峰嫌疑） |
| `AT^SETNETNUM?` | `1` | |

### 市场面（现状拓扑，实测）

```
[5G 模块 MT5700M  NAT+DHCP  192.168.8.1 (CGNAT 10.6.223.136)]
        │  板载 GE 链路（观测：模块的 MAC/IP 出现在 eth1 = gmac1 的 L2 上）
        ▼
[路由器 WAN = eth1  192.168.8.133/24  ← 双重 NAT 的第一层]
        │  br-lan 192.168.66.1/24（lan1-3 + BLUE4 + ra0/rax0 + dheth0）
        ▼
[终端 192.168.66.101 …]   ← 第二层 NAT
```

- 模块的 USB NCM(`eth2`) 不参与数据面（0 字节），AT/串口才是 USB 侧用途。
- 厂商拨号脚本 `/usr/share/modem/mt5700m.sh` 中 `#/sbin/ifup wan` 是**注释掉的** → 数据面完全依赖模块内置 NAT/DHCP，路由器只是 dhcp client。

## 5. 厂商私有栈清单（重建时的清理对象）

- `/usr/sbin/quickstart`（厂商 UI 后端，unix socket :3038）
- `at-server.py` / `websocket_server.py`（`:8765`，**AT WebSocket 无鉴权**，`/www/5700/` 前端可直接发任意 AT 写命令）
- `python3 httpapi.py`（`:5000`）、`/www/5700`（modem 页面）
- `dhns` netns + `dheth0` veth（DHCP/DNS 隔离实现，dnsmasq 实际未做 LAN DHCP：`dhcp.lan.ignore=1`，leases 为空）
- `timecontrol / timewol / webrestriction / weburl / uugamebooster / ddnsto / cklinkn3000 / alist / turboacc / mtkhnat / uugamebooster / miniupnpd`
- 服务暴露面：uhttpd 80/443/8888、vsftpd 21、samba4 139/445、ttyd 7681(br-lan)、wsdd2 3702/5355、avahi 5353、dockerd 20.10.26（**vfs 驱动，0 容器**）
- 垃圾配置：`network.@route[0]` = `192.168.1.1/24 via 127.0.0.1`
- 日志噪音：每 1~2 分钟 `No response from modem`（uhttpd）——根因疑似 `/dev/ttyUSB1` 被 `:8765` 服务独占，`sendat` 消费者拿不到响应

## 5b. 厂商构建谱系（`/etc/build.config` 等，实测）

| 文件 | 内容要点 |
|---|---|
| `/etc/build.config` | 19 KB = 完整构建 `.config`，首行注释 `# Build configuration for board mediatek/mt7981/DEVICE_nradio_wt9104_No2-manper_New688` |
| 选中 profile | **`CONFIG_TARGET_mediatek_mt7981_DEVICE_nradio_wt9104_No2-manper_New688=y`**（**target = `mediatek/mt7981`，不是上游的 `mediatek/filogic`**） |
| 私有驱动 | `CONFIG_MTK_WARP_V2=y`、`CONFIG_WARP_CHIPSET="mt7981"`、`kmod-warp`、`kmod-mediatek_hnat`、`mtwifi-cfg` + `luci-app-mtwifi-cfg` |
| 私有应用 | `quickstart`(+luci)、`luci-app-Smstrun5700`、`ddnsto`、`uugamebooster`、`timecontrol`、`turboacc-mtk`、`eqos-mtk` |
| USB/模块能力 | 已内置 `kmod-usb-net-{cdc-ether,cdc-mbim,cdc-ncm,huawei-cdc-ncm,qmi-wwan,rndis}`、`kmod-usb-serial-{option,qualcomm,wwan}` |
| `/etc/build.feeds` | `immortalwrt/packages@e09f3c7d1`、`immortalwrt/luci@5829eabba5`、`openwrt/routing@a9e4310`、`openwrt/telephony@920fbc5`（feed 固定到 commit） |
| `/etc/build.version` | `r0-3fa9687` |
| `/etc/banner` | `The firmware compilation version V5.1.0 by:Manper-zcy` |
| `/etc/board.json` | `model.id = HCMT7981-emmc`、`model.name = NRadio-C8-New688`；lan = `lan1 lan2 lan3 BLUE4`(static)、wan = `eth1`(dhcp)；MAC 写死 `46:ab:61:16:7c:xx / …:ee` |
| `/etc/usb-mode.json` | 仅 usb-modeswitch 标准库（`messages`/`devices`），**无 TD Tech 专用条目** |
| `/etc/simsel` | `0`（与 `uci modem.@ndis[0].simsel=6` 不一致） |
| `/sys/firmware/fdt` | 存在（20480 B）→ **可直接导出厂商 DTB 反编译，得到权威 DTS**，无需拆机猜 GPIO |

结论：厂商固件属 **immortalwrt-21.02 + MTK SDK 5.4 内核 + mtwifi/warp 私有驱动** 谱系（与 `padavanonly`/`hanwckf` 的 `immortalwrt-mt798x` 同源），但**设备 profile（`nradio_wt9104_No2-manper_New688`）为厂商自建**；公开的 padavanonly 树里只有 `nradio_wt9103`（+512m），没有 WT9104/C8-688。

## 6. 上游已有支持与差异（关键）

**immortalwrt master 与 openwrt main 均已收录 `nradio_c8-668gl`**：

- DTS：`target/linux/mediatek/dts/mt7981b-nradio-c8-668gl.dts`（已在 `docs/refs/` 落盘 immortalwrt 版，265 行）
- `filogic.mk`：`DEVICE_DTS := mt7981b-nradio-c8-668gl`，`IMAGE_SIZE := 131072k`，`IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata | check-size`，`DEVICE_PACKAGES += kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb-serial-option kmod-usb-net-cdc-ether kmod-usb-net-qmi-wwan kmod-usb3 automount`
- `platform.sh`：`nradio,c8-668gl)` → `CI_DATAPART="rootfs_data"`、`CI_KERNPART="kernel_2nd"`、`CI_ROOTPART="rootfs_2nd"`、`emmc_do_upgrade`（即 **写 B 槽**）；镜像校验要求 `ustar`；配置迁移用 `emmc_copy_config`
- `02_network`：`ucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" "eth1"`；MAC 取 `mmc_get_mac_ascii bdinfo "fac_mac "`，**WAN = LAN + 2**
- `01_leds`：`wifi=blue:wlan(phy1-ap0)`、`5g=blue:indicator-0(eth1)`
- ⚠️ 该上游 profile 的 compatible 是 `nradio,c8-668gl`，**与本机 `HCMT7981-emmc` 不一致** → 从厂商固件直接 sysupgrade 会被 board 校验拒绝（需自建同 compatible 的 profile，或 `-F` 强刷）

### 与本机的实测差异（重建时必须适配）

| 项 | 上游 immortalwrt | 本机（WT9104 / C8-688） | 处理 |
|---|---|---|---|
| WiFi LED | `pio 13` | **`pio 34`** | 改 DTS |
| CPE 选择 | `cpe-sel0 = pio 30` | **`cpe-sel0 = pio 29`，另有 `cpe-sel1 = pio 30`** | 改 DTS |
| 风扇 | 无节点 | **`fan-hw = pio 27`、`fan-fg = pio 28`、`pwm-fan`（ch0, period 40000ns, cooling-levels 64/128/192/255）** | 补 DTS + 冷却策略 |
| 按键 | `reset(1)` + `wps(9)` | 只有 `reset(1)`（本机未见 WPS） | 去掉/禁用 wps |
| 数据分区 | 期望 `rootfs_data` | GPT 中为 **`app_data`**（p10，256 MB） | ⚠️ 需核实 `emmc_do_upgrade` 行为，必要时打兼容补丁 |
| LED 命名 | `blue:power / blue:indicator-0/1 / blue:wlan` | 厂商 `hc:blue:status / cmode5 / cmode4 / wifi` | 采用上游命名，GPIO 按实测 |
| `bdinfo` nvmem | DTS 只解析了 `u-boot-env` + `factory` | `bdinfo` 为文本（fac_mac/imei/oem_pname） | 需确认 `mmc_get_mac_ascii` 的读取路径可用 |

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

- 源码：`immortalwrt/immortalwrt` master，**pin 到** `bf156b68e3c9829f3e494e458caf97a40413c34c`
- 机型：`CONFIG_TARGET_PROFILE="DEVICE_nradio_c8-668gl"`（上游已有该机型）
- 包集：沿用旧 `Actions-OpenWrt` 的包选择（argon 主题、samba4、smartdns、ttyd、wol、upnp、ddns 等），
  另加 MT5700 适配：`kmod-usb-serial(-option)`、`kmod-usb-net-cdc-ncm`、`usbutils`、`picocom`、
  `python3-light` + `python3-pyserial`、`luci-app-commands`。不含任何 Mwrt/厂商私有包。

## 本仓库对上游的补丁（`patches/`）

| 补丁 | 内容 |
|---|---|
| `0001-nradio-c8-688-wt9104-dts.patch` | 按实机（官方 1.9.4.n2.c3 DTB + 现网 GPIO 表）修正：WiFi LED pio13→**34**；`cpe-sel0` 30→**29**、新增 **cpe-sel1(30)**；新增 **fan-hw(27)/fan-fg(28)** 与 `pwm-fan`（25 kHz，首级 50% 保底）；保留 `reset`/`wps` 按键 |
| `0002-nradio-c8-688-sysupgrade-and-mac.patch` | `platform.sh`：数据分区优先用原厂 `app_data`（老批次回退 `rootfs_data`）；`02_network`：`bdinfo` 的 `fac_mac` 键去掉多余空格（原样匹配，否则 MAC 读不到） |

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

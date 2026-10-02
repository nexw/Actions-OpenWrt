# MT5700M-CN 的"去 NAT / IP 直通"能力实测结论（2026-10-02）

> 现场：模块经**以太网**（非 USB 数据面）接到 C8 的 2.5G 口（gmac1/eth1）。
> 相关厂商设置：`AT^SETAUTODIAL=1,2`（**网口作为数传接口**）、`AT^TDPCIELANCFG=2`（RTL8215 2.5G PHY）。
> 模块固件：`V200R001C20B014` / `EXTS 1.1.4.0(SP1C01)` / 编译 2024-12-05。

## 实测结果

| 指令 | 本机结果 | 含义 |
|---|---|---|
| `AT^TDCFG?` | `Mode: 1 \| Dmz: not cfg \| PostRoute: 0 \| LHCM: 192.168.8.1,255.255.255.0,192.168.8.100,192.168.8.200 \| Share-pdp: 0` | 网口模式 = 1（默认） |
| `AT^TDCFG="infcfg","mode",<1\|2\|3>` | 可写；Mode 1→3 生效需重启模块 | 官方 UI 定义：1=USB Stick+网口E5数传，2=USB E5+网口E5数传，**3=网口直通模式(需执行拨号命令)** |
| **`AT^SETDIRECTIP=1/0`** | **ERROR（本固件未实现）** | 厂商 UI 的"IP 直通"开关就是它；跨机型共用 UI，本机 FW 不支持 |
| `AT+QCFG="nat",<0\|1\|2>` | ERROR | 其他模组的"网卡/路由/网桥"模式，本机不支持 |
| `AT^SETAUTODIAL?` | `1,2,"IPV4V6","","","",0` | 自动拨号开启，第 2 参=2 表示网口承载数据 |
| `AT+CGPADDR` | CID 8 = `10.x.x.x`（运营商 CGNAT） | 模块自己持有 WAN IP 并做 NAT |

**关键实测**：把 `mode` 设成 3 + 重启模块 + 手动拨号（先 `AT^SETAUTODIAL=0`，再
`AT+CGACT=1,8`，可见 `^DSAMBR: 8,300000,75000,"CMNET",7`），**模块仍然向下游发 192.168.8.x**，
路由器 WAN 没有拿到运营商 IP。→ 该固件的 `Mode 3` 是模块**内部数据通道**语义，不是"WAN IP 透传下游"。
（测试后已恢复 `mode=1` + `AT^SETAUTODIAL=1,2` + `AT^RESET`，联网复通。）

## DMZ（不减 NAT，但入站可达）

`AT^TDCFG="infcfg","dmz","<目标IP>"`；官方 UI 提示：**最好在拨号前配置 DMZ**
（"断开拨号 → 配置 → 重新拨号"），且 DMZ 主机会完全暴露在公网。

## 模块固件升级（只能官方签名包）

C8 官方固件内 `/usr/bin/UpdateWizard_MT5700` + `cloudd/firmware.lua` 从 NRadio 云取包，
通过串口走：`AT^DLOADVER?` / `AT^AUTHORITYVER?` / **`AT^SIGNVER=?`（签名校验）** /
`AT^GODLOAD`（进入下载模式）/ `AT^NVRESTORE`（NV 恢复）/ `AT^VERSION?`。
→ 自制/未签名固件刷不进去。

社区实测贴（恩山）结论：**B014 为推荐版本；B016 存在"网络 AT 不可用"**（本项目的监控/控制全依赖 AT），
因此不建议盲目升级。

## 想"只剩一层 NAT"时的可选方案

1. **C8 降级为 AP/交换机（无 NAT）**：把 eth1 并入 br-lan，关闭 C8 的 DHCP/NAT →
   全网只有模块一层 NAT（100% 可行，不改模块）；代价是 C8 不再做路由/防火墙/DNS。
2. 现状双 NAT：性能无虞（实测 **148 Mbps**），仅端口映射需连做两层。
3. 模块 DMZ 指向 C8 的 WAN IP：入站可达，出站仍双层。
4. 等具备 `AT^SETDIRECTIP` 且保留网络 AT 的新固件（取决于 TD Tech/NRadio）。


---

# 补充（2026-10-02，基于用户提供的新资料）

## 资料清单（~/workspace）
| 文件 | 内容 |
|---|---|
| `MT5700M-CN 5G系列模组AT命令手册(1).pdf` | 官方 AT 手册（546 页，文档版本 01，2024-05-17）。**`SETDIRECTIP` 全文 0 命中**；`AT^TDCFG` 正文只定义 mode **1/2**；含 `AT^NDISDUP`（NDIS 拨号）、`AT^DHCP`、`AT^IPFILTERSWITCH`、`AT^SETE5STICK`、`AT^GNETFEATURE`(5G LAN) 等 |
| `.../网口stick操作.txt`（208 字节，官方） | **IP 直通标准配方**：① 升级到最新版本 ② `at^tdcfg="infcfg","mode",3`，重启生效 ③ **入网拨号 `at^ndisdup=8,1`**，完成后下挂 PC 拿到 IP（抓网口日志另加 `AT^LOGPORT=2`） |
| `MT5700M-CN_Update_9.9.9.9(SP1C01)-debug-sec.exe`（80MB，2025-04-27，RAR 内） | **支持"IP 直通下发 10 地址"的测试/调试版模组固件升级器**。华为 Balong 升级框架；内含 `onchip.img`/`share_sec.bin`/`share_nsro.bin`/`comm.bin`/`dtcust.img`/`lpmcu_tcm.bin` 等组件；NV 配置 `MBB_NV_DIFF_CONFIG_hi9510_MT5700M_*.xml`；升级 AT 流程：`AT^SIGNVER=?`(签名校验) → `AT^NVBACKUP` → `AT^GODLOAD`(下载模式) → `AT^NVRESTORE` → `AT^SETMODE=1` → `AT^RESET` |
| `mt5700webui-openwrt-server_2.7(.zip)` | Windows 版模组 WebUI 服务（luajit + 混淆 Lua），与本机网络模式无关 |

## 实测（本机 B014）
- `AT^TDCFG="infcfg","mode",3` **可写入**（本机 `Mode: 3` 可查询），但**数据面未直通**：
  - `AT^NDISDUP=8,1` → `ERROR: DUPLICATED`（自动拨号已占 CID8）
  - 关闭自动拨号后 `AT^NDISDUP=8,0/1` 仍不能让下游拿到运营商 IP：路由器 WAN 继续从模组 DHCP 得到 `192.168.8.x`
- 结论：**mode-3 直通需要升级模组固件**（与官方说明第 1 条一致）；本机 B014 只接受该配置项，不实现数据面。
- 已恢复 `mode=1` + `AT^SETAUTODIAL=1,2` + `AT^RESET`（WAN `192.168.8.140`，联网正常）。

## 手册补充要点
- `AT^TDCFG` 字段：`Mode`(1/2)、`Dmz`("hostIP"/"0")、`PostRoute`(0/1/2)、`LHCM`(<lanIP>,<mask>,<start>,<end>)、`Share-pdp`(0/1，仅 USB Stick 模式)。
- 官方约束：**DMZ 与后路由互斥**；DMZ/后路由需在**拨号前**配置、**断开拨号后**删除；用后路由需先 `AT^IPFILTERSWITCH=0` + `AT+CFUN=0/1` 再拨号；`mode`/`LHCM`/`Share-pdp` **重启生效**。
- `AT^IPFILTERSWITCH=<0|1>`：IP 地址过滤开关（默认 0；本机当前为 1）。
- `AT^GNETFEATURE=0,1`：给网卡开启 **5G LAN** 特性（USB 单网卡用 0x01）。


---

# ✅ 结果：已实现 IP 直通（去掉模块那层 NAT）— 2026-10-02

## 有效配方（已验证）
1. 模组固件升级到 **`1.2.4.0(SP1C01)`**（官方签名包 `后台升级MT5700M-CN_UPDATE_1.2.4.0-SP1C01-sec.bin`，头部 `55aa5aa5`/`HWEW11.1`，SHA256 `8fe209f6…a41c97f`）
2. `AT^TDCFG="infcfg","mode",3`（写入模组 NVM，**掉电保存**）
3. `AT^RESET`
4. 保持模组自动拨号 `AT^SETAUTODIAL=1,2` 即可，**不需要**手动 `AT^NDISDUP=8,1`

旧固件 `1.1.4.0(SP1C01)` 只"记住" mode=3 但不实现直通数据面（`AT^NDISDUP=8,1` 返回 `ERROR: DUPLICATED`，下游仍拿 192.168.8.x），所以**必须升级固件**——与官方说明第 1 条一致。

## 验证证据
| 项目 | 结果 |
|---|---|
| 模组 `AT+CGPADDR`（CID 8） | 运营商分配地址，如 `10.x.x.x` |
| 路由器 `eth1`（WAN） | **与模组相同**的运营商地址（同一 IP = 模块未做 NAT） |
| 默认路由 | 运营商网关（如 `10.0.0.1`），不再是 `192.168.8.1` |
| DHCP 租约 | `udhcpc: lease of 10.x.x.x obtained from 192.168.8.1`（模块作 DHCP 代理，不下发 192.168.8.x） |
| 测速 / 延迟 | 91.2 Mbps（清华源） / 24~35 ms |
| traceroute 第一跳 | `192.168.8.1`（模块仅作为网关转发，不再 NAT） |
| 全网 NAT 层数 | **1 层**（只有 C8；模块层已透明） |

## 固件升级方法（关键经验）
- 厂家 A 槽原厂固件自带 `UpdateWizard_MT5700`（32 位 ARM、静态、`/usr/bin/UpdateWizard_MT5700`），调用方式：
  `UpdateWizard_MT5700 <bin> /PRINTLOG [-s /sys/bus/usb/devices/1-1]`
  （同一目录还有包装脚本 `modem_upgrade -f <bin> -m 0`，支持 local/ftp/fota 三种模式）
- 该程序在 aarch64 OpenWrt 上跑不了（内核无 `CONFIG_COMPAT`/AArch32）→ 用 **Debian arm64 的 `qemu-arm-static`** 运行，见 `scripts/mt5700-fw-update.sh`
- **下载模式的坑**：升级时模组切成 `3466:3302`（接口 class `ff` / subclass `06`），上游 `usb-serial` 通用规则不认领（它只匹配 subclass `00`），导致升级器报 `Last error: 10: Cannot find the port`。解决：把该 PID 注册进 `option` 驱动 ——
  `echo "3466 3302" > /sys/bus/usb-serial/drivers/option1/new_id`
  注册会**立即触发**对已存在接口的探测绑定（无需重插拔）✓
  正常模式 `3466:3301` 同理。现已由 `/etc/init.d/mt5700-usbserial` + `/etc/hotplug.d/usb/25-mt5700-download` 自动处理
- 升级器内部流程：签名校验 → `AT^NVBACKUP`(NV 备份) → `AT^GODLOAD`(进下载模式) → 传输(~60MB) → `AT^NVRESTORE` → `AT^SETMODE=1` → `AT^RESET`；实测 NV 保留（自动拨号/SIM 设置都在）
- 升级期间必须停掉会碰模组的服务并 `ifdown wan`（否则 AT 冲突/链路抖动）
- **失败恢复**：若停在下载模式，`cpe-pwr` GPIO 断电重启即可（`active_low=1`，写 0 断电、写 1 上电，约 20s 枚举回正常模式）

## 升级后变化
- USB 串口由 5 个变 4 个：`ttyUSB0`=proto `0x13`(diag)、**`ttyUSB1`=proto `0x12`(AT，脚本不用改)**、`ttyUSB2`=proto `0x1c`、`ttyUSB3`=proto `0x14`
- 正常模式串口接口的 subclass 变为 `06`，因此需要有 `mt5700-usbserial` 里的 PID 注册才能绑定（否则开机没有 `/dev/ttyUSB*`）

## 开机时序（已加自愈）
`mt5700-sim` 开机切 SIM 槽位会 `AT+CFUN` 循环、让模组重新拨号；若 DHCP 抢在拨号完成前发出会失败且 netifd 停在 pending。因此：
- `/usr/bin/mt5700-wan-check`：检测 `eth1` 无 IPv4 就重新触发 DHCP（+ `ifup wan`）
- `/etc/init.d/mt5700-wan`（START=99）：开机 45s 后最多重试 6 次
- `crontab`：每 3 分钟兜底一次
- 实测冷启动约 7 秒内拿到运营商地址 ✓

## 相关脚本/配置（随固件一起构建）
| 路径 | 作用 |
|---|---|
| `/usr/bin/mt5700-passthrough` | `on`=mode 3 IP 直通 / `off`=mode 1 传统路由 / `--status` |
| `/usr/bin/mt5700-wan-check` | WAN 自愈（无 IP 时重新 DHCP） |
| `/etc/init.d/mt5700-usbserial` | 启动时把 `3466:3301/3302` 注册进 option 驱动，保证串口可用 |
| `/etc/init.d/mt5700-mode` | 按 UCI `mt5700.eth.mode`（默认 3）应用网口模式 |
| `/etc/init.d/mt5700-wan` | 开机后确保 WAN 拿到地址 |
| `/etc/hotplug.d/usb/25-mt5700-download` | 模组进下载模式时自动绑定串口（固件升级用） |
| `/etc/config/mt5700` | `sim.slot`、`eth.mode` 等配置 |

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

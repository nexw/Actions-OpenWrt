# 模块(5G)管理功能的 GitHub 溯源与加入构建评估

> 2026-10-02 调研。目标：搞清厂商/Mwrt 那套 5G 模组管理功能**有没有公开源码**，
> 以及能不能加进我们的构建（`immortalwrt v25.12.2` / `mediatek/filogic` / LuCI ucode）。

## 0. 结论速览

| 来源 | 有源码? | 许可证 | 结论 |
|---|---|---|---|
| **NRadio OEM 层**（`luci-app-nradio-*`、`cpesel`、`cpetools`、`smsd`、`UpdateWizard_MT5700`…） | ❌ **无源码** | 无（闭源） | 只有别人把固件**解包**后放上 GitHub 的存档；我们本机 A 槽就是同一套 |
| **Manper/Mwrt 侧模块管理应用** | ✅ **有源码** | Apache-2.0 / GPL-3.0 | 在 `zhongweijie95/NRadio-CPE-NO2` 里，**含 MT5700M 支持** ← 这条才是可评估的对象 |

一句话：**想"加入构建"的候选是 Manper 那套 LuCI 应用，不是 NRadio 的 OEM 闭源层。**

## 1. 本机 A 槽（NRadio 原厂 1.9.4.n1.c6）里的模块管理清单

430 个包里，模块/CPE 相关的有：

```
init.d:  cellular_init cellular_power cpesel cpeselgpio cimd smsd combo
         nrswitch wanchk wanswd conn_detect msad fanctrl ledctrl
bin/sh:  cpesel.sh cpetools.sh sync_cpecfg.sh wanchk.sh wanswd.sh
         UpdateWizard_MT5700(ELF) modem_upgrade simcom_http simcom_http_cli
         devstatus nrswitch nradio_device_binding nradio_crypto
LuCI:    controller/{nradio,nradio_adv}.lua + view/nradio_{cpecfg,cpedata,cpestat,
         sms,hsimlock,dividing,fanctrl,ledctrl,wanchk,qsetup,status,...}
包名:    luci-app-nradio-{ac,access,apcli,app,appcenter,authmodule,cpe,cpe-upgrade,
         cpecfg,cpedata,cpestat,device-binding,dhcp,diag,dividing,dmz,fanctrl,
         firewall,forwarding,guest,hsimlock,ipv6,ledctrl,logread,mcast,mtkhnat,
         passwd,ptype,reset,restart,security,sms,terminal-limit,ttl,upnp,vpn,
         wanchk,wifidogx}  + pkg-usb-modem{,-meig,-quectel} + pkg-{sms,mwan,
         fanctrl,device-binding,appcenter,io-ata}
```

版权指纹：`Copyright 2017-2018 NRadio`、`Copyright 2019 Allen Wu <allen@nradiowifi.com>`。

`usr/lib/opkg/status` 里**没有** `Homepage`/`License` 字段，所以无法从包元数据反查来源。

**GitHub 上的对应物**（都是"固件解包存档"，非源码）：

- `561410590/ssh-nradio-plugin-installer`
  → 路径 `10-router-pages/factory-bin-C2000MAX-2.1.7.n0.c1-extracted/`
  含同款 `luci-app-nradio-*.control`、`usr/bin/{cpetools.sh,sync_cpecfg.sh,modem_upgrade}`、
  `etc/init.d/cpeselgpio`、`lib/netifd/proto/{ncm,odu}.sh`、`UpdateWizard_MT5700.list`、
  `usr/lib/lua/luci/{nradio.lua,model/cbi/nradio_cpecfg/*}` —— **就是解包出来的 rootfs**
- `github.com/nradiowifi`（NRadio Global，2026-04 注册）只有 1 个 `docs` 仓库 → 无固件源码

> 也就是说：**NRadio 的 OEM 层闭源**。脚本（`.sh`）是明文可以直接搬；
> LuCI 是 Lua（可读但依赖老 Lua 栈）；`UpdateWizard_MT5700`/`modem_upgrade`/`nrswitch`/
> `simcom_http` 等是 **32 位 ARM ELF**，要匹配 ABI 才能搬。

## 2. 可评估的源码候选：`zhongweijie95/NRadio-CPE-NO2`

- 基于 `hanwckf/immortalwrt-mt798x`；蜂窝程序源自 `Zy143L/luci-app-zmodem`
- README 明确「新增鲲鹏 MTK7981 系列 WT91XX-NO2 分区的 DTS 与配套程序」
- **新增设备列表含 NRadio-C8/650/660/668/680/688/688-Pro/C5800-688**
- 带 `config-NRdev/` 预置 config，其中就有 **`668巴龙常规版/纯净版`、`668移远常规版/纯净版`**

候选包（都在 `feeds/luci/applications/`）：

| 包 | 作用 | 许可证 | 体积 | 上游 | 备注 |
|---|---|---|---|---|---|
| `luci-app-WTModem` | 内置蜂窝控制器（信号/小区/温度/APN/SIM/IMEI/锁频） | **Apache-2.0** | 794 KB / 58 文件 | Manper rebuild | **含 `net_status_MT5700M.htm` + `zinfo_mt5700.sh` → 支持我们这颗模组** |
| `luci-app-zmodem` | 原始蜂窝控制面板 | **Apache-2.0** | 732 KB / 53 文件 | `Zy143L/luci-app-zmodem` ★19，2023-11 停更 | 面向 RM520N |
| `luci-app-ModemATSD` | AK68 控制器（ATS 后台送 AT） | **Apache-2.0** | 653 KB / 38 文件 | README 署名 **By Manper 20241102** | 含 `modem5700-AK68.lua` |
| `luci-app-cellscan` | 基站/邻区扫描 + EARFCN→band 映射 | **GPL-3.0** | 56 KB / 8 文件 | `newton-miku/luci-app-cellscan` | 作者同款，"for NRadio-C8 660/668" |
| `luci-app-Smstrun` | 短信转发 | ⚠️ **无 LICENSE** | 49 KB | 未标 | 含二进制 `sms_tool2` |
| `luci-app-Secondsystem` | 双系统(A/B 槽)切换器 | ⚠️ **无 LICENSE** | 41 KB | 未标 | 含 `smstrun.py`、`sms_tool2` |

`luci-app-WTModem` 是**自包含全家桶**：除 LuCI 前端外还自带
`root/usr/bin/sendat`、`root/usr/share/modem/{atcmd.sh,delatcmd.sh,zinfo.sh,zinfo_mt5700.sh,mt5700m.sh,rm520n.sh,autofreqlock.sh,netmodeled.sh,ipcheck.sh,pingCheck.sh}`、
`root/etc/init.d/modeminit`、`root/etc/config/{modem,apninfo}`，以及一堆附加物：
`QFirehose`(110 KB, Quectel 刷机)、`RMUnlock`(304 KB, Quectel 解锁)、`sms_tool2`、
`smstrun.py`、`adbunloc.py`、`httpapi.py`、`rsrp2rssi`、`bdinfo1/bdinfoemmc`，
以及运营商专用脚本 `a.sh/cgsys1.sh/dxzf.sh/gjmy.sh/l2tp-sim.sh/disl2tp-sim.sh/sll.sh`。

## 3. 与我们现状的差距（按 AT 命令对比）

我们的 `usr/bin/mt5700-at` 已用：
`AT^C5GOPTION? AT^CHIPTEMP? AT^DSFLOWQRY AT^FASTDORM? AT^HCSQ? AT^HFREQINFO? AT^ICCID?
AT^MONSC AT^SETMODE? AT^SIMSQ? AT^TDPCIELANCFG? AT^TDPMCFG? AT^VERSION? AT+CEREG? AT+CEUS?
AT+CFUN? AT+CGATT? AT+CGDCONT? AT+CGMI AT+CGMM AT+CGMR AT+CGPADDR AT+CIMI AT+CNUM AT+COPS?
AT+CPIN? AT+CPMS? AT+CSQ`

厂商 `zinfo_mt5700.sh` 额外用到、**我们还没有的**：

| 命令 | 用途 | 差距 |
|---|---|---|
| `AT^CASCELLINFO?` | 服务小区 + 邻区详细列表 | 我们只有 `AT^MONSC`（粗） |
| `AT^DSAMBR` | 上下行 AMBR（速率上限） | 缺 |
| `AT^EONS` | 运营商全名 | 缺 |
| `AT+CGEQOSRDP` | QoS 参数 | 缺 |
| `AT+CGSN` | IMEI 读取（面板还带"修改 IMEI"开关） | 缺（有风险，建议只读） |

**好消息**：这些和我们的同一族（展锐/UNISOC 私有 `AT^` 命令），`AT^CHIPTEMP?`/`AT^ICCID?`/
`AT^HFREQINFO?`/`AT^MONSC` 我们已经有了 → **补差距的成本很低，不需要引入整个包**。

## 4. 加入构建的三个阻碍

1. **Lua 运行时缺失（最大阻碍）**
   这些应用是 `luasrc/` 的 **Lua CBI**；而我们的镜像是纯 ucode/JS（`.config` 里
   `CONFIG_PACKAGE_lua is not set`，manifest 里没有 `luci-compat`/`luci-lua-runtime`）。
   要跑起来必须加：`lua` + `luci-compat` + `luci-lua-runtime` +（部分应用）`luci-lib-nixio`、
   `lua-cjson`。这些包在 luci feed 里**存在**（已确认），但等于给固件塞回一套老 Lua 栈。
2. **无用二进制**：`RMUnlock`(304 KB)+`QFirehose`(110 KB) 是给移远模组的，对 MT5700M 零价值。
3. **职责冲突**：它自带 `modeminit`/`sendat`/`zinfo*`/`cpe-pwr` GPIO 操作，会与我们已有的
   `mt5700-*`（`mt5700-sim-check`/`mt5700-wan-check`/`mt5700-modem-restart`）以及
   `fanctl`/`ledctl` 抢同一批 GPIO/接口，必须裁剪。

## 5. 建议

**方案 A（推荐）——零新增依赖，只补能力**
把上面 5 条缺的 AT 命令吃进 `usr/bin/mt5700-at`（只读为主），再按需加一个 LuCI 页面
（ucode/JS，跟着现有 `luci-app-commands` 走即可）。不动 Lua 栈、不进二进制、不冲突。

**方案 B（要"厂商那种一页看全"的面板）——只挑 `luci-app-WTModem`**
- 保留：`luasrc/` + `root/usr/share/modem/zinfo_mt5700.sh` + `sendat` + `net_status_MT5700M.htm`
- 砍掉：`QFirehose`/`RMUnlock`/`sms_tool2`/运营商专用脚本/`modeminit`（避免抢 GPIO 和 WAN）
- 代价：`lua`+`luci-compat`+`luci-lua-runtime`（约 1 MB+），以及长期维护一份老 Lua 应用

**方案 C——只挑 `luci-app-cellscan`**
GPL-3.0、56 KB，做基站扫描。仍需 Lua 栈，且 AT 逻辑偏移远
（脚本里 `PROGRAM="RM520N_CELLSCAN"`），要改成展锐命令。

> 采用方案 B/C 时注意 GPL-3.0 的传染性（cellscan）与"无 LICENSE 文件"的风险（Smstrun/Secondsystem）。
> 另外那个仓库是**整棵 OpenWrt 树**（178 MB），不要整体 fork，只把目标包拷进 `files/` 或自建 feed。

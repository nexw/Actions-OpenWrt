# RFC-001：NRadio C8（WT9104 / C8-688）整机固件重建 —— 走"原生 OpenWrt 栈"

- 状态：**Draft，待评审**
- 作者：Johnny（+ AI 协作）
- 日期：2026-10-01
- 关联：`docs/refs/device-baseline.md`（实机基线）、`docs/refs/mt7981b-nradio-c8-668gl.immortalwrt.dts`、`docs/refs/platform.filogic.immortalwrt.sh`、`docs/refs/02_network.immortalwrt.sh`、`docs/refs/01_leds.immortalwrt.sh`、`docs/refs/emmc.sh`
- 施工仓库：`nexw/Actions-OpenWrt`（当前是 P3TERX 模板 + Cudy TR3000 目标）

---

## 1. 背景

现机跑的是厂商 `Mwrt @Manper-5.1.0`（immortalwrt-21.02 血统 + MTK SDK 5.4.255 内核 + 私有用户态）。实测问题：

1. **数据面不原生**：5G 模块（TD Tech MT5700M-CN）自己做 NAT+DHCP（`192.168.8.1`），路由器 `eth1` 只是它的下游 DHCP client → **双层 NAT**；模块的 USB NCM 口（`eth2`）自开机 0 字节，完全闲置；拨号依赖厂商脚本 + 模块内部状态。
2. **驱动面不原生**：WiFi 走厂商 `mt_wifi/mtk_warp`，Offload 走 `mtkhnat`，交换机被厂商驱动托管，DHCP/DNS 被塞进私有 netns（`dhns`）。
3. **私有件多且不可控**：`quickstart`、`at-server`（`:8765` 的 AT WebSocket **无鉴权**）、`httpapi`、`timecontrol/webrestriction/weburl/ddnsto/...`、`docker`（vfs 驱动、0 容器）、垃圾静态路由。
4. 好消息：**immortalwrt master / openwrt main 已官方收录本机**（`nradio_c8-668gl`），DTS/分区/刷机逻辑都齐；本机 A/B 双槽 + U-Boot env `boot_system` 天然支持安全回滚。

## 2. 目标 / 非目标

**目标**
- G1 系统层原生化：immortalwrt 主线栈（netifd/uci/LuCI/fw4/dnsmasq/mt76），清掉私有件。
- G2 数据面原生化：5G 数据路径"可控、可观测、单层 NAT（或明确的双层 NAT 且可解释）"。
- G3 保留厂商 U-Boot / GPT / fip / factory / bdinfo / A-B 槽，**不刷引导**，任何时刻可一键回滚。
- G4 出厂身份可保留：`fac_mac`（`FC:83:C6:xx:xx:xx`）、WiFi EEPROM（`factory`）、module IMEI（`bdinfo`）。
- G5 可重复构建：CI 产物可复现（pin commit + git 化补丁）。

**非目标（本期）**
- 不动 U-Boot/fip/GPT 分区表；不追 MT7981 主线 kernel 6.12 的新特性（可作后续 RFC）。
- 不做模块固件升级/降级（TD Tech 固件不在本期范围）。
- 不迁移无关业务（Docker/alist 等按需在 P5 决定）。

## 3. "更原生"的定义：三层阶梯

| 层 | 现状 | 目标态 | 收益 | 风险 |
|---|---|---|---|---|
| **L1 系统层** | 私有 Mwrt + 私有用户态 | immortalwrt master 主线（mt76 + fw4 + dnsmasq + netifd） | 可维护、可升级、行为可预期 | 低（有 A/B 回滚） |
| **L2 驱动层** | `mt_wifi`/`mtkhnat`/厂商 switch | `kmod-mt7915e`(mt76) + DSA(mt7531) + flow-offload | 上游修复、WiFi 稳定、调试工具齐全 | 中（WiFi 校准/吞吐需回归） |
| **L3 数据面** | 模块 NAT + 双层 NAT，USB NCM 闲置 | 见下方 4 选项 | 单层 NAT / 原生 IPv6 / 端口映射可用 | 中~高（依赖模块能力，部分需写操作） |

### L3 数据面 4 个选项

| 选项 | 做法 | 结果 | 风险 | 需要写操作？ |
|---|---|---|---|---|
| **D0** 保持现状拓扑 | 模块继续 NAT，路由器 `eth1` 标准 `proto dhcp`；只做 L1/L2 替换 | 双层 NAT 仍在，但叠加层全清、可观测 | 最低 | 否 |
| **D1** 模块 IP Passthrough / DMZ | 模块侧把 WAN IP/端口直通给路由器 WAN MAC | **单层 NAT**，端口映射/UPnP 可用 | 中：模块侧参数需勘探（`AT+CEUS`/`^TDPCIELANCFG`/`^TDPMCFG` 或模块 Web/协议）；写错需回滚 | 是（需授权） |
| **D2** 走 USB 数据面 | 让模块的 `cdc_ncm`（`eth2`）成为 WAN（标准 usbnet + dhcp） | 数据面回到"标准 USB 网卡"，与板载 GE 解耦 | 中：当前 NCM 无载波/0 流量，需查明模块侧为何不启用（可能与 `AT^SETMODE`/`CEUS` 有关） | 是（需授权） |
| **D3** 切 USB 组合到 ECM/MBIM/QMI | 模块 `bNumConfigurations=2`，尝试切到 ECM/MBIM/QMI，用 `uqmi`/`umbim` 原生拨号 | 最"原生"：路由器自己做 IP/NAT/ND，模块退化为纯 Modem | **高**：TD Tech/UNISOC 平台 QMI 支持未知（现 5 个 `ff/06` 口全是串口，无 QMI 特征）；组合切换失败可能需重插/串口恢复 | 是（需授权） |

**建议路线：D0 先落地（把整机换成原生栈并稳定运行）→ 在同一固件上做 D1/D2 可行性实验 → 通过再切 D1（首推）或 D2/D3。** 理由：D0 零模块风险且立刻消除 90% 的"不优雅"；D1 用最小改动拿到单层 NAT；D3 收益最大但不确定性也最大，不应作为首刷前提。

## 4. 阶段计划

> 约定：**P0 之前不对整机做任何写操作**；所有需要写整机/模块的动作都单独列出并等你逐条批准。

### P0 基线与回滚准备（只读 + 本地备份，0.5 天）
- 固化基线：把 `docs/refs/device-baseline.md` 的采集命令整理成 `scripts/c8-baseline.sh`（只读），CI 与本地都可跑。
- 备份：`u-boot-env`(p2)、`factory`(p3)、`bdinfo`(p4)、`fip`(p5)、A 槽 `kernel/rootfs`(p6/p7) 的头部校验、GPT 表 → 落到本地/私有存储（**只读 dd**）。
- 确认引导语义：A/B 槽切换方式（`fw_setenv boot_system 0/1`）、串口救砖可用性、U-Boot tftp 是否可用。
- 待核实项（见 §9）：`rootfs_data` vs `app_data`、LAN DHCP/DNS 归属（`192.168.66.251` 是谁）、模块数据面物理链路。
- 产出：`docs/refs/rollback-plan.md`（一页纸的回滚 SOP）。

### P1 仓库改造 + 首版产物（不刷机，1~2 天）
见 §5 的文件级清单。产出：GitHub Actions 里 3 个 release 资产（`*-squashfs-sysupgrade.bin`、`*-initramfs-kernel.bin`、manifest），**先不刷**。
验收：
- `openwrt/bin/targets/mediatek/filogic/` 里出现 `nradio_c8-668gl` 产物；
- `sysupgrade.bin` 解包后：`sysupgrade-nradio_c8-668gl/` 含 `CONTROL`/`kernel`(FIT)/`rootfs`(squashfs)；
- DTS 与本机实测 GPIO/分区一致（对照 §6 表）。

### P2 首刷 + 网络可用性（0.5 天，需授权写操作）
- 用厂商 U-Boot 现成的 A/B 机制：**写 B 槽（`kernel_2nd`+`rootfs_2nd`）**（与上游 `platform.sh` 的 `nradio,c8-668gl` 分支一致）→ 保留 A 槽出厂固件作为回滚。
- 先接串口（115200）在场，确认 `sysupgrade` 正常；验收：能起来、能上网（D0 方式）、`lan1-3/eth1` 链路正确、WiFi 双频可连、LED 合理、风扇可控、温度正常。
- 回滚演练：`fw_setenv boot_system` 切回 A 槽，确认能回到出厂固件。

### P3 数据面实验（1~2 天，需逐条授权写操作）
- 在**不重刷固件**的前提下做：
  1. 只读勘探：模块 USB 全套描述符（两个 configuration）、`AT^SETMODE=?/^TDPCIELANCFG=?/CEUS=?` 的能力面、模块侧是否有 passthrough/DMZ 概念；
  2. D2 实验：让 `eth2` 起来（`ip link set eth2 up` + dhcp 探测）看模块是否给 NCM 侧载波与租约；
  3. D1 实验：按勘探结果改模块参数，验证路由器 WAN 是否拿到 `10.6.223.136` 级别地址；
  4. 失败即回滚到 §基线表里记录的模块参数（`SETMODE=4 / TDPCIELANCFG=2 / TDPMCFG=1,0,0,0 / CEUS=0`）。
- 产出：`docs/refs/l3-dataplane-findings.md` + 固化后的最终方案（D1 或 D2 或 D3 或保持 D0）。

### P4 落地与业务迁移（1 天 + 观察期）
- 按 P3 结论固化 WAN 配置（uci 模板进 `files/`）、DNS/DHCP 接管（标准 dnsmasq）、防火墙/fw4、IPv6（原生 PD/RA）、UPnP/端口映射策略。
- 业务：`ttyd`（若要）、`samba4`、`docker`（建议改 `overlay2`，或明确不用）、5G 状态监控（只读轮询 TCP 20249 的 AT，脚本化，不装厂商私有件）。
- 安全收口：删掉无鉴权 AT WebSocket；SSH 仅 LAN；关闭不需要的 21/445/8888 等。

### P5 稳定性验收（7 天观察）
- 指标见 §8；产出验收报告 + 是否回滚的结论。

## 5. 仓库改造清单（文件级）

### 5.1 `.github/workflows/openwrt-builder.yml`
```diff
-  REPO_URL: https://github.com/openwrt/openwrt.git
-  REPO_BRANCH: main
-  BUILD_BRANCH: v24.10.2
-  COMMIT_ID: 594da824a4f2f9582941e612f1a912773d43ff1d
+  REPO_URL: https://github.com/immortalwrt/immortalwrt.git
+  REPO_BRANCH: master
+  # 可复现：pin 到 tag/commit（评审时确定，例：openwrt-24.10 分支或某个 commit）
+  BUILD_BRANCH: <pin>
+  COMMIT_ID: ""            # 不再 cherry-pick
```
- 理由：`v24.10.2` 里**没有** `nradio_c8-668gl`；immortalwrt master 有，且其 `platform.sh/02_network/01_leds` 已覆盖本机（含 `bdinfo fac_mac` 读取路径），维护成本最低。
- 备选：openwrt main（也有该机型），但 `platform.sh` 的 `CI_DATAPART` 等细节需另行核对；本机 DTS 与 immortalwrt 版差异更小。
- 建议同时加：`actions/cache` 缓存 `ccache`，把每轮构建从 ~2.5h 压到 ~1h（Actions 免费额度 2000 min/月，构建轮次敏感）。

### 5.2 补丁管理
- 现状：`patch.tar.gz` / `patch2.tar.gz`（不透明）。
- 改为：`patches/` 目录下 git 可 diff 的补丁 + `diy-part2.sh` 里 `git apply`（或保留 tar 但改为 `tar` 内是文本补丁）。**这是我目前评审的第一步收益**：别人/未来的你能看到"改了什么"。

### 5.3 `.config`
- `CONFIG_TARGET_mediatek_filogic_DEVICE_nradio_c8-668gl=y`（替换 `cudy_tr3000-256mb-v1`）
- 追加（数据面与调试）：
  - `kmod-usb-net-cdc-ncm`、`kmod-usb-net-cdc-ether`、`kmod-usb-net-cdc-mbim`、`kmod-usb-net-qmi-wwan`、`kmod-usb-serial-option`、`kmod-usb-net-rndis`（D2/D3 实验与兜底）
  - `uqmi`、`umbim`（若 D3 成立）、`picocom` 或 `socat`（AT 实验）
  - `kmod-usb3`、`automount`（上游默认已带）
  - 可视化：`luci-app-commands`/`luci-app-ttyd`（可选）
- 移除（本机无用且体积大）：OpenClash 相关（除非你要在 C8 上跑）、`cudy` 专属包。
- 明确选择：是否保留 `docker/dockerd`（厂商版是 vfs + 0 容器；如要跑容器，建议 24.10 的 `dockerd` + `overlay2`，但 A 槽 256MB 不够，必须用 B 槽 6.7GB）。

### 5.4 DTS：`target/linux/mediatek/dts/mt7981b-nradio-c8-668gl.dts`
以 immortalwrt 版为基线（已在 `docs/refs/`），按本机实测修正：

| 改动点 | 内容 |
|---|---|
| WiFi LED | `wlan` 从 `&pio 13` 改为 **`&pio 34`**（实测） |
| CPE 选择 | `cpe-sel0` 从 `&pio 30` 改为 **`&pio 29`**，新增 `cpe-sel1 = &pio 30` |
| 风扇 | 新增 `fan-hw = &pio 27`、`fan-fg = &pio 28` gpio-export；新增 `pwm-fan`（`pwms=<&pwm 0 40000 0>`、`cooling-levels=<64 128 192 255>`）+ `cpu-thermal` 冷却映射（厂商是脚本控风扇，我们改成内核 thermal 控） |
| 按键 | 去掉 `wps`（本机 DT 无此键），保留 `reset = &pio 1` |
| LED 命名 | 采用上游 `blue:power / blue:indicator-0 / blue:indicator-1 / blue:wlan`（与 `01_leds` 的 `blue:wlan`、`blue:indicator-0` 对齐） |
| nvmem | 确认/补齐 `bdinfo` 文本分区（fac_mac/imei），供 `mmc_get_mac_ascii` 使用 |
| 分区 | 不改 GPT；仅在 DTS 里声明 nvmem 解析（`u-boot-env`/`factory`/`bdinfo`） |

### 5.5 `board.d` / 刷机逻辑
- `02_network`：本机 board_name（`HCMT7981-emmc`）**不在**上游 case 里 → 要么把 DTS 的 compatible 对齐为 `nradio,c8-668gl`（推荐，兼容上游全部逻辑），要么给上游文件加一条本机 board_name 分支（补丁）。**推荐前者**：DTS 里 `compatible = "nradio,c8-668gl", "mediatek,mt7981"`，同时保留实际硬件差异（LED/GPIO）——但这会影响 `board_name` 判定与回滚时的识别，需要评审决定（见 §9-Q1）。
- `01_leds`：本机 LED 名称/含义按实测确认后微调。
- `platform.sh`：核实 `CI_DATAPART="rootfs_data"` 在本机 GPT（只有 `app_data`）下的行为；若 `emmc_do_upgrade` 强依赖该分区，则加兼容分支（`nradio_c8-688`）或在 DTS/GPT 层面把 `app_data` 视作 data 位。

## 6. 刷机与回滚（关键安全设计）

- **只刷 B 槽**（`kernel_2nd` p8 + `rootfs_2nd` p9），与上游 `platform.sh` 的 `nradio,c8-668gl` 分支一致 → A 槽出厂固件保持原样。
- 回滚：`fw_setenv boot_system 0`（或反向）后重启，走 A 槽出厂固件。串口 115200 常接。
- 刷前必做：`sha256` 记录 A 槽 kernel/rootfs 头部 + GPT 表；确认 `sysupgrade` 产物是 `ustar`（上游 check 逻辑要求）。
- 不做：不写 `fip`/`u-boot-env`（除切换 `boot_system` 这一条）、不重建 GPT、不动 `factory`/`bdinfo`。
- 模块侧写操作：只在 P3 进行，逐条授权，且每条都记录旧值（§基线表）。

## 7. 风险矩阵

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| 首刷变砖 | 低 | 高 | 只写 B 槽 + 串口到场 + A 槽回滚 |
| DTS 差异导致外设不可用（LED/按键/风扇/交换机口） | 中 | 中 | P1 静态比对 §6 表；P2 逐项验收 |
| WiFi 由 `mt_wifi` 换 `mt76` 后校准/吞吐异常 | 中 | 中 | 保留 `factory` 分区与 `nvmem eeprom` 引用；准备 WiFi 回归测试 |
| 模块参数写入后不可恢复 | 中 | 高 | 先记录基线值；只用 `=0/1/2` 这类已声明的取值；必要时串口/重插恢复 |
| D3（ECM/MBIM/QMI）不成立 | 中高 | 低（仅浪费实验） | 先 D1/D2；D3 作为可选加分项 |
| `app_data` vs `rootfs_data` 不匹配导致配置写入失败 | 中 | 中 | P0 读 `emmc.sh`/`emmc_do_upgrade` 实现，必要时打分支补丁 |
| Actions 额度/构建时长 | 高 | 低 | pin commit + ccache 缓存 + 减少重跑 |

## 8. 验收指标（P5）

1. **数据面**：`traceroute 223.5.5.5` 首跳是否只在模块内网一次；若走 D1，路由器 WAN 直接持有 `10.6.223.136`（或公网 v6）且 `nft list ruleset` 里只剩一层 masquerade。
2. **IPv6**：LAN 拿到原生 `240a:` 前缀（PD）或明确说明为何仍走模块 NAT66。
3. **性能基线对比**（与现状同点测）：`iperf3` 上下行、`ping` 平均/抖动、WiFi 2.4/5G 吞吐。
4. **稳定性**：7 天无重启、无 `No response from modem` 类噪音、内存无泄漏、SoC 温度与风扇曲线正常。
5. **纯净度**：`ps` 无 quickstart/at-server/httpapi/dhns；`uci show` 无私有配置；`nft` 暴露面仅剩必需端口。
6. **可回滚**：从新固件一键回 A 槽出厂固件（演练记录留档）。

## 9. 待确认 / 待授权

- **Q1（需你决定）**：目标机型标识用上游 `nradio,c8-668gl`（改 DTS compatible，吃上游全部逻辑）还是新增 `nradio,c8-688`（保留本机真实 SKU，但需要给上游文件打多处小补丁）？
- **Q2（需你确认）**：源码树选 **immortalwrt master**（推荐）还是 openwrt main？是否接受 pin 到某个 tag/commit 牺牲"最新"换可复现？
- **Q3（需你确认）**：整机 WAN 口是否有插网线？我需要用它判定"模块数据面走板载 GE（推断）还是外部上联"，也影响 D1/D2 方案。
- **Q4（需你授权，写操作）**：P2 首刷（写 B 槽）。
- **Q5（需你授权，写操作）**：P3 模块参数实验（`AT+CEUS` / `AT^TDPCIELANCFG` / USB 组合切换），每次单条、可回滚。
- **Q6（需你确认）**：是否需要在这台 C8 上继续跑 Docker / alist / samba 等业务（决定 B 槽容量与包选择）。
- **Q7（需你确认）**：LAN 的 DHCP/DNS 现在到底谁在服务（`dhcp.lan.ignore=1`、leases 为空、DNS 指向 `192.168.66.251`）。接管方式需按现状定。

## 10. 成本与里程碑

| 阶段 | 工作量 | CI 成本 |
|---|---|---|
| P0 基线/回滚准备 | 0.5 天 | 0 |
| P1 仓库改造 + 首版产物 | 1~2 天 | 2~4 轮构建（每轮 1~2.5h） |
| P2 首刷 + 网络验收 | 0.5 天 | — |
| P3 数据面实验 | 1~2 天 | 0~2 轮（如需改 dts/包） |
| P4 落地 + 业务迁移 | 1 天 | 1~2 轮 |
| P5 稳定性观察 | 7 天（被动） | 0 |

合计**约 4~6 个工作日**（不含观察期）；Actions 额度约需 6~10 轮构建，建议开 ccache 缓存。

## 11. 最小下一步（等你一句话即可开工）

1. 答复 Q1/Q2/Q3/Q6/Q7；
2. 我随后提交 P1 的第一批改动（`.config` + workflow 变量 + 把 patch.tar.gz 换成文本补丁 + DTS 基线文件入库），**不动整机**；
3. P1 产物出来后，再单独向你申请 P2 的首刷窗口。

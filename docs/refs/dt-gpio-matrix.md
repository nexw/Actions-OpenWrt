# WT9104 / NRadio C8-688：按键 · LED · GPIO 三方对照

数据来源（全部本地反编译，命令可复现）：
- **官方固件** `C8-688-WT9104_1.9.4.n2.c3_flash.bin` → 内嵌板级 DTB，`model = "HC-WT9104"`，`compatible = "HCMT7981-EMMC","mediatek,mt7981-emmc-rfb"`
- **现网固件** Manper Mwrt 5.1.0 → `/sys/firmware/fdt`（厂商魔改版）
- **上游** immortalwrt master `mt7981b-nradio-c8-668gl.dts`

## 1. 按键（gpio-keys）

| 名称 | 官方 DTB | 现网(Manper) DTB | 上游 DTS | 结论 |
|---|---|---|---|---|
| `reset` | ✅ pio **1**，code `0x198`(KEY_RESTART) | ✅ 同左 | ✅ 同左 | 一致 |
| `wps` | ✅ pio **9**，code `0x211`(KEY_WPS_BUTTON) | ❌ **缺失** | ✅ 同官方 | 现网版被删；重建应恢复 |
| 第 3 颗 | ❌ 无 | ❌ 无 | ❌ 无 | **DT 未定义**，见 §4 |

官方工厂测试配置同样只声明两颗：`oem/WT9104/config/99_factory_check` → `factory_check.button.buttons='reset wps'`。

## 2. LED（gpio-leds）

| 用途 | 官方 / 现网标签 | GPIO | 上游 DTS | 结论 |
|---|---|---|---|---|
| 状态 | `hc:blue:status` | pio **10** | `blue:power` = pio 10 | GPIO 一致 |
| 组网模式 5 | `hc:blue:cmode5` | pio **11** | `blue:indicator-0` = pio 11 | GPIO 一致 |
| 组网模式 4 | `hc:blue:cmode4` | pio **12** | `blue:indicator-1` = pio 12 | GPIO 一致 |
| WiFi | `hc:blue:wifi` | pio **34**(0x22) | `blue:wlan` = **pio 13** ❌ | **上游 GPIO 错误，必须改为 34** |

## 3. GPIO 导出（板级电源/风扇/模块选择）

| 功能 | 官方 DTB | 现网 DTB | 上游 DTS | 结论 |
|---|---|---|---|---|
| `cpe-pwr`（模块供电） | pio **31**, output 0 | pio 31, output 0 | pio 31, output 0 | 一致 |
| `fan-hw`（风扇电源） | pio **27**, output **0** | pio 27, output **1** | ❌ 无 | 上游缺；注意官方与现网 output 相反 |
| `fan-fg`（风扇转速反馈） | pio **28**, output 1 | pio 28, output 1 | ❌ 无 | 上游缺 |
| `cpe-sel0`（模块/SIM 选择） | pio **29** | pio 29 | pio **30** ❌ | 上游错位 |
| `cpe-sel1` | pio **30** | pio 30 | ❌ 无 | 上游缺（其 cpe-sel0 实际是 sel1） |

PWM 风扇：`pwm-fan`，`pwms=<&pwm 0 40000 0>`（25 kHz），`cooling-levels=<64 128 192 255>`，`cooling-max-state=3`。官方用硬件 PWM + `fanctrl`；现网改由 `fancts.sh` 脚本控制。

## 4. 第 3 颗按键：为什么 DT 里没有

事实：
- DT（官方+现网）只有 2 个 `gpio-keys`；官方工厂配置也只写 `reset wps`。
- 但官方 rootfs 里有 `etc/rc.button/power`（松开=关机）与 `etc/rc.button/rfkill`（无线开关）处理器 → **存在"power/rfkill 型按键"的用户态语义**。
- `ledctrl.sh` 里有完整 mesh 状态机与 `cmode4/cmode5`（组网指示灯）+ `uci mesh.config.enabled` → "一键组网"确实存在，但**未见独立按键**；WPS 处理器用的是 MTK 专有 `WscConfMode=4`（可同时承载 WPS/组网配对）。
- 板级"键盘 MCU"线索：U-Boot env `kp_model=WT9104`、`kp_soft_ver=109040106`，官方仓库含 `nradiorecovery kpimg`。注意 `usr/sbin/kpshd` 经反编译确认是 **TCP 50001 的 ATE(GnuTLS-PSK) 远程 shell**，与按键无关，勿混淆。

三种可能（待实测排除）：
1. 第 3 颗是 **power 键**，由 PMIC/其它驱动上报，DT 未声明（最可能）；
2. 第 3 颗是 **rfkill/无线开关**（滑动开关或轻触键，走 `rfkill` 而非 gpio-keys）；
3. 第 3 颗复用 **WPS 键的长按**（短按 WPS、长按组网），并非独立 GPIO。

验证方法（见 `scripts/c8-hw-inventory.sh` §1/§6）：`cat /proc/bus/input/devices`、`dmesg | grep -i key`、逐个按键时 `cat /sys/class/gpio/*/value` 与 `logread -f`，即可定位。

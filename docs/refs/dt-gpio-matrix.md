# WT9104 / NRadio C8-688：按键 · LED · GPIO 三方对照

数据来源（全部本地反编译，命令可复现）：
- **官方固件** `C8-688-WT9104_1.9.4.n2.c3_flash.bin` → 内嵌板级 DTB，`model = "HC-WT9104"`，`compatible = "HCMT7981-EMMC","mediatek,mt7981-emmc-rfb"`
- **现网固件** Manper Mwrt 5.1.0 → `/sys/firmware/fdt`（厂商魔改版）
- **上游** immortalwrt master `mt7981b-nradio-c8-668gl.dts`
- **设备自带 A 槽官方固件**（2026-10-02 补挖，最权威：它就是本机原厂出货的那份）
  `OpenWrt 21.02-SNAPSHOT 1.9.4.n1.c6`，kernel 在 `mmcblk0p6` 的 FIT 里，
  `images/fdt-1` description = `ARM64 OpenWrt nradio-wt9104 device tree blob`，
  `model = "HC-WT9104"`。复现：
  ```sh
  ssh root@192.168.66.1 'dd if=/dev/mmcblk0p6 bs=1k count=4096' > aslot-kernel.img
  python3 -c "import struct;d=open('aslot-kernel.img','rb').read();o=d.find(b'\\xd0\\x0d\\xfe\\xed',0x100000);print(hex(o),struct.unpack('>I',d[o+4:o+8])[0])"
  # 按上一步的 offset/size 切出 dtb，再用 dtc -I dtb -O dts 反编译
  ```
  产物不入库（`.gitignore` 里有 `aslot-official-wt9104.dts`），约定同 `vendor-fdt.dts`。

## 1. 按键（gpio-keys）

| 名称 | 官方 DTB | 现网(Manper) DTB | 上游 DTS | 结论 |
|---|---|---|---|---|
| `reset` | ✅ pio **1**，code `0x198`(KEY_RESTART) | ✅ 同左 | ✅ 同左 | 一致 |
| `wps` | ✅ pio **9**，code `0x211`(KEY_WPS_BUTTON) | ❌ **缺失** | ✅ 同官方 | 现网版被删；重建应恢复 |
| 第 3 颗 | ❌ 无 | ❌ 无 | ❌ 无 | **DT 未定义**，见 §4 |

官方工厂测试配置同样只声明两颗：`oem/WT9104/config/99_factory_check` → `factory_check.button.buttons='reset wps'`。

## 2. LED（gpio-leds）

四份来源三处一致，**未发现 GPIO 定义出入**：

| 用途 | 设备自带官方 DTB `HC-WT9104` | 官方 flash.bin DTB | 现网 Manper | 上游 DTS | 我们仓库 DTS | 实测 |
|---|---|---|---|---|---|---|
| 状态/电源 | pio **10** (0x0a) AL | pio **10** | pio **10** | `blue:power` pio **10** | pio **10** | ❌ 脚在动、灯不亮（见 §2.1） |
| 组网模式 5 | pio **11** (0x0b) AL | pio 11 | pio 11 | `blue:indicator-0` pio 11 | pio 11 | ✅ 正常 |
| 组网模式 4 | pio **12** (0x0c) AL | pio 12 | pio 12 | `blue:indicator-1` pio 12 | pio 12 | ✅ 正常 |
| WiFi | pio **34** (0x22) AL | pio 34 | pio 34 | pio **13** ❌ | pio **34** ✅ | ✅ 正常 |
| `wps` 按键 | pio **9** (0x09) AL | pio 9 | ❌ 缺 | pio 9 | pio 9 | 脚在，实物未见按键 |

> 上游 DTS 的 WiFi LED `pio 13` 是错的（本机实测 `pio 34`），由 `patches/0001` 修正。
> `wps = pio 9` 官方 DTB 里确实存在（Manper 版被删），所以保留它是正确的。

### 2.1 `blue:power` / pio10：软件无问题，灯不响应

2026-10-02 实测结论（软件侧已排除干净）：

| 检查 | 结果 |
|---|---|
| 写 `brightness=1` | `gpio-10` → `out lo` |
| 写 `brightness=0` | `gpio-10` → `out hi` |
| `trigger=timer` 1s/1s | pin10 每秒 lo/hi 交替（即 blink 时确实在翻转） |
| pinmux | `pin 10 (WO_JTAG_JTDI): GPIO`，未被外设占用 |
| pinconf | 与能正常点亮的 pin11/pin12 **完全一致**（2 mA、output enabled、pulldown） |
| 其它空闲脚扫描 | pio 0/3/4/5/6/9/26/35 逐个驱动，均未点亮该灯 |

→ 三份 DTB 都写 pio10、且 pio10 电平确实在翻转，**但实物不亮**。
最可能是**该颗 LED 未贴片/损坏**，或实物丝印为 Power 的灯不走 pio10（DTB 与实际板级 net 不符）。
待确认，勿在无实测依据时改 DTS。

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

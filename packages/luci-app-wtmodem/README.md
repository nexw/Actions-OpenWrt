# luci-app-wtmodem（本仓库裁剪版）

> 上游包名是 `luci-app-WTModem`（含大写）。本仓库改成全小写 `luci-app-wtmodem` ——
> 25.12 用 apk 打包，包名保持传统全小写更稳妥；功能与菜单显示不受影响。


内置蜂窝模组面板。上游为 Manper 的 rebuild 版，取自
[zhongweijie95/NRadio-CPE-NO2](https://github.com/zhongweijie95/NRadio-CPE-NO2)
的 `feeds/luci/applications/luci-app-WTModem`，原始蜂窝程序源自
[Zy143L/luci-app-zmodem](https://github.com/Zy143L/luci-app-zmodem)。
许可证 **Apache-2.0**（见 `LICENSE`）。

## 本仓库改了什么

目标：**只要只读面板**，不碰 GPIO、不改网络，避免与现网（IP 直通）配置互相打架。

### 删掉的

| 类别 | 文件 | 原因 |
|---|---|---|
| 预编译 ELF | `sendat`、`QFirehose`、`RMUnlock`、`sms_tool2`、`bdinfo1`、`bdinfoemmc`、`rsrp2rssi`、`moimei`、`mopdu`、`libbdinfo.so*` | 无源码；`QFirehose`/`RMUnlock` 是移远专用（对 MT5700M 零价值） |
| 数据面守护 | `mt5700m.sh`、`netmodeled.sh`、`rm520n.sh`、`500U.sh` | 会覆盖本仓库的 IP 直通/NDISDUP 配置 |
| 原 init.d | `modeminit` | 会抢 `cpe-pwr`/USB/灯，并拉起上面那些守护 → 换成只读的 `modeminfo` |
| 运营商专用脚本 | `a.sh`、`dxzf.sh`、`gjmy.sh`、`cgsys1.sh`、`l2tp*.sh`、`disl2tp-sim.sh`、`sll.sh`、`led.sh`、`BLUE4WAN.sh`、`setppstoken.sh`、`setsmstitle.sh` | 与本设备无关 |
| SMS 相关 | `smstrun.py`、`smstrun-title.conf`、`httpapi.py` | 见仓库 `docs/` 里的 SMS 方案（另做） |
| 其它 | `apninfo`、`autofreqlock.sh`、`ipcheck.sh`、`pingCheck.sh`、`enableipv6.sh`、`cellscan.sh` | 依赖已删组件或功能重复 |

### 加回来的 / 新写的

| 文件 | 说明 |
|---|---|
| `root/usr/bin/sendat` | 原版是 ELF；改写为 shell，直接调用仓库自带的 `/usr/bin/mt5700-at` |
| `root/etc/init.d/modeminfo` | 只发布 `/tmp/modconf.conf`（面板据此选模板）与 `/tmp/sim_sel`；**不上电、不配网** |
| `root/usr/bin/5700_get_zbjh.sh` | 纯 shell 的载波聚合解析（保留） |

### 关键适配点：`sendat` 不回显命令

厂商的 `zinfo_mt5700.sh` 用这类管道取值：

```sh
OX=$(sendat 1 'AT^CHIPTEMP?' | grep 'CHIPTEMP' | sed -n '1p' | cut -d, -f9)
```

如果 `sendat` 回显命令，`AT^CHIPTEMP?` 会先被 `grep` 命中 → 取值错位
（实测 `OX` 变成字符串 `AT^CHIPTEMP?` → `arithmetic syntax error`）。
所以本实现与 `mt5700-at --raw` 一致：**只输出模块响应**，末尾补一行 `OK`。

因此 `zinfo_mt5700.sh` 里原本按“第 2 行是响应”写的取值，统一前移为第 1 行
（`AT+CGSN`/`AT+CIMI`/`AT^ICCID?`/`AT+CGEQOSRDP`/`AT^MONSC`/`ATI`），
并把 `cleanup()` 提到 `trap` 之前（原版 EXIT trap 触发时函数还没定义会报错）。

## 依赖

- `luci-compat` + `luci-lua-runtime`（LuCI 现在的 LuCI 是 ucode/JS，跑老 Lua CBI 需要兼容层）
- `luci-lib-nixio`（页面用 `nixio.fs.access`）
- 运行时还需要本仓库 `files/` 里的 `mt5700-at`（python3）与 `jsonfilter`/`jshn`（`5700_get_zbjh.sh`）

## 面板内容（MT5700M 实测）

`/usr/share/modem/zinfo_mt5700.sh` 采集 31 个字段写入 `/tmp/cpe_cell.file`，实测全部有值：

模组厂商/型号/固件版本、芯片温度、SIM 槽位、运营商、IMEI/IMSI/ICCID、
制式(NR-5G)、信号百分比/RSRQ/RSRP/SINR、MCC/MNC、LAC、CellID、频段+带宽、
EARFCN、PCI、APN、上下行 AMBR、QCI、载波聚合主/从波。

已知留白（模块本身不支持，脚本已优雅降级）：
- 本机号码：`AT+CNUM` 返回 `+CME ERROR: 22`（国内卡不写 MSISDN）
- `R2cc`/`R3cc`：`AT^CASCELLINFO?` 返回 ERROR → 显示 `Loss-in`

## 未包含（需要时再评估）

- 修改 IMEI：页面保留了上游的开关（默认关闭），但**不建议使用**，部分司法辖区属违法
- SMS 收发/转发：见仓库 SMS 方案文档

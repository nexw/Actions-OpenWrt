#!/bin/sh
# c8-hw-inventory.sh — 在 C8（WT9104）本机运行，只读清点 按键/LED/GPIO/风扇/交换机/模块
# 用法: ssh root@192.168.66.1 'sh -s' < scripts/c8-hw-inventory.sh
# 安全性: 全部为只读查询（cat/ls/grep/ubus/uci show），不写任何配置、不改 GPIO 方向。
echo "===== 1. 按键：内核输入设备 ====="
echo "--- /proc/bus/input/devices"
cat /proc/bus/input/devices 2>/dev/null
echo "--- dmesg 中按键相关"
dmesg 2>/dev/null | grep -iE "gpio-keys|gpio-button|input:|button|keypad" | tail -30
echo "--- rc.button 处理器"
ls -la /etc/rc.button/ 2>/dev/null
echo "--- gpio-button-hotplug 是否加载"
lsmod 2>/dev/null | grep -i button

echo
echo "===== 2. gpio-keys / gpio-leds / gpio-export（DT 定义）====="
for n in gpio-keys gpio-leds gpio_export gpio-export; do
  d=/proc/device-tree/$n
  [ -d "$d" ] || continue
  echo "--- $n"
  for c in "$d"/*/; do
    [ -d "$c" ] || continue
    b=$(basename "$c")
    label=$(tr -d '\0' < "$c/label" 2>/dev/null)
    name=$(tr -d '\0' < "$c/gpio-export,name" 2>/dev/null)
    echo "  $b  label='$label' name='$name'"
    python3 -c "
import struct,sys
for f in ('linux,code','gpios'):
    try: b=open('$c/'+f,'rb').read()
    except: continue
    print('      ',f,'=',[struct.unpack('>I',b[i:i+4])[0] for i in range(0,len(b)-3,4)])
" 2>/dev/null
  done
done

echo
echo "===== 3. 当前 GPIO 电平（gpio-export 已导出的）====="
for g in /sys/class/gpio/gpio*; do
  [ -d "$g" ] || continue
  n=$(basename "$g")
  echo "$n dir=$(cat $g/direction 2>/dev/null) value=$(cat $g/value 2>/dev/null)"
done

echo
echo "===== 4. LED 现状 ====="
for l in /sys/class/leds/*; do
  echo "$(basename $l): brightness=$(cat $l/brightness 2>/dev/null) trigger=$(cat $l/trigger 2>/dev/null | tr ' ' '\n' | grep -m1 '\[' )"
done

echo
echo "===== 5. 风扇 / 热管理 ====="
ls -la /sys/class/hwmon/ 2>/dev/null
for h in /sys/class/hwmon/hwmon*; do
  echo "$(basename $h) name=$(cat $h/name 2>/dev/null)"
  for f in "$h"/pwm* "$h"/fan* "$h"/temp*; do [ -f "$f" ] && echo "   $(basename $f)=$(cat $f 2>/dev/null)"; done
done
for z in /sys/class/thermal/thermal_zone*; do echo "$(basename $z) type=$(cat $z/type 2>/dev/null) temp=$(cat $z/temp 2>/dev/null)"; done
echo "--- 厂商风扇脚本"
ls -la /etc/init.d/fanctrl /usr/bin/fanctrl.sh /bin/fancts.sh 2>/dev/null

echo
echo "===== 6. 串口 / MCU 线索 ====="
ls -la /dev/ttyS* /dev/ttyUSB* 2>/dev/null
echo "--- 谁占用 ttyS1/ttyS2/ttyUSB*"
for p in /proc/[0-9]*; do
  pid=$(basename $p)
  for fd in $p/fd/*; do
    t=$(readlink "$fd" 2>/dev/null) || continue
    case "$t" in *ttyS1*|*ttyS2*|*ttyUSB*) echo "pid=$pid cmd=$(tr '\0' ' ' < $p/cmdline | cut -c1-60) fd=$t";; esac
  done
done 2>/dev/null | sort -u | head -20

echo
echo "===== 7. 网口 / 交换机 / 模块链路 ====="
ip -br link 2>/dev/null
echo "--- 计数器（判断 5G 数据走哪个口）"
for n in eth0 eth1 eth2 dheth0; do
  [ -e /sys/class/net/$n ] || continue
  echo "$n rx=$(cat /sys/class/net/$n/statistics/rx_bytes) tx=$(cat /sys/class/net/$n/statistics/tx_bytes) oper=$(cat /sys/class/net/$n/operstate)"
done
echo "--- 桥成员"; ls /sys/class/net/br-lan/brif/ 2>/dev/null
echo "--- 上游 ARP/路由"; ip neigh show dev eth1 2>/dev/null; ip route 2>/dev/null

echo
echo "===== 8. 模块 USB 组合 / 设备 ====="
for d in /sys/bus/usb/devices/*/; do
  [ -f "$d/idVendor" ] || continue
  echo "--- $(basename $d) $(cat $d/idVendor):$(cat $d/idProduct) $(cat $d/manufacturer 2>/dev/null) $(cat $d/product 2>/dev/null) serial=$(cat $d/serial 2>/dev/null)"
  echo "    bNumConfigurations=$(cat $d/bNumConfigurations 2>/dev/null) bConfigurationValue=$(cat $d/bConfigurationValue 2>/dev/null) bNumInterfaces=$(cat $d/bNumInterfaces 2>/dev/null)"
  for i in "$d":*; do
    [ -d "$i" ] || continue
    echo "    iface $(basename $i) class=$(cat $i/bInterfaceClass)/$(cat $i/bInterfaceSubClass) drv=$(basename $(readlink $i/driver 2>/dev/null)) net=$(ls $i/net 2>/dev/null | tr '\n' ',')"
  done
done

echo
echo "===== 9. mesh / 组网 线索 ====="
uci -q show mesh 2>/dev/null || echo "(无 mesh uci)"
uci -q show wireless | grep -iE "mesh|wds|mode|ssid" | head -20
ls /etc/init.d/ | tr '\n' ' '; echo
echo "===== 完成（本脚本未修改任何配置）====="

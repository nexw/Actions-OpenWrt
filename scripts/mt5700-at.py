#!/usr/bin/env python3
"""mt5700-at.py — TD Tech MT5700M-CN 只读状态探针 / AT 客户端

用途：
  * 在 C8（MWRT/OpenWrt）上查模块状态，替代厂商 at-server/websocket_server；
  * 也可作为新固件里"受控"的最小实现：一条命令拿到 JSON 状态。

用法：
  python3 mt5700-at.py                      # 默认走串口 /dev/ttyUSB1 拉一份状态
  python3 mt5700-at.py --transport tcp      # 走模块自带 TCP AT（192.168.8.1:20249）
  python3 mt5700-at.py --cmds "AT+CSQ" "AT^MONSC"
  python3 mt5700-at.py --json
  python3 mt5700-at.py --raw "ATI"

安全：默认只发查询（'?' / '=' 结尾的只读探测除外），不写任何模块状态。
"""
import argparse
import json
import re
import socket
import sys
import time

STATUS_CMDS = [
    "ATI", "AT^VERSION?", "AT+CGMI", "AT+CGMM", "AT+CGMR",
    "AT+CPIN?", "AT^SIMSQ?", "AT+CIMI", "AT^ICCID?", "AT+CNUM",
    "AT+CFUN?", "AT+CEREG?", "AT+CGATT?", "AT+COPS?",
    "AT+CSQ", "AT^HCSQ?", "AT^MONSC", "AT^HFREQINFO?", "AT^CHIPTEMP?",
    "AT+CGPADDR", "AT+CGDCONT?", "AT^DSFLOWQRY", "AT+CPMS?",
    "AT^SETMODE?", "AT^TDPCIELANCFG?", "AT^TDPMCFG?", "AT+CEUS?",
    "AT^C5GOPTION?", "AT^FASTDORM?",
]


def parse_ati(text):
    out = {}
    for line in text.splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            out[k.strip()] = v.strip()
    return out


def parse_hcsq(text):
    """^HCSQ: "NR",52,166,30 -> 模式 + 原始索引"""
    m = re.search(r'\^HCSQ:\s*"(\w+)",\s*([\d,]+)', text)
    if not m:
        return None
    vals = [int(x) for x in m.group(2).split(",") if x.strip().lstrip("-").isdigit()]
    return {"mode": m.group(1), "raw": vals}


def parse_monsc(text):
    """^MONSC: NR,460,15,504990,1,C286F8002,130,14901D,-78,-10,15"""
    m = re.search(r"\^MONSC:\s*([^\r\n]+)", text)
    if not m:
        return None
    f = [x.strip() for x in m.group(1).split(",")]
    d = {"rat": f[0]}
    if len(f) >= 11:
        d.update(mcc=f[1], mnc=f[2], arfcn=f[3], nci=f[5], pci=f[6],
                 tac=f[7], rsrp=f[8], rsrq=f[9], sinr=f[10])
    return d




class Modem:
    def __init__(self, transport="serial", port="/dev/ttyUSB1", host="192.168.8.1",
                 tcp_port=20249, baud=115200, timeout=3.0):
        self.transport, self.timeout = transport, timeout
        if transport == "serial":
            import serial  # pyserial
            self.io = serial.Serial(port, baud, timeout=0.2)
            self.io.reset_input_buffer()
        else:
            self.io = socket.create_connection((host, tcp_port), timeout)
            self.io.settimeout(timeout)

    def _write(self, data: bytes):
        if self.transport == "serial":
            self.io.write(data)
        else:
            self.io.sendall(data)

    def _read(self):
        if self.transport == "serial":
            return self.io.read(4096)
        buf = b""
        try:
            while True:
                chunk = self.io.recv(4096)
                if not chunk:
                    break
                buf += chunk
                if b"OK" in buf or b"ERROR" in buf:
                    break
        except Exception:
            pass
        return buf

    URC = ("^RSSI", "^CERSSI", "^HCSQ", "^DSFLOWRPT", "+CREG", "+CGREG", "+CEREG",
           "+CMTI", "+CLIP", "^SIMSQ", "^MODE")

    def cmd(self, c: str, wait=None) -> str:
        """发一条命令，读到 OK/ERROR 为止；主动上报(URC)行单独丢弃，避免污染解析。"""
        self._write((c + "\r").encode())
        deadline = time.time() + (wait if wait is not None else self.timeout)
        buf = ""
        while time.time() < deadline:
            try:
                chunk = self._read()
            except Exception:
                break
            if chunk:
                buf += chunk.decode("utf-8", "replace")
                if re.search(r"^\s*(OK|ERROR)\s*$", buf, re.M):
                    break
            else:
                time.sleep(0.05)
        lines = [l for l in buf.splitlines()
                 if l.strip() and not l.strip().startswith("AT")
                 and not any(l.strip().startswith(u) for u in self.URC)]
        return "\n".join(lines)

    def close(self):
        try:
            self.io.close()
        except Exception:
            pass


def collect(m: Modem, cmds, gap=0.35):
    out = {}
    for c in cmds:
        out[c] = m.cmd(c, wait=gap).strip()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transport", choices=["serial", "tcp"], default="serial")
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--host", default="192.168.8.1")
    ap.add_argument("--tcp-port", type=int, default=20249)
    ap.add_argument("--cmds", nargs="*")
    ap.add_argument("--raw")
    ap.add_argument("--status", action="store_true", help="拉整套只读状态")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--gap", type=float, default=0.35)
    a = ap.parse_args()

    m = Modem(a.transport, a.port, a.host, a.tcp_port, timeout=max(2.0, a.gap * 6))
    try:
        if a.raw:
            sys.stdout.write(m.cmd(a.raw, wait=1.0))
            return
        cmds = a.cmds or STATUS_CMDS
        res = collect(m, cmds, gap=a.gap)
    finally:
        m.close()

    if a.json:
        atti = parse_ati(res.get("ATI", ""))
        rep = {
            "module": atti,
            "sim": {
                "cpin": res.get("AT+CPIN?", "").strip(),
                "simsq": res.get("AT^SIMSQ?", "").strip(),
                "imsi": res.get("AT+CIMI", "").strip().splitlines()[-1] if res.get("AT+CIMI") else None,
                "iccid": res.get("AT^ICCID?", "").strip(),
                "sms": res.get("AT+CPMS?", "").strip(),
            },
            "net": {
                "cereg": res.get("AT+CEREG?", "").strip(),
                "cgatt": res.get("AT+CGATT?", "").strip(),
                "cops": res.get("AT+COPS?", "").strip(),
                "csq": res.get("AT+CSQ", "").strip(),
                "hcsq": parse_hcsq(res.get("AT^HCSQ?", "")),
                "monsc": parse_monsc(res.get("AT^MONSC", "")),
                "freq": res.get("AT^HFREQINFO?", "").strip(),
                "temp": res.get("AT^CHIPTEMP?", "").strip(),
            },
            "data": {
                "cgpaddr": res.get("AT+CGPADDR", "").strip(),
                "cgdcont": res.get("AT+CGDCONT?", "").strip(),
                "flow": res.get("AT^DSFLOWQRY", "").strip(),
            },
            "mode": {
                "setmode": res.get("AT^SETMODE?", "").strip(),
                "tdpcielancfg": res.get("AT^TDPCIELANCFG?", "").strip(),
                "tdpmcfg": res.get("AT^TDPMCFG?", "").strip(),
                "ceus": res.get("AT+CEUS?", "").strip(),
                "c5goption": res.get("AT^C5GOPTION?", "").strip(),
                "fastdorm": res.get("AT^FASTDORM?", "").strip(),
            },
            "raw": res,
        }
        print(json.dumps(rep, indent=2, ensure_ascii=False))
    else:
        for c, r in res.items():
            print(f"### {c}\n{r}\n")


if __name__ == "__main__":
    main()

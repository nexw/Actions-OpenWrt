"""极简串口/TCP 封装 —— 只依赖 python3-light 自带的 os/termios/select。

放在 /usr/lib/mt5700/ 供 mt5700-at / mt5700-simsel / mt5700-sim-check 复用，
避免依赖 python-pyserial（发行版 v25.12.2 上该包构建会失败）。
"""
import os
import select
import socket
import termios

SPEEDS = {9600: termios.B9600, 19200: termios.B19200, 38400: termios.B38400,
          57600: termios.B57600, 115200: termios.B115200, 230400: termios.B230400,
          460800: termios.B460800}


class SerialPort:
    def __init__(self, path="/dev/ttyUSB1", baud=115200, timeout=0.2):
        self.timeout = timeout
        self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        speed = SPEEDS.get(baud, termios.B115200)
        cc = [0] * 32
        cc[termios.VMIN] = 0
        cc[termios.VTIME] = 0
        attrs = [0, 0, termios.CS8 | termios.CREAD | termios.CLOCAL, 0, speed, speed, cc]
        try:
            termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        except termios.error:
            pass
        self.reset_input_buffer()

    def write(self, data):
        os.write(self.fd, data)

    def read(self, n=4096):
        try:
            r, _, _ = select.select([self.fd], [], [], self.timeout)
        except (OSError, ValueError):
            return b""
        if not r:
            return b""
        try:
            return os.read(self.fd, n)
        except (BlockingIOError, OSError):
            return b""

    def reset_input_buffer(self):
        while True:
            try:
                r, _, _ = select.select([self.fd], [], [], 0)
            except (OSError, ValueError):
                return
            if not r:
                return
            try:
                os.read(self.fd, 65536)
            except (BlockingIOError, OSError):
                return

    def close(self):
        try:
            os.close(self.fd)
        except OSError:
            pass


class TcpPort:
    def __init__(self, host="192.168.8.1", port=20249, timeout=3.0):
        self.timeout = timeout
        self.sock = socket.create_connection((host, port), timeout)
        self.sock.settimeout(timeout)

    def write(self, data):
        self.sock.sendall(data)

    def read(self, n=4096):
        try:
            return self.sock.recv(n)
        except Exception:
            return b""

    def reset_input_buffer(self):
        try:
            while select.select([self.sock], [], [], 0)[0]:
                self.sock.recv(65536)
        except Exception:
            return

    def close(self):
        try:
            self.sock.close()
        except Exception:
            pass

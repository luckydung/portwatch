#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Port Dashboard cho Linux - liet ke cac port dang mo tren may va cho phep dung ung dung chiem port.

Chay:
    python3 portwatch.py          # xem port cua chinh ban
    sudo python3 portwatch.py     # xem va dung duoc ca port cua user khac / dich vu he thong
    python3 portwatch.py --list   # in bang ra man hinh roi thoat (dung trong script)
    python3 portwatch.py --install  # them "Port Dashboard" vao menu ung dung de mo bang click

Chi dung thu vien chuan cua Python 3.6+, khong can cai them gi.
"""

import argparse
import base64
import curses
import json
import locale
import os
import platform
import pwd
import shlex
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
import unicodedata

APP_NAME = 'Port Dashboard'

# ---------- Du lieu tham khao ----------
KNOWN_PORTS = {
    21: 'Truyền file (FTP)',
    22: 'Điều khiển từ xa (SSH)',
    25: 'Gửi email (SMTP)',
    53: 'Phân giải tên miền (DNS)',
    80: 'Web server (HTTP)',
    111: 'Dịch vụ RPC (rpcbind)',
    139: 'Chia sẻ file (Samba)',
    443: 'Web server bảo mật (HTTPS)',
    445: 'Chia sẻ file (Samba / SMB)',
    631: 'Dịch vụ in ấn (CUPS)',
    1433: 'Cơ sở dữ liệu SQL Server',
    1521: 'Cơ sở dữ liệu Oracle',
    2375: 'Docker API',
    2376: 'Docker API (TLS)',
    3000: 'Web dev server (React / Node.js)',
    3306: 'Cơ sở dữ liệu MySQL',
    3389: 'Remote Desktop (xrdp)',
    4200: 'Web dev server (Angular)',
    5000: 'Web dev server (Flask / .NET)',
    5173: 'Web dev server (Vite)',
    5432: 'Cơ sở dữ liệu PostgreSQL',
    5672: 'Hàng đợi tin nhắn RabbitMQ',
    6379: 'Bộ nhớ đệm Redis',
    6443: 'Kubernetes API',
    8000: 'Web dev server',
    8080: 'Web server (Tomcat / Spring Boot)',
    8081: 'Web server / Metro (React Native)',
    8443: 'Web server bảo mật (HTTPS phụ)',
    9000: 'Web server / SonarQube',
    9092: 'Kafka',
    9200: 'Elasticsearch',
    11211: 'Bộ nhớ đệm Memcached',
    27017: 'Cơ sở dữ liệu MongoDB',
}

# Tien trinh chay bang root nhung thuc chat la port cua ung dung nguoi dung -> khong coi la he thong
CONTAINER_PROCS = {'docker-proxy', 'rootlesskit', 'conmon', 'slirp4netns', 'pasta', 'containerd-shim'}

LOOPBACK_V6 = {'::1'}
INTERVAL_PRESETS = [1, 2, 3, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]
MIN_REFRESH, MAX_REFRESH = 1, 3600


# ---------- Doc danh sach port tu /proc ----------
def _decode_addr(hex_addr, family):
    ip_hex, port_hex = hex_addr.split(':')
    if family == socket.AF_INET:
        packed = struct.pack('<I', int(ip_hex, 16))
    else:
        packed = b''.join(struct.pack('<I', int(ip_hex[i:i + 8], 16)) for i in range(0, 32, 8))
    return socket.inet_ntop(family, packed), int(port_hex, 16)


def _listening_sockets():
    """Tra ve {inode: (ip, port, uid)} cho cac socket TCP dang LISTEN."""
    socks = {}
    for path, family in (('/proc/net/tcp', socket.AF_INET), ('/proc/net/tcp6', socket.AF_INET6)):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    p = line.split()
                    if len(p) < 10 or p[3] != '0A':   # 0A = LISTEN
                        continue
                    ip, port = _decode_addr(p[1], family)
                    inode = int(p[9])
                    if inode:
                        socks[inode] = (ip, port, int(p[7]))
        except OSError:
            continue
    return socks


def _inode_owners(inodes):
    """Quet /proc/<pid>/fd de biet tien trinh nao giu socket. Khong co sudo chi thay tien trinh cua minh."""
    owners = {}
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = '/proc/%s/fd' % name
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                link = os.readlink('%s/%s' % (fd_dir, fd))
            except OSError:
                continue
            if link.startswith('socket:['):
                inode = int(link[8:-1])
                if inode in inodes:
                    owners.setdefault(inode, set()).add(int(name))
    return owners


def _read(path, mode='r'):
    try:
        with open(path, mode) as f:
            return f.read()
    except OSError:
        return None


def proc_start_time(pid):
    """Thoi diem bat dau cua tien trinh (truong 22 trong /proc/<pid>/stat), dung de phat hien PID bi tai su dung."""
    stat = _read('/proc/%d/stat' % pid)
    if not stat:
        return None
    try:
        return int(stat.rsplit(')', 1)[1].split()[19])
    except (IndexError, ValueError):
        return None


_user_cache = {}


def user_name(uid):
    if uid not in _user_cache:
        try:
            _user_cache[uid] = pwd.getpwuid(uid).pw_name
        except KeyError:
            _user_cache[uid] = str(uid)
    return _user_cache[uid]


def _is_loopback(ip):
    return ip.startswith('127.') or ip in LOOPBACK_V6 or ip.startswith('::ffff:127.')


def get_port_rows():
    socks = _listening_sockets()
    owners = _inode_owners(set(socks))
    is_root = os.geteuid() == 0

    groups = {}
    for inode, (ip, port, uid) in socks.items():
        pids = owners.get(inode)
        pid = min(pids) if pids else None   # nhieu tien trinh chung socket (vd nginx) -> lay tien trinh cha
        key = (port, pid if pid is not None else 'uid%d' % uid)
        g = groups.setdefault(key, {'port': port, 'pid': pid, 'uid': uid, 'addrs': set(), 'nproc': 0})
        g['addrs'].add(ip)
        if pids:
            g['nproc'] = max(g['nproc'], len(pids))

    rows = []
    for g in groups.values():
        pid, port, uid = g['pid'], g['port'], g['uid']
        comm = exe = cmd = ''
        if pid is not None:
            comm = (_read('/proc/%d/comm' % pid) or '').strip()
            try:
                exe = os.readlink('/proc/%d/exe' % pid)
            except OSError:
                exe = ''
            raw = _read('/proc/%d/cmdline' % pid, 'rb') or b''
            cmd = raw.rstrip(b'\0').replace(b'\0', b' ').decode('utf-8', 'replace')
        if comm:
            app = comm
        elif pid is None and not is_root:
            app = '(cần sudo để xem)'
        else:
            app = '(không rõ)'   # vd socket do kernel giu, khong thuoc tien trinh nao
        if g['nproc'] > 1:
            app += ' +%d' % (g['nproc'] - 1)

        addrs = sorted(g['addrs'])
        if '0.0.0.0' in addrs or '::' in addrs:
            scope = 'Máy khác truy cập được'
        elif all(_is_loopback(a) for a in addrs):
            scope = 'Chỉ máy này'
        else:
            scope = ', '.join(addrs)

        is_container = comm in CONTAINER_PROCS
        is_system = not is_container and (uid < 1000 or uid == 65534 or pid == 1)

        if port in KNOWN_PORTS:
            desc = KNOWN_PORTS[port]
        elif is_container:
            desc = 'Port của container'
        elif is_system:
            desc = 'Dịch vụ hệ thống'
        else:
            desc = ''

        rows.append({
            'port': port, 'app': app, 'desc': desc, 'scope': scope, 'pid': pid,
            'user': user_name(uid), 'cmd': cmd, 'exe': exe, 'addrs': addrs,
            'system': is_system,
        })
    rows.sort(key=lambda r: (r['port'], r['pid'] or 0))
    return rows


# ---------- Thong tin may ----------
def _ipv4_addresses():
    import fcntl
    ips = []
    try:
        names = [n for _, n in socket.if_nameindex()]
    except OSError:
        return ips
    for name in names:
        if name == 'lo':
            continue
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            res = fcntl.ioctl(s.fileno(), 0x8915, struct.pack('256s', name[:15].encode()))   # SIOCGIFADDR
            ip = socket.inet_ntoa(res[20:24])
            if not ip.startswith('169.254.'):
                ips.append('%s (%s)' % (ip, name))
        except OSError:
            pass
        finally:
            s.close()
    return ips


def _meminfo():
    info = {}
    for line in (_read('/proc/meminfo') or '').splitlines():
        k, _, v = line.partition(':')
        try:
            info[k] = int(v.split()[0])   # kB
        except (IndexError, ValueError):
            pass
    return info


def get_machine_info():
    info = [('Tên máy', socket.gethostname())]

    user = user_name(os.geteuid())
    sudo_user = os.environ.get('SUDO_USER')
    if os.geteuid() == 0 and sudo_user and sudo_user != 'root':
        user = 'root (sudo từ %s)' % sudo_user
    info.append(('Người dùng', user))

    os_name = ''
    for line in (_read('/etc/os-release') or '').splitlines():
        if line.startswith('PRETTY_NAME='):
            os_name = line.split('=', 1)[1].strip().strip('"')
    info.append(('Hệ điều hành', '%s (kernel %s)' % (os_name or platform.system(), platform.release())))

    ips = _ipv4_addresses()
    info.append(('IP', ', '.join(ips) if ips else '(không có mạng)'))

    cpu = ''
    for line in (_read('/proc/cpuinfo') or '').splitlines():
        if line.lower().startswith(('model name', 'hardware', 'processor\t: ')) and ':' in line:
            val = line.split(':', 1)[1].strip()
            if val and not val.isdigit():
                cpu = ' '.join(val.split())
                break
    info.append(('CPU', '%s - %d luồng' % (cpu or platform.machine(), os.cpu_count() or 1)))

    mem = _meminfo()
    total = mem.get('MemTotal', 0)
    avail = mem.get('MemAvailable', mem.get('MemFree', 0))
    if total:
        used = total - avail
        gb = 1024.0 * 1024.0
        info.append(('RAM', '%.1f / %.1f GB (%d%%)' % (used / gb, total / gb, round(used * 100.0 / total))))

    up = _read('/proc/uptime')
    if up:
        secs = int(float(up.split()[0]))
        d, h, m = secs // 86400, secs % 86400 // 3600, secs % 3600 // 60
        if d:
            info.append(('Đã bật', '%d ngày %d giờ' % (d, h)))
        elif h:
            info.append(('Đã bật', '%d giờ %d phút' % (h, m)))
        else:
            info.append(('Đã bật', '%d phút' % m))
    return info


# ---------- Cai dat (luu o ~/.config/portwatch/settings.json) ----------
DEFAULT_SETTINGS = {
    'AutoRefresh': True,       # tu dong lam moi
    'RefreshSeconds': 5,       # chu ky lam moi (giay)
    'ShowSystemPorts': False,  # hien port he thong
    'KillSignal': 'TERM',      # TERM = de ung dung tu thoat, KILL = buoc dung ngay
}


def _sudo_ids():
    """(uid, gid, home) cua nguoi dung that khi chay bang sudo, de file cai dat van nam o home cua ho."""
    if os.geteuid() != 0:
        return None
    name = os.environ.get('SUDO_USER')
    if not name or name == 'root':
        return None
    try:
        pw = pwd.getpwnam(name)
        return pw.pw_uid, pw.pw_gid, pw.pw_dir
    except KeyError:
        return None


def settings_path():
    sudo = _sudo_ids()
    if sudo:
        base = os.path.join(sudo[2], '.config')
    else:
        base = os.environ.get('XDG_CONFIG_HOME') or os.path.join(os.path.expanduser('~'), '.config')
    return os.path.join(base, 'portwatch', 'settings.json')


def load_settings():
    s = dict(DEFAULT_SETTINGS)
    try:
        with open(settings_path(), encoding='utf-8') as f:
            data = json.load(f)
        for k, default in DEFAULT_SETTINGS.items():
            v = data.get(k)
            if isinstance(default, bool) and isinstance(v, bool):
                s[k] = v
            elif isinstance(default, int) and not isinstance(default, bool) and isinstance(v, int):
                s[k] = v
            elif isinstance(default, str) and v in ('TERM', 'KILL'):
                s[k] = v
    except (OSError, ValueError, AttributeError):
        pass   # chua co file / file hong -> dung mac dinh
    s['RefreshSeconds'] = min(MAX_REFRESH, max(MIN_REFRESH, s['RefreshSeconds']))
    return s


def save_settings(s):
    path = settings_path()
    sudo = _sudo_ids()
    try:
        d = os.path.dirname(path)
        created = []   # cac thu muc phai tao moi (vd ~/.config chua co)
        p = d
        while p and not os.path.isdir(p):
            created.append(p)
            p = os.path.dirname(p)
        os.makedirs(d, exist_ok=True)
        tmp = path + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(s, f, indent=4, ensure_ascii=False)
        os.replace(tmp, path)
        if sudo:   # chay bang sudo: tra quyen so huu ve nguoi dung that, khong de lai thu muc/file cua root
            for p in created + [path]:
                os.chown(p, sudo[0], sudo[1])
        return True
    except OSError:
        return False


# ---------- Tien ich hien thi ----------
def char_width(c):
    if unicodedata.combining(c):
        return 0
    return 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1


def text_width(s):
    return sum(char_width(c) for c in s)


def fit(s, width):
    """Cat chuoi cho vua 'width' o (them '…' neu bi cat) roi chen khoang trang cho du."""
    if width <= 0:
        return ''
    s = s.replace('\t', ' ').replace('\n', ' ')
    if text_width(s) <= width:
        return s + ' ' * (width - text_width(s))
    out, w = [], 0
    for c in s:
        cw = char_width(c)
        if w + cw > width - 1:
            break
        out.append(c)
        w += cw
    return ''.join(out) + '…' + ' ' * (width - 1 - w)


def copy_to_clipboard(text):
    """Thu wl-copy / xclip / xsel; neu khong co thi gui ma OSC 52 de terminal tu chep."""
    cmds = []
    if os.environ.get('WAYLAND_DISPLAY'):
        cmds.append(['wl-copy'])
    if os.environ.get('DISPLAY'):
        cmds += [['xclip', '-selection', 'clipboard'], ['xsel', '--clipboard', '--input']]
    for cmd in cmds:
        try:
            r = subprocess.run(cmd, input=text.encode('utf-8'), stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=2)
            if r.returncode == 0:
                return 'Đã sao chép vào clipboard.'
        except (OSError, subprocess.SubprocessError):
            continue
    try:
        sys.stdout.write('\033]52;c;%s\a' % base64.b64encode(text.encode('utf-8')).decode('ascii'))
        sys.stdout.flush()
        return 'Đã gửi sang terminal (OSC 52). Nếu chưa chép được, hãy bôi đen để chép.'
    except OSError:
        return 'Không sao chép được.'


class Loader(object):
    """Chay mot ham o luong nen de giao dien khong bi dung trong luc doc /proc."""

    def __init__(self, fn):
        self.fn = fn
        self.lock = threading.Lock()
        self.thread = None
        self.result = None
        self.again = False

    @property
    def busy(self):
        return self.thread is not None and self.thread.is_alive()

    def start(self):
        if self.busy:
            self.again = True   # dang doc do -> doc lai ngay khi xong
            return
        self.thread = threading.Thread(target=self._run)
        self.thread.daemon = True
        self.thread.start()

    def _run(self):
        try:
            res = (self.fn(), None)
        except Exception as e:   # noqa: BLE001 - hien loi len thanh trang thai
            res = (None, e)
        with self.lock:
            self.result = res

    def poll(self):
        with self.lock:
            res, self.result = self.result, None
        if res is not None and self.again and not self.busy:
            self.again = False
            self.start()
        return res


# ---------- Hop thoai ----------
class Dialog(object):
    title = ''
    width = 60

    def lines(self):
        return []

    def footer(self):
        return 'Esc: đóng'

    def handle(self, key):
        """Tra ve False de dong hop thoai."""
        return key not in ('\x1b', 'q', '\n', curses.KEY_ENTER)

    def draw(self, app, scr):
        h, w = scr.getmaxyx()
        ww = min(w - 2, max(self.width, text_width(self.title) + 6))
        body = []
        for item in self.lines():
            if not isinstance(item, tuple):
                item = (item, 0)
            text, attr = item[0], item[1]
            hang = item[2] if len(item) > 2 else 0
            body += [(part, attr) for part in wrap(text, ww - 4, hang)]
        foot = wrap(self.footer(), ww - 4)
        hh = min(h - 2, len(body) + len(foot) + 3)
        y, x = max(0, (h - hh) // 2), max(0, (w - ww) // 2)
        try:
            win = curses.newwin(hh, ww, y, x)
        except curses.error:
            return
        win.bkgd(' ', app.color('dialog'))
        win.erase()
        win.box()
        _put(win, 0, 2, ' %s ' % self.title, app.color('dialog') | curses.A_BOLD)
        room = hh - 3 - len(foot)
        for i, (text, attr) in enumerate(body[:max(0, room)]):
            _put(win, i + 1, 2, fit(text, ww - 4), app.color('dialog') | attr)
        for i, text in enumerate(foot):
            _put(win, hh - 1 - len(foot) + i, 2, fit(text, ww - 4), app.color('dialog') | curses.A_DIM)
        win.noutrefresh()


def wrap(text, width, hang=0):
    """Xuong dong theo tu, tinh theo do rong hien thi. 'hang' = so o thut le cho cac dong tiep theo."""
    if width <= 0 or text_width(text) <= width:
        return [text]
    indent = ' ' * (hang or (len(text) - len(text.lstrip(' '))))
    if text_width(indent) >= width // 2:
        indent = ''
    out, line = [], ''
    for word in text.split(' '):
        cand = word if not line.strip() else line + ' ' + word
        if text_width(cand) <= width:
            line = cand
            continue
        if line.strip():
            out.append(line)
        line = indent + word
        while text_width(line) > width:   # tu qua dai (duong dan, lenh) -> cat cung
            cut, used = 0, 0
            for i, c in enumerate(line):
                if used + char_width(c) > width:
                    break
                used += char_width(c)
                cut = i + 1
            out.append(line[:cut])
            line = indent + line[cut:]
    if line.strip():
        out.append(line)
    return out


def _put(win, y, x, text, attr=0):
    h, w = win.getmaxyx()
    if y < 0 or y >= h or x >= w:
        return
    out, used = [], 0
    for c in text:
        cw = char_width(c)
        if x + used + cw > w - (1 if y == h - 1 else 0):
            break
        out.append(c)
        used += cw
    try:
        win.addstr(y, x, ''.join(out), attr)
    except curses.error:
        pass


class MessageDialog(Dialog):
    def __init__(self, title, text, warn=False):
        self.title, self.text, self.warn = title, text, warn

    def lines(self):
        out = []
        for line in self.text.split('\n'):
            out.append((line, curses.A_BOLD) if self.warn and line.startswith('CẢNH BÁO') else line)
        return out

    def footer(self):
        return 'Enter / Esc: đóng'


class ConfirmDialog(MessageDialog):
    def __init__(self, title, text, on_yes, warn=False):
        MessageDialog.__init__(self, title, text, warn)
        self.on_yes = on_yes

    def footer(self):
        return 'y: Đồng ý     n / Esc: Hủy'

    def handle(self, key):
        if key in ('y', 'Y'):
            self.on_yes()
            return False
        return key not in ('n', 'N', '\x1b', 'q')


class DetailDialog(Dialog):
    title = 'Chi tiết'
    width = 78

    def __init__(self, row):
        self.row = row

    def lines(self):
        r = self.row
        pid = r['pid']
        out = [
            'Port:         %d' % r['port'],
            'Ứng dụng:     %s' % r['app'],
            'Dùng để:      %s' % (r['desc'] or '-'),
            'Phạm vi:      %s' % r['scope'],
            'Địa chỉ:      %s' % ', '.join(r['addrs']),
            'PID:          %s' % (pid if pid is not None else '- (cần sudo để xem)'),
            'Người dùng:   %s' % r['user'],
            'File chạy:    %s' % (r['exe'] or '-'),
        ]
        if pid is not None:
            try:
                out.append('Thư mục:      %s' % os.readlink('/proc/%d/cwd' % pid))
            except OSError:
                pass
        cmd = r['cmd'] or '-'
        if len(cmd) > 300:
            cmd = cmd[:300] + '…'
        out.append('Lệnh:         %s' % cmd)
        return [(line, 0, 14) for line in out]

    def footer(self):
        return 'k: Dừng ứng dụng     Esc: đóng'

    def handle(self, key):
        if key in ('k', 'K', curses.KEY_DC):
            self.app.ask_kill(self.row)
            return False
        return Dialog.handle(self, key)


class InfoDialog(Dialog):
    title = 'Thông tin máy'
    width = 72

    def __init__(self):
        self.loader = Loader(get_machine_info)
        self.info = None
        self.note = 'Đang đọc thông tin...'
        self.next = 0

    def tick(self, now):
        if now >= self.next:
            self.loader.start()
            self.next = now + 3   # RAM / thoi gian bat may thay doi lien tuc
        res = self.loader.poll()
        if res and res[0]:
            self.info = res[0]
            if self.note == 'Đang đọc thông tin...':
                self.note = ''

    def lines(self):
        if not self.info:
            return [self.note]
        out = [('%-14s%s' % (k, v), 0, 14) for k, v in self.info]
        out.append('')
        out.append((self.note, curses.A_DIM))
        return out

    def footer(self):
        return 'c: Sao chép     Esc: đóng'

    def handle(self, key):
        if key in ('c', 'C') and self.info:
            self.note = copy_to_clipboard('\n'.join('%s: %s' % kv for kv in self.info))
            return True
        return Dialog.handle(self, key)


class SettingsDialog(Dialog):
    title = 'Cài đặt'
    width = 72

    def __init__(self, settings):
        self.s = dict(settings)
        self.sel = 0
        self.typed = None   # chuoi so dang go cho o "Lam moi moi"
        self.error = ''

    def _interval_text(self):
        return self.typed if self.typed is not None else str(self.s['RefreshSeconds'])

    def lines(self):
        s = self.s
        sig = 'Lịch sự (SIGTERM)' if s['KillSignal'] == 'TERM' else 'Buộc dừng (SIGKILL)'
        items = [
            '[%s] Tự động làm mới danh sách port' % ('x' if s['AutoRefresh'] else ' '),
            '    Làm mới mỗi  ◀ %s ▶  giây' % self._interval_text(),
            '[%s] Hiện port hệ thống' % ('x' if s['ShowSystemPorts'] else ' '),
            '    Cách dừng ứng dụng  ◀ %s ▶' % sig,
        ]
        out = []
        for i, t in enumerate(items):
            out.append(('› ' + t, curses.A_REVERSE) if i == self.sel else ('  ' + t, 0))
        out.append('')
        if self.error:
            out.append((self.error, curses.A_BOLD))
        else:
            out.append(('Lưu tại: %s' % settings_path(), curses.A_DIM))
        return out

    def footer(self):
        return '↑↓ chọn  Space/◀▶ đổi  gõ số  d: mặc định  Enter: Lưu  Esc: Hủy'

    def _commit_typed(self):
        if self.typed is None:
            return True
        try:
            v = int(self.typed)
        except ValueError:
            v = 0
        if not MIN_REFRESH <= v <= MAX_REFRESH:
            self.error = 'Thời gian làm mới phải từ %d đến %d giây.' % (MIN_REFRESH, MAX_REFRESH)
            return False
        self.s['RefreshSeconds'] = v
        self.typed = None
        self.error = ''
        return True

    def _step_interval(self, d):
        if not self._commit_typed():
            return
        cur = self.s['RefreshSeconds']
        if d > 0:
            nxt = [p for p in INTERVAL_PRESETS if p > cur]
            self.s['RefreshSeconds'] = nxt[0] if nxt else cur
        else:
            prv = [p for p in INTERVAL_PRESETS if p < cur]
            self.s['RefreshSeconds'] = prv[-1] if prv else cur

    def handle(self, key):
        s = self.s
        if key == '\x1b':
            return False
        if key in ('\n', curses.KEY_ENTER):
            if not self._commit_typed():
                return True
            self.app.apply_settings(s)
            return False
        if key in (curses.KEY_UP, 'k'):
            if self._commit_typed():
                self.sel = (self.sel - 1) % 4
        elif key in (curses.KEY_DOWN, 'j', '\t'):
            if self._commit_typed():
                self.sel = (self.sel + 1) % 4
        elif key in ('d', 'D'):
            self.s = dict(DEFAULT_SETTINGS)
            self.typed, self.error = None, ''
        elif self.sel == 1 and isinstance(key, str) and key.isdigit():
            self.typed = (self.typed or '') + key
            self.typed = self.typed[-4:]
        elif self.sel == 1 and key in (curses.KEY_BACKSPACE, '\x7f', '\b'):
            t = self._interval_text()[:-1]
            self.typed = t
        elif key in (' ', curses.KEY_LEFT, curses.KEY_RIGHT, 'h', 'l'):
            d = -1 if key in (curses.KEY_LEFT, 'h') else 1
            if self.sel == 0:
                s['AutoRefresh'] = not s['AutoRefresh']
            elif self.sel == 1:
                self._step_interval(d)
            elif self.sel == 2:
                s['ShowSystemPorts'] = not s['ShowSystemPorts']
            elif self.sel == 3:
                s['KillSignal'] = 'KILL' if s['KillSignal'] == 'TERM' else 'TERM'
        return True


# ---------- Ung dung chinh ----------
COLUMNS = [
    # key, tieu de, do rong toi thieu, he so gian (0 = co dinh)
    ('port', 'Port', 6, 0),
    ('app', 'Ứng dụng', 14, 2),
    ('desc', 'Dùng để làm gì', 16, 3),
    ('scope', 'Phạm vi', 23, 0),
    ('pid', 'PID', 8, 0),
    ('user', 'Người dùng', 11, 0),
    ('cmd', 'Lệnh', 16, 5),
]
DROP_ORDER = ['cmd', 'user', 'desc', 'scope']   # cua so hep thi an bot cot theo thu tu nay


class App(object):
    def __init__(self, scr):
        self.scr = scr
        self.settings = load_settings()
        self.rows = []
        self.view = []
        self.hidden = 0
        self.sel = 0
        self.top = 0
        self.query = ''
        self.searching = False
        self.dialog = None
        self.status = 'Đang đọc danh sách port...'
        self.status_override = None
        self.loader = Loader(get_port_rows)
        self.next_refresh = 0
        self.timers = []
        self.quit = False
        self.relaunch_sudo = False
        self.is_root = os.geteuid() == 0
        self._colors = {}
        self._init_colors()

    # --- mau sac ---
    def _init_colors(self):
        names = {'header': 0, 'selected': curses.A_REVERSE, 'dialog': 0, 'bar': curses.A_REVERSE,
                 'accent': curses.A_BOLD, 'warn': curses.A_BOLD}
        self._colors = dict(names)
        if not curses.has_colors():
            return
        try:
            curses.start_color()
            curses.use_default_colors()
            bg = -1
        except curses.error:
            bg = curses.COLOR_BLACK
        pairs = {
            'header': (curses.COLOR_WHITE, curses.COLOR_BLUE, curses.A_BOLD),
            'selected': (curses.COLOR_BLACK, curses.COLOR_CYAN, 0),
            'dialog': (curses.COLOR_BLACK, curses.COLOR_WHITE, 0),
            'bar': (curses.COLOR_BLACK, curses.COLOR_WHITE, 0),
            'accent': (curses.COLOR_CYAN, bg, curses.A_BOLD),
            'warn': (curses.COLOR_RED, bg, curses.A_BOLD),
        }
        try:
            for i, (name, (fg, b, extra)) in enumerate(pairs.items(), start=1):
                curses.init_pair(i, fg, b)
                self._colors[name] = curses.color_pair(i) | extra
        except curses.error:
            self._colors = dict(names)

    def color(self, name):
        return self._colors.get(name, 0)

    # --- du lieu ---
    def refresh(self):
        self.loader.start()
        self.next_refresh = time.time() + self.settings['RefreshSeconds']

    def after(self, seconds, fn):
        self.timers.append((time.time() + seconds, fn))

    def tick(self):
        now = time.time()
        due = [t for t in self.timers if t[0] <= now]
        self.timers = [t for t in self.timers if t[0] > now]
        for _, fn in due:
            fn()

        if self.settings['AutoRefresh'] and now >= self.next_refresh and not self.loader.busy:
            self.refresh()

        res = self.loader.poll()
        if res:
            rows, err = res
            if err:
                self.status = 'Lỗi khi đọc danh sách port: %s' % err
            else:
                self.rows = rows
                self.update_view()

        if isinstance(self.dialog, InfoDialog):
            self.dialog.tick(now)

    def update_view(self):
        keep = None
        if self.view and 0 <= self.sel < len(self.view):
            keep = (self.view[self.sel]['port'], self.view[self.sel]['pid'])
        q = self.query.strip().lower()
        show_sys = self.settings['ShowSystemPorts']
        view, hidden = [], 0
        for r in self.rows:
            if r['system'] and not show_sys:
                hidden += 1
                continue
            if q:
                hay = ('%s %s %s %s %s %s' % (r['port'], r['app'], r['desc'], r['pid'], r['user'], r['cmd'])).lower()
                if q not in hay:
                    continue
            view.append(r)
        self.view, self.hidden = view, hidden
        self.sel = 0
        if keep:
            for i, r in enumerate(view):
                if (r['port'], r['pid']) == keep:
                    self.sel = i
                    break
        self.sel = min(self.sel, max(0, len(view) - 1))

        st = 'Đang hiện %d port' % len(view)
        if hidden:
            st += ' · đã ẩn %d port hệ thống' % hidden
        st += ' · cập nhật lúc %s' % time.strftime('%H:%M:%S')
        if not self.is_root:
            st += ' · chưa chạy với sudo'
        if self.status_override:
            st, self.status_override = self.status_override, None
        self.status = st

    def apply_settings(self, s):
        old = self.settings
        self.settings = s
        saved = save_settings(s)
        if s['RefreshSeconds'] != old['RefreshSeconds'] or (s['AutoRefresh'] and not old['AutoRefresh']):
            self.next_refresh = time.time() + s['RefreshSeconds']
        self.update_view()
        if not saved:
            self.status = 'Đã áp dụng cài đặt nhưng không lưu được vào %s' % settings_path()

    def toggle(self, key):
        self.settings[key] = not self.settings[key]
        save_settings(self.settings)
        if key == 'AutoRefresh' and self.settings[key]:
            self.refresh()
        self.update_view()

    # --- dung ung dung ---
    def ask_kill(self, row):
        pid = row['pid']
        if pid is None:
            self.dialog = MessageDialog(APP_NAME, 'Không biết tiến trình nào đang giữ port %d.\n\n'
                                        'Port này thuộc người dùng "%s". Bấm u để chạy lại với sudo rồi thử lại.'
                                        % (row['port'], row['user']))
            return
        if pid <= 1 or pid == os.getpid():
            self.dialog = MessageDialog(APP_NAME, 'Đây là tiến trình lõi của hệ thống, không thể dừng.')
            return
        msg = ('Dừng ứng dụng này?\n\n%s\nPort: %d   PID: %d   Người dùng: %s\n\n'
               'Dữ liệu chưa lưu trong ứng dụng sẽ bị mất.' % (row['app'], row['port'], pid, row['user']))
        if row['system']:
            msg = 'CẢNH BÁO: đây là dịch vụ hệ thống, dừng nó có thể làm hệ thống chạy sai.\n\n' + msg
        self.dialog = ConfirmDialog('Xác nhận dừng ứng dụng', msg,
                                    lambda: self.kill(row, self.settings['KillSignal']), warn=row['system'])
        self.dialog.app = self

    def kill(self, row, sig_name):
        pid, port, app = row['pid'], row['port'], row['app']
        start = proc_start_time(pid)
        sig = signal.SIGKILL if sig_name == 'KILL' else signal.SIGTERM
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            self.status = '%s đã thoát từ trước.' % app
            self.refresh()
            return
        except PermissionError:
            hint = '' if self.is_root else '\n\nBấm u để chạy lại với sudo rồi dừng lại lần nữa.'
            self.dialog = MessageDialog(APP_NAME, 'Không có quyền dừng %s (PID %d).%s' % (app, pid, hint))
            return

        self.status = 'Đã gửi tín hiệu dừng tới %s (PID %d)...' % (app, pid)

        def alive():
            return start is not None and proc_start_time(pid) == start

        def check():
            if alive():
                if sig == signal.SIGTERM:
                    self.dialog = ConfirmDialog('Ứng dụng chưa thoát',
                                                '%s (PID %d) vẫn đang chạy sau 2 giây.\n\nBuộc dừng ngay (SIGKILL)?'
                                                % (app, pid), lambda: self.kill(row, 'KILL'))
                else:
                    self.status = 'Đã gửi SIGKILL nhưng %s vẫn chạy.' % app
                return
            self.status_override = 'Đã dừng %s - port %d đã được giải phóng.' % (app, port)
            self.status = self.status_override
            self.refresh()

        # Doi ung dung thoat ma khong lam dung giao dien
        waited = [0.0]

        def poll_exit():
            waited[0] += 0.2
            if alive() and waited[0] < 2.0:
                self.after(0.2, poll_exit)
            else:
                check()

        self.after(0.2, poll_exit)

    # --- ve giao dien ---
    def layout(self, width):
        cols = list(COLUMNS)
        avail = width - 1
        for drop in DROP_ORDER:
            if sum(c[2] + 1 for c in cols) <= avail:
                break
            cols = [c for c in cols if c[0] != drop]
        extra = max(0, avail - sum(c[2] + 1 for c in cols))
        weights = sum(c[3] for c in cols) or 1
        out, given = [], 0
        flex = [c for c in cols if c[3]]
        for c in cols:
            add = extra * c[3] // weights if c[3] else 0
            if flex and c is flex[-1]:
                add = extra - given
            given += add
            out.append((c[0], c[1], c[2] + add))
        return out

    def draw(self):
        scr = self.scr
        scr.erase()
        h, w = scr.getmaxyx()
        if h < 10 or w < 50:
            _put(scr, 0, 0, 'Cửa sổ quá nhỏ - hãy phóng to terminal (tối thiểu 50x10).')
            scr.noutrefresh()
            curses.doupdate()
            return

        title = ' %s - các port đang mở trên máy%s' % (APP_NAME, ' (root)' if self.is_root else '')
        right = 'i: Thông tin máy   s: Cài đặt '
        bar = fit(title, w - text_width(right) - 1) + ' ' + right
        _put(scr, 0, 0, fit(bar, w), self.color('header'))

        auto = ('tự làm mới %d giây' % self.settings['RefreshSeconds']) if self.settings['AutoRefresh'] else 'tự làm mới: tắt'
        sysp = 'port hệ thống: %s' % ('hiện' if self.settings['ShowSystemPorts'] else 'ẩn')
        if self.searching:
            search = 'Tìm: %s█' % self.query
        elif self.query:
            search = 'Tìm: %s   (/ để sửa, Esc để xóa)' % self.query
        else:
            search = 'Bấm / để tìm theo port, tên ứng dụng, PID...'
        info = '%s · %s ' % (auto, sysp)
        _put(scr, 1, 1, fit(search, w - 3 - text_width(info)), self.color('accent') if self.searching else curses.A_DIM)
        _put(scr, 1, w - 1 - text_width(info), info, curses.A_DIM)

        cols = self.layout(w)
        x = 0
        for key, title_, cw in cols:
            _put(scr, 3, x, fit(title_, cw), curses.A_BOLD | curses.A_UNDERLINE)
            x += cw + 1

        list_top, list_h = 4, h - 7
        if self.sel < self.top:
            self.top = self.sel
        elif self.sel >= self.top + list_h:
            self.top = self.sel - list_h + 1
        self.top = max(0, min(self.top, max(0, len(self.view) - list_h)))

        if not self.view:
            msg = 'Đang đọc...' if not self.rows and self.loader.busy else 'Không có port nào khớp.'
            _put(scr, list_top + 1, 2, msg, curses.A_DIM)
        for i, r in enumerate(self.view[self.top:self.top + list_h]):
            idx = self.top + i
            line = ''
            for key, _, cw in cols:
                v = r[key]
                line += fit('-' if v is None else str(v), cw) + ' '
            if idx == self.sel:
                attr = self.color('selected')
            elif r['system']:
                attr = curses.A_DIM
            else:
                attr = 0
            _put(scr, list_top + i, 0, fit(line, w), attr)

        if len(self.view) > list_h:
            _put(scr, h - 3, w - 14, fit(' %d/%d ' % (self.sel + 1, len(self.view)), 12), curses.A_DIM)

        _put(scr, h - 2, 0, fit(' ' + self.status, w), self.color('bar'))
        keys = '↑↓ chọn  / tìm  Enter chi tiết  k dừng  r làm mới  a tự làm mới  h port hệ thống'
        if not self.is_root:
            keys += '  u sudo'
            if not is_installed():
                keys += '  m thêm vào menu'
        keys += '  q thoát'
        _put(scr, h - 1, 0, fit(keys, w - 1), curses.A_DIM)

        scr.noutrefresh()
        if self.dialog:
            self.dialog.draw(self, scr)
        curses.doupdate()

    # --- phim ---
    def handle_key(self, key):
        if key == curses.KEY_RESIZE:
            return
        if self.dialog:
            d = self.dialog
            if not d.handle(key) and self.dialog is d:
                self.dialog = None
            return

        if self.searching:
            if key in ('\n', curses.KEY_ENTER):
                self.searching = False
            elif key == '\x1b':
                self.searching = False
                self.query = ''
            elif key in (curses.KEY_BACKSPACE, '\x7f', '\b'):
                self.query = self.query[:-1]
            elif key == '\x15':   # Ctrl+U
                self.query = ''
            elif isinstance(key, str) and key.isprintable():
                self.query += key
            elif key in (curses.KEY_UP, curses.KEY_DOWN):
                self.searching = False
                self.handle_key(key)
                return
            self.update_view()
            return

        n = len(self.view)
        page = max(1, self.scr.getmaxyx()[0] - 8)
        if key in ('q', 'Q'):
            self.quit = True
        elif key == '\x1b':
            if self.query:
                self.query = ''
                self.update_view()
            else:
                self.quit = True
        elif key == curses.KEY_UP:
            self.sel = max(0, self.sel - 1)
        elif key == curses.KEY_DOWN:
            self.sel = min(max(0, n - 1), self.sel + 1)
        elif key == curses.KEY_PPAGE:
            self.sel = max(0, self.sel - page)
        elif key == curses.KEY_NPAGE:
            self.sel = min(max(0, n - 1), self.sel + page)
        elif key == curses.KEY_HOME:
            self.sel = 0
        elif key == curses.KEY_END:
            self.sel = max(0, n - 1)
        elif key == '/':
            self.searching = True
        elif key in ('r', 'R', curses.KEY_F5):
            self.status = 'Đang làm mới...'
            self.refresh()
        elif key in ('a', 'A'):
            self.toggle('AutoRefresh')
        elif key in ('h', 'H'):
            self.toggle('ShowSystemPorts')
        elif key in ('i', 'I'):
            self.dialog = InfoDialog()
        elif key in ('s', 'S'):
            self.dialog = SettingsDialog(self.settings)
        elif key in ('u', 'U') and not self.is_root:
            self.relaunch_sudo = True
            self.quit = True
        elif key in ('m', 'M') and not self.is_root:
            try:
                msg = install()
            except (OSError, RuntimeError) as e:
                msg = 'Không thêm được vào menu: %s' % e
            self.dialog = MessageDialog(APP_NAME, msg)
        elif n and key in ('\n', curses.KEY_ENTER):
            self.dialog = DetailDialog(self.view[self.sel])
        elif n and key in ('k', 'K', curses.KEY_DC):
            self.ask_kill(self.view[self.sel])
        if self.dialog is not None:
            self.dialog.app = self

    def run(self):
        curses.curs_set(0)
        self.scr.keypad(True)
        self.scr.timeout(100)
        self.refresh()
        while not self.quit:
            self.tick()
            self.draw()
            try:
                key = self.scr.get_wch()
            except curses.error:
                continue
            except KeyboardInterrupt:
                break
            self.handle_key(key)


# ---------- Mo bang click: tu mo cua so terminal, them vao menu ung dung ----------
# Moi terminal nhan cau lenh theo mot kieu: 'argv' = cac doi so rieng sau co,
# 'line' = ca cau lenh trong mot chuoi.
TERMINALS = {
    'x-terminal-emulator': (['-e'], 'argv'),
    'ptyxis':         (['--new-window', '-x'], 'line'),
    'kgx':            (['--'], 'argv'),
    'gnome-terminal': (['--geometry=120x32', '--'], 'argv'),
    'konsole':        (['-e'], 'argv'),
    'xfce4-terminal': (['--geometry=120x32', '-x'], 'argv'),
    'mate-terminal':  (['--geometry=120x32', '-x'], 'argv'),
    'tilix':          (['-e'], 'line'),
    'terminator':     (['-x'], 'argv'),
    'qterminal':      (['-e'], 'line'),
    'lxterminal':     (['-e'], 'line'),
    'kitty':          ([], 'argv'),
    'alacritty':      (['-e'], 'argv'),
    'wezterm':        (['start', '--'], 'argv'),
    'foot':           ([], 'argv'),
    'xterm':          (['-geometry', '120x32', '-e'], 'argv'),
    'urxvt':          (['-e'], 'argv'),
}
DESKTOP_TERMINALS = [
    ('KDE', ['konsole']),
    ('XFCE', ['xfce4-terminal']),
    ('MATE', ['mate-terminal']),
    ('LXQT', ['qterminal']),
    ('LXDE', ['lxterminal']),
    ('GNOME', ['ptyxis', 'kgx', 'gnome-terminal']),
    ('UNITY', ['gnome-terminal']),
    ('CINNAMON', ['gnome-terminal']),
]


def _terminal_order():
    desk = (os.environ.get('XDG_CURRENT_DESKTOP') or os.environ.get('DESKTOP_SESSION') or '').upper()
    order = []
    for tag, names in DESKTOP_TERMINALS:   # uu tien terminal di kem moi truong desktop dang dung
        if tag in desk:
            order += names
    order += ['x-terminal-emulator'] + list(TERMINALS)
    seen = set()
    return [t for t in order if not (t in seen or seen.add(t))]


def has_display():
    return bool(os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY'))


def gui_message(text):
    """Bao loi bang hop thoai khi khong co terminal de in ra (vd. mo bang click)."""
    for cmd in (['zenity', '--error', '--title', APP_NAME, '--text', text],
                ['kdialog', '--title', APP_NAME, '--error', text],
                ['notify-send', APP_NAME, text],
                ['xmessage', '-center', text]):
        if shutil.which(cmd[0]):
            try:
                subprocess.call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return
            except OSError:
                pass


def open_in_terminal(extra_args):
    """Chay lai chinh file nay trong mot cua so terminal moi. Chi tro ve neu khong tim duoc terminal nao."""
    cmd = [sys.executable, os.path.abspath(__file__)] + extra_args + ['--terminal']
    for name in _terminal_order():
        path = shutil.which(name)
        if not path:
            continue
        opts, style = TERMINALS[name]
        tail = cmd if style == 'argv' else [' '.join(shlex.quote(a) for a in cmd)]
        try:
            os.execv(path, [path] + opts + tail)
        except OSError:
            continue


def pause_before_close():
    try:
        input('\nNhấn Enter để đóng cửa sổ...')
    except (EOFError, KeyboardInterrupt):
        pass


def _install_paths():
    home = os.path.expanduser('~')
    data = os.environ.get('XDG_DATA_HOME') or os.path.join(home, '.local', 'share')
    return (os.path.join(home, '.local', 'bin', 'portwatch'),
            os.path.join(data, 'applications', 'portwatch.desktop'))


def _desktop_dir():
    try:
        out = subprocess.check_output(['xdg-user-dir', 'DESKTOP'], stderr=subprocess.DEVNULL)
        path = out.decode('utf-8', 'replace').strip()
    except (OSError, subprocess.CalledProcessError):
        path = os.path.join(os.path.expanduser('~'), 'Desktop')
    home = os.path.expanduser('~').rstrip('/')
    if path and path.rstrip('/') != home and os.path.isdir(path):
        return path
    return None


def is_installed():
    return all(os.path.exists(p) for p in _install_paths())


def _refresh_menu(app_dir):
    if shutil.which('update-desktop-database'):
        try:
            subprocess.call(['update-desktop-database', app_dir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass


def install():
    """Chep file vao ~/.local/bin/portwatch va tao bieu tuong trong menu ung dung (+ ngoai Desktop).
    Tra ve thong bao ket qua."""
    if os.geteuid() == 0:
        raise RuntimeError('không chạy bằng sudo. Hãy chạy bằng người dùng bình thường để thêm vào menu của bạn.')
    target, entry = _install_paths()
    src = os.path.realpath(__file__)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    os.makedirs(os.path.dirname(entry), exist_ok=True)
    if os.path.realpath(target) != src:
        tmp = target + '.tmp'
        shutil.copyfile(src, tmp)
        os.chmod(tmp, 0o755)
        os.replace(tmp, target)

    exec_path = '"%s"' % target if ' ' in target else target
    text = '\n'.join([
        '[Desktop Entry]',
        'Type=Application',
        'Name=%s' % APP_NAME,
        'GenericName=Port đang mở',
        'Comment=Xem port nào đang mở, ứng dụng nào chiếm port và dừng nó',
        'Exec=%s' % exec_path,
        'Icon=utilities-system-monitor',
        # Terminal=false: portwatch tu mo terminal phu hop (va giu cua so lai neu co loi)
        'Terminal=false',
        'Categories=System;Network;Monitor;',
        'Keywords=port;network;tcp;listen;kill;mạng;',
        'StartupNotify=false',
        '',
    ])
    with open(entry, 'w', encoding='utf-8') as f:
        f.write(text)
    os.chmod(entry, 0o755)
    _refresh_menu(os.path.dirname(entry))

    lines = ['Đã thêm "%s" vào menu ứng dụng.' % APP_NAME,
             'Mở menu (hoặc bấm phím Super), gõ "Port" rồi click để chạy. Có thể ghim vào thanh tác vụ/dock.']
    desk = _desktop_dir()
    if desk:
        shortcut = os.path.join(desk, 'portwatch.desktop')
        shutil.copyfile(entry, shortcut)
        os.chmod(shortcut, 0o755)
        if shutil.which('gio'):   # GNOME: danh dau tin cay de double-click chay duoc
            try:
                subprocess.call(['gio', 'set', shortcut, 'metadata::trusted', 'true'],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                pass
        lines.append('Đã tạo biểu tượng ngoài Desktop (lần đầu có thể phải chuột phải → "Allow Launching").')
    lines.append('Lệnh "portwatch" cũng đã được cài vào %s.' % os.path.dirname(target))
    return '\n'.join(lines)


def uninstall():
    target, entry = _install_paths()
    removed = []
    desk = _desktop_dir()
    for p in [entry, target] + ([os.path.join(desk, 'portwatch.desktop')] if desk else []):
        if os.path.exists(p):
            os.remove(p)
            removed.append(p)
    _refresh_menu(os.path.dirname(entry))
    if not removed:
        return 'Chưa cài nên không có gì để gỡ.'
    return 'Đã gỡ:\n' + '\n'.join('  ' + p for p in removed)


# ---------- Che do --list ----------
def print_list(show_system):
    all_rows = get_port_rows()
    rows = [r for r in all_rows if show_system or not r['system']]
    cols = [('port', 'Port'), ('app', 'Ứng dụng'), ('desc', 'Dùng để làm gì'), ('scope', 'Phạm vi'),
            ('pid', 'PID'), ('user', 'Người dùng'), ('cmd', 'Lệnh')]
    table = [[t for _, t in cols]] + [['-' if r[k] is None else str(r[k]) for k, _ in cols] for r in rows]
    widths = [min(40, max(text_width(row[i]) for row in table)) for i in range(len(cols))]
    for row in table:
        print('  '.join(fit(v, widths[i]) for i, v in enumerate(row)).rstrip())
    hidden = len(all_rows) - len(rows)
    if hidden:
        print('\n(đã ẩn %d port hệ thống - thêm --system để hiện)' % hidden)
    if os.geteuid() != 0:
        print('(chưa chạy với sudo - port của người dùng khác sẽ không rõ tiến trình)')


def main():
    ap = argparse.ArgumentParser(description='Xem các port đang mở trên máy và dừng ứng dụng đang chiếm port.')
    ap.add_argument('--list', action='store_true', help='in danh sách port ra màn hình rồi thoát')
    ap.add_argument('--system', action='store_true', help='(dùng với --list) hiện cả port hệ thống')
    ap.add_argument('--install', action='store_true', help='thêm Port Dashboard vào menu ứng dụng và Desktop để mở bằng click')
    ap.add_argument('--uninstall', action='store_true', help='gỡ những gì --install đã thêm')
    ap.add_argument('--terminal', action='store_true', help=argparse.SUPPRESS)   # dang chay trong cua so tu mo
    args = ap.parse_args()

    if not sys.platform.startswith('linux') or not os.path.exists('/proc/net/tcp'):
        sys.exit('Port Dashboard bản này chỉ chạy trên Linux (cần /proc). Trên Windows hãy dùng windows/PortDashboard.bat.')

    if args.install or args.uninstall:
        try:
            print(install() if args.install else uninstall())
        except (OSError, RuntimeError) as e:
            sys.exit('Không %s được: %s' % ('cài' if args.install else 'gỡ', e))
        return

    if args.list:
        print_list(args.system)
        return

    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        # Duoc mo bang click (menu, Desktop, trinh quan ly file): tu mo mot cua so terminal
        if has_display() and not args.terminal:
            open_in_terminal([])
            gui_message('Không tìm thấy chương trình terminal nào để mở %s.\n'
                        'Hãy cài một terminal (vd. gnome-terminal, konsole, xterm) rồi thử lại.' % APP_NAME)
            sys.exit(1)
        sys.exit('Cần chạy trong terminal. Dùng --list để in danh sách ra màn hình.')

    locale.setlocale(locale.LC_ALL, '')
    os.environ.setdefault('ESCDELAY', '25')   # phim Esc phan hoi ngay

    holder = {}

    def _run(scr):
        app = App(scr)
        holder['app'] = app
        app.run()

    curses.wrapper(_run)

    app = holder.get('app')
    if app and app.relaunch_sudo:
        cmd = ['sudo', sys.executable, os.path.abspath(__file__)] + (['--terminal'] if args.terminal else [])
        print('Đang chạy lại với sudo...')
        try:
            rc = subprocess.call(cmd)
        except OSError as e:
            sys.exit('Không chạy được sudo: %s' % e)
        except KeyboardInterrupt:
            rc = 130
        if rc not in (0, 130):
            sys.exit('sudo không chạy được (mã lỗi %d).' % rc)


if __name__ == '__main__':
    # Trong cua so terminal tu mo: neu co loi thi giu cua so lai de con doc duoc thong bao
    in_own_window = '--terminal' in sys.argv[1:]
    try:
        main()
    except SystemExit as e:
        if in_own_window and e.code not in (None, 0):
            if isinstance(e.code, str):
                print(e.code, file=sys.stderr)
            pause_before_close()
            sys.exit(1)
        raise
    except Exception:
        if not in_own_window:
            raise
        import traceback
        traceback.print_exc()
        pause_before_close()
        sys.exit(1)

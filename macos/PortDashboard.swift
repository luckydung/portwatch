// Port Dashboard cho macOS - cho biet port nao dang mo, ung dung nao dang chiem, va dung ung dung de giai phong port.
// Build: ./build.sh  (can Xcode hoac Command Line Tools)
import AppKit
import Darwin
import ServiceManagement
import SwiftUI

// MARK: - Du lieu tham khao

let knownPorts: [Int: String] = [
    21: "Truyền file (FTP)",
    22: "Điều khiển từ xa (SSH)",
    25: "Gửi email (SMTP)",
    53: "Phân giải tên miền (DNS)",
    80: "Web server (HTTP)",
    88: "Đăng nhập mạng (Kerberos)",
    443: "Web server bảo mật (HTTPS)",
    445: "Chia sẻ file (SMB)",
    548: "Chia sẻ file (AFP)",
    631: "Dịch vụ in ấn (CUPS)",
    1433: "Cơ sở dữ liệu SQL Server",
    1521: "Cơ sở dữ liệu Oracle",
    2375: "Docker API",
    2376: "Docker API (TLS)",
    3000: "Web dev server (React / Node.js)",
    3306: "Cơ sở dữ liệu MySQL",
    3389: "Remote Desktop",
    4200: "Web dev server (Angular)",
    5000: "Web dev server (Flask / .NET)",
    5173: "Web dev server (Vite)",
    5432: "Cơ sở dữ liệu PostgreSQL",
    5672: "Hàng đợi tin nhắn RabbitMQ",
    5900: "Chia sẻ màn hình (VNC)",
    6379: "Bộ nhớ đệm Redis",
    6443: "Kubernetes API",
    7000: "AirPlay Receiver",
    8000: "Web dev server",
    8080: "Web server (Tomcat / Spring Boot)",
    8081: "Web server / Metro (React Native)",
    8443: "Web server bảo mật (HTTPS phụ)",
    9000: "Web server / SonarQube",
    9092: "Kafka",
    9200: "Elasticsearch",
    11211: "Bộ nhớ đệm Memcached",
    27017: "Cơ sở dữ liệu MongoDB",
    33060: "MySQL X Protocol",
]

/// Tien trinh cua macOS hay giu port; mo ta theo ten tien trinh duoc uu tien hon theo so port.
let knownProcesses: [String: String] = [
    "ControlCenter": "AirPlay Receiver của macOS",
    "rapportd": "Handoff / kết nối thiết bị Apple",
    "sharingd": "AirDrop / chia sẻ của macOS",
    "kdc": "Đăng nhập mạng (Kerberos)",
    "screensharingd": "Chia sẻ màn hình (VNC)",
    "cupsd": "Dịch vụ in ấn (CUPS)",
    "com.docker.backend": "Port của container (Docker)",
    "vpnkit-bridge": "Port của container (Docker)",
    "gvproxy": "Port của container (Podman)",
    "OrbStack Helper": "Port của container (OrbStack)",
]

let containerProcesses: Set<String> = ["com.docker.backend", "vpnkit-bridge", "gvproxy", "OrbStack Helper", "limactl"]
let systemDirs = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"]

/// Port cua macOS ma dung tien trinh khong giai phong duoc: chi tat trong Cai dat he thong.
struct SettingsHint {
    let text: String
    let url: String
}

func settingsHint(for row: PortRow) -> SettingsHint? {
    if row.process == "ControlCenter" {
        return SettingsHint(
            text: "Port \(row.port) là AirPlay Receiver của macOS. Dừng ControlCenter không giải phóng được port vì macOS sẽ tự mở lại nó.\n\nĐể giải phóng port: Cài đặt hệ thống → Chung → AirDrop & Handoff → tắt \"AirPlay Receiver\".",
            url: "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension")
    }
    if row.pid == 1 {
        return SettingsHint(
            text: "Port \(row.port) do launchd (tiến trình lõi của macOS) giữ thay cho một dịch vụ chia sẻ (\(row.desc.isEmpty ? "dịch vụ hệ thống" : row.desc)). Không thể dừng launchd.\n\nĐể giải phóng port: Cài đặt hệ thống → Chung → Chia sẻ → tắt dịch vụ tương ứng.",
            url: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")
    }
    return nil
}

// MARK: - Mo hinh

struct PortRow: Identifiable, Hashable {
    var id: String { "\(port)-\(pid)" }
    let port: Int
    let app: String        // ten hien thi (ten app .app ngoai cung neu co)
    let process: String    // ten tien trinh
    let desc: String
    let scope: String
    let isPublic: Bool
    let pid: Int
    let user: String
    let uid: Int
    let exe: String
    let bundlePath: String
    let cmd: String
    let addrs: [String]
    let system: Bool

    var pidText: String { String(pid) }

    func matches(_ q: String) -> Bool {
        if q.isEmpty { return true }
        return [String(port), app, process, String(pid), exe, desc, user]
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }

    var summary: String {
        """
        Port: \(port)
        Ứng dụng: \(app)
        Tiến trình: \(process)
        Dùng để: \(desc.isEmpty ? "-" : desc)
        Phạm vi: \(scope) (\(addrs.joined(separator: ", ")))
        PID: \(pid)
        Người dùng: \(user)
        File chạy: \(exe.isEmpty ? "-" : exe)
        Lệnh: \(cmd.isEmpty ? "-" : cmd)
        """
    }
}

// MARK: - Doc danh sach port

enum Shell {
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

enum PortScanner {
    private struct Group {
        let port: Int
        let pid: Int
        let name: String
        var addrs: Set<String>
    }

    /// Nguon chinh la lsof (thay tien trinh cua nguoi dung hien tai). netstat -anv con thay ca port cua root,
    /// nhung macOS co the chan app doc bang TCP qua netstat (tra ve rong) -> chi dung de bo sung.
    static func scan() -> [PortRow] {
        var groups: [String: Group] = [:]
        for (pid, name, host, port) in lsofListening() {
            groups["\(port)-\(pid)", default: Group(port: port, pid: pid, name: name, addrs: [])].addrs.insert(host)
        }
        for line in Shell.run("/usr/sbin/netstat", ["-anv", "-p", "tcp"]).split(separator: "\n") {
            let t = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard t.count > 11, t[0].hasPrefix("tcp"), t[5] == "LISTEN" else { continue }
            let local = t[3]
            guard let dot = local.lastIndex(of: "."), let port = Int(local[local.index(after: dot)...]) else { continue }
            var host = String(local[..<dot])
            if host == "*" { host = t[0] == "tcp4" ? "0.0.0.0" : "::" }

            // cot "process:pid" (ten tien trinh co the co khoang trang)
            var parts: [String] = []
            var pid = -1
            var name = ""
            for i in 10..<t.count {
                parts.append(t[i])
                if let c = t[i].lastIndex(of: ":"), let n = Int(t[i][t[i].index(after: c)...]) {
                    pid = n
                    let joined = parts.joined(separator: " ")
                    name = String(joined[..<joined.lastIndex(of: ":")!])
                    break
                }
            }
            guard pid > 0 else { continue }
            let key = "\(port)-\(pid)"
            groups[key, default: Group(port: port, pid: pid, name: name, addrs: [])].addrs.insert(host)
        }

        let pids = Set(groups.values.map(\.pid))
        let info = psInfo(pids)
        let cmds = psCommands(pids)

        return groups.values.map { g in
            let (uid, user, exePath) = info[g.pid] ?? (-1, "?", "")
            let exe = exePath.hasPrefix("/") ? exePath : ""
            let process = exe.isEmpty ? (exePath.isEmpty ? g.name : exePath) : (exe as NSString).lastPathComponent
            let bundle = outerBundle(exe)
            var app = process
            if !bundle.isEmpty {
                var n = FileManager.default.displayName(atPath: bundle)
                if n.hasSuffix(".app") { n = String(n.dropLast(4)) }
                app = n
            }
            let addrs = g.addrs.sorted()
            let isPublic = addrs.contains("0.0.0.0") || addrs.contains("::")
            let scope: String
            if isPublic {
                scope = "Máy khác truy cập được"
            } else if addrs.allSatisfy({ $0.hasPrefix("127.") || $0 == "::1" || $0.hasPrefix("::ffff:127.") }) {
                scope = "Chỉ máy này"
            } else {
                scope = addrs.joined(separator: ", ")
            }

            let isContainer = containerProcesses.contains(process)
            // AirPlay Receiver hay chiem port 5000/7000 cua dev server -> luon hien, khong an nhu port he thong
            let isSystem = !isContainer && process != "ControlCenter"
                && (uid < 500 || g.pid == 1 || systemDirs.contains { exe.hasPrefix($0) })

            let desc: String
            if let d = knownProcesses[process] {
                desc = d
            } else if let d = knownPorts[g.port] {
                desc = d
            } else if isContainer {
                desc = "Port của container"
            } else if isSystem {
                desc = "Dịch vụ hệ thống"
            } else {
                desc = ""
            }

            return PortRow(port: g.port, app: app, process: process, desc: desc, scope: scope, isPublic: isPublic,
                           pid: g.pid, user: user, uid: uid, exe: exe, bundlePath: bundle, cmd: cmds[g.pid] ?? "",
                           addrs: addrs, system: isSystem)
        }
        .sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    private static func lsofListening() -> [(Int, String, String, Int)] {
        var res: [(Int, String, String, Int)] = []
        var pid = -1, name = "", ftype = ""
        let out = Shell.run("/usr/sbin/lsof", ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pctn"])
        for line in out.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let val = String(line.dropFirst())
            switch tag {
            case "p": pid = Int(val) ?? -1; name = ""
            case "c": name = val
            case "f": ftype = ""
            case "t": ftype = val
            case "n":
                guard pid > 0, let c = val.lastIndex(of: ":"), let port = Int(val[val.index(after: c)...]) else { break }
                var host = String(val[..<c]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                if host == "*" { host = ftype == "IPv6" ? "::" : "0.0.0.0" }
                res.append((pid, name, host, port))
            default: break
            }
        }
        return res
    }

    /// Thu muc .app ngoai cung chua file chay (vd /Applications/GitHub Desktop.app).
    static func outerBundle(_ exe: String) -> String {
        guard let r = exe.range(of: ".app/") else { return "" }
        return String(exe[..<r.lowerBound]) + ".app"
    }

    private static func psInfo(_ pids: Set<Int>) -> [Int: (Int, String, String)] {
        guard !pids.isEmpty else { return [:] }
        var out: [Int: (Int, String, String)] = [:]
        let list = pids.sorted().map(String.init).joined(separator: ",")
        for line in Shell.run("/bin/ps", ["-ww", "-o", "pid=,uid=,user=,comm=", "-p", list]).split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
            guard f.count == 4, let pid = Int(f[0]), let uid = Int(f[1]) else { continue }
            out[pid] = (uid, f[2], f[3].trimmingCharacters(in: .whitespaces))
        }
        return out
    }

    private static func psCommands(_ pids: Set<Int>) -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        var out: [Int: String] = [:]
        let list = pids.sorted().map(String.init).joined(separator: ",")
        for line in Shell.run("/bin/ps", ["-ww", "-o", "pid=,command=", "-p", list]).split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard f.count == 2, let pid = Int(f[0]) else { continue }
            out[pid] = f[1].trimmingCharacters(in: .whitespaces)
        }
        return out
    }
}

enum Proc {
    /// Thoi diem bat dau cua tien trinh, de biet PID co bi tai su dung khong.
    static func startTime(_ pid: Int) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == Int32(pid) else { return nil }
        let tv = info.kp_proc.p_un.__p_starttime
        return "\(tv.tv_sec).\(tv.tv_usec)"
    }

    static func cwd(_ pid: Int) -> String? {
        var vpi = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(Int32(pid), PROC_PIDVNODEPATHINFO, 0, &vpi, size) == size else { return nil }
        let path = withUnsafeBytes(of: &vpi.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }
}

enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for row: PortRow) -> NSImage {
        let key = row.bundlePath.isEmpty ? row.exe : row.bundlePath
        if key.isEmpty {
            return NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        if let i = cache[key] { return i }
        let i = NSWorkspace.shared.icon(forFile: key)
        cache[key] = i
        return i
    }
}

// MARK: - Thong tin may

enum MachineInfo {
    static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "" }
        return String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
    }

    static func ipAddresses() -> [String] {
        var list: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if name == "lo0" || ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { continue }
            list.append("\(ip) (\(name))")
        }
        return list
    }

    static func memory() -> String {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let gb = 1024.0 * 1024.0 * 1024.0
        guard r == KERN_SUCCESS else { return String(format: "%.1f GB", total / gb) }
        var page: vm_size_t = 0
        host_page_size(mach_host_self(), &page)
        let used = Double(UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count))
            * Double(page)
        return String(format: "%.1f / %.1f GB (%d%%)", used / gb, total / gb, Int((used * 100 / total).rounded()))
    }

    static func uptime() -> String {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return "-" }
        let secs = Int(Date().timeIntervalSince1970) - Int(tv.tv_sec)
        let d = secs / 86400, h = secs % 86400 / 3600, m = secs % 3600 / 60
        if d > 0 { return "\(d) ngày \(h) giờ" }
        if h > 0 { return "\(h) giờ \(m) phút" }
        return "\(m) phút"
    }

    static func items() -> [(String, String)] {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let full = NSFullUserName()
        let ips = ipAddresses()
        let cpu = sysctlString("machdep.cpu.brand_string")
        return [
            ("Tên máy", Host.current().localizedName ?? ProcessInfo.processInfo.hostName),
            ("Người dùng", full.isEmpty || full == NSUserName() ? NSUserName() : "\(NSUserName()) (\(full))"),
            ("Hệ điều hành", "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion) (\(sysctlString("kern.osversion")))"),
            ("IP", ips.isEmpty ? "(không có mạng)" : ips.joined(separator: ", ")),
            ("CPU", "\(cpu.isEmpty ? sysctlString("hw.machine") : cpu) - \(ProcessInfo.processInfo.processorCount) luồng"),
            ("RAM", memory()),
            ("Đã bật", uptime()),
        ]
    }
}

// MARK: - Cai dat

enum Keys {
    static let autoRefresh = "AutoRefresh"
    static let refreshSeconds = "RefreshSeconds"
    static let showInfoButton = "ShowMachineInfoButton"
    static let showSystem = "ShowSystemPorts"
    static let alwaysOnTop = "AlwaysOnTop"
}

// MARK: - Store

struct PromptAction: Identifiable {
    let id = UUID()
    let label: String
    var role: ButtonRole? = nil
    let run: () -> Void
}

struct Prompt {
    let title: String
    let message: String
    var actions: [PromptAction] = []
}

@MainActor
final class PortStore: ObservableObject {
    @Published var rows: [PortRow] = []
    @Published var loaded = false
    @Published var lastUpdated: Date?
    @Published var notice: String?
    @Published var prompt: Prompt?
    private var loading = false
    private var timer: Timer?
    private var noticeClear: DispatchWorkItem?

    func refresh() {
        guard !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let r = PortScanner.scan()
            await MainActor.run {
                self.rows = r
                self.lastUpdated = Date()
                self.loaded = true
                self.loading = false
            }
        }
    }

    func schedule(enabled: Bool, seconds: Int) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(min(3600, max(1, seconds))), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func show(_ text: String) {
        notice = text
        noticeClear?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeClear = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: w)
    }

    /// Hien prompt sau khi alert truoc dong han, tranh bi alert cu ghi de.
    func present(_ p: Prompt) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.prompt = p }
    }

    // --- dung ung dung ---
    func askKill(_ row: PortRow) {
        if let hint = settingsHint(for: row) {
            present(Prompt(title: "Không dừng được bằng cách này", message: hint.text, actions: [
                PromptAction(label: "Mở Cài đặt hệ thống") {
                    if let u = URL(string: hint.url) { NSWorkspace.shared.open(u) }
                },
            ]))
            return
        }
        if row.pid == Int(getpid()) {
            present(Prompt(title: "Port Dashboard", message: "Đây là chính Port Dashboard."))
            return
        }
        var msg = "\(row.app)\nPort \(row.port) · PID \(row.pid) · \(row.user)\n\nDữ liệu chưa lưu trong ứng dụng sẽ bị mất."
        if row.system {
            msg = "CẢNH BÁO: đây là dịch vụ hệ thống, dừng nó có thể làm macOS chạy sai.\n\n" + msg
        }
        present(Prompt(title: "Dừng ứng dụng này?", message: msg, actions: [
            PromptAction(label: "Dừng", role: .destructive) { self.kill(row, force: false, admin: false) },
        ]))
    }

    func kill(_ row: PortRow, force: Bool, admin: Bool) {
        let start = Proc.startTime(row.pid)
        let sig = force ? SIGKILL : SIGTERM
        if admin {
            let name = row.app.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\", with: "")
            let src = "do shell script \"/bin/kill -\(force ? "KILL" : "TERM") \(row.pid)\" with administrator privileges with prompt \"Port Dashboard cần quyền Admin để dừng \(name).\""
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
            if let err {
                if (err[NSAppleScript.errorNumber] as? Int) == -128 { return }   // nguoi dung bam Huy
                if Proc.startTime(row.pid) != start || start == nil {
                    show("\(row.app) đã thoát từ trước.")
                    refresh()
                    return
                }
                present(Prompt(title: "Không dừng được \(row.app)",
                               message: (err[NSAppleScript.errorMessage] as? String) ?? "Lỗi không rõ."))
                return
            }
        } else if Darwin.kill(pid_t(row.pid), sig) != 0 {
            switch errno {
            case ESRCH:
                show("\(row.app) đã thoát từ trước.")
                refresh()
            case EPERM:
                present(Prompt(title: "Cần quyền Admin",
                               message: "\(row.app) (PID \(row.pid)) do người dùng \"\(row.user)\" chạy. Cần quyền Admin để dừng nó.",
                               actions: [PromptAction(label: "Dừng với quyền Admin", role: .destructive) {
                                   self.kill(row, force: force, admin: true)
                               }]))
            default:
                present(Prompt(title: "Không dừng được \(row.app)", message: String(cString: strerror(errno))))
            }
            return
        }

        show("Đã gửi tín hiệu dừng tới \(row.app) (PID \(row.pid))...")
        waitForExit(row, start: start, waited: 0) { exited in
            if exited {
                self.show("Đã dừng \(row.app) - port \(row.port) đã được giải phóng.")
                self.refresh()
            } else if !force {
                self.present(Prompt(title: "Ứng dụng chưa thoát",
                                    message: "\(row.app) (PID \(row.pid)) vẫn đang chạy sau 2 giây.\n\nBuộc dừng ngay? Ứng dụng sẽ bị tắt lập tức.",
                                    actions: [PromptAction(label: "Buộc dừng", role: .destructive) {
                                        self.kill(row, force: true, admin: admin)
                                    }]))
            } else {
                self.show("Đã buộc dừng nhưng \(row.app) vẫn chạy.")
            }
        }
    }

    private func waitForExit(_ row: PortRow, start: String?, waited: Double, done: @escaping (Bool) -> Void) {
        let alive = start != nil && Proc.startTime(row.pid) == start
        if !alive { done(true); return }
        if waited >= 2 { done(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.waitForExit(row, start: start, waited: waited + 0.2, done: done)
        }
    }
}

// MARK: - Giao dien

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

func copyToPasteboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

struct ContentView: View {
    @EnvironmentObject var store: PortStore
    @AppStorage(Keys.autoRefresh) private var autoRefresh = true
    @AppStorage(Keys.refreshSeconds) private var refreshSeconds = 5
    @AppStorage(Keys.showInfoButton) private var showInfoButton = true
    @AppStorage(Keys.showSystem) private var showSystem = false
    @AppStorage(Keys.alwaysOnTop) private var alwaysOnTop = false

    @State private var search = ""
    @State private var selection: PortRow.ID?
    @State private var sortOrder = [KeyPathComparator(\PortRow.port)]
    @State private var detail: PortRow?
    @State private var showInfo = false
    @State private var window: NSWindow?

    private var visible: [PortRow] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return store.rows.filter { (showSystem || !$0.system) && $0.matches(q) }.sorted(using: sortOrder)
    }

    private var selectedRow: PortRow? { store.rows.first { $0.id == selection } }

    private var statusLine: String {
        if let n = store.notice { return n }
        guard store.loaded else { return "Đang đọc danh sách port..." }
        var parts = ["Đang hiện \(visible.count) port"]
        let hidden = store.rows.filter(\.system).count
        if !showSystem && hidden > 0 { parts.append("đã ẩn \(hidden) port hệ thống") }
        if let t = store.lastUpdated { parts.append("cập nhật lúc \(t.formatted(date: .omitted, time: .standard))") }
        if !autoRefresh { parts.append("không tự làm mới") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            table
            Divider()
            HStack(spacing: 12) {
                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(store.notice == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button("Dừng ứng dụng", role: .destructive) {
                    if let r = selectedRow { store.askKill(r) }
                }
                .disabled(selectedRow == nil)
                .keyboardShortcut(.delete, modifiers: [])
                .help("Dừng ứng dụng đang chiếm port đã chọn (phím Delete)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.bar)
        }
        .background(WindowAccessor { w in
            window = w
            w.level = alwaysOnTop ? .floating : .normal
        })
        .searchable(text: $search, placement: .toolbar, prompt: "Port, ứng dụng, PID, đường dẫn")
        .navigationTitle("Port Dashboard")
        .navigationSubtitle(store.loaded ? "\(visible.count) port đang mở" : "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.refresh()
                } label: {
                    Label("Làm mới", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Làm mới (⌘R)")
                if showInfoButton {
                    Button {
                        showInfo = true
                    } label: {
                        Label("Thông tin máy", systemImage: "desktopcomputer")
                    }
                    .help("Thông tin máy")
                }
                SettingsLink {
                    Label("Cài đặt", systemImage: "gearshape")
                }
                .help("Cài đặt (⌘,)")
            }
        }
        .alert(store.prompt?.title ?? "", isPresented: Binding(
            get: { store.prompt != nil },
            set: { if !$0 { store.prompt = nil } }
        ), presenting: store.prompt) { p in
            ForEach(p.actions) { a in
                Button(a.label, role: a.role) {
                    let run = a.run
                    DispatchQueue.main.async { run() }
                }
            }
            Button(p.actions.isEmpty ? "OK" : "Hủy", role: .cancel) {}
        } message: { p in
            Text(p.message)
        }
        .sheet(item: $detail) { row in
            DetailView(row: row) { store.askKill(row) }
        }
        .sheet(isPresented: $showInfo) { MachineInfoView() }
        .onAppear {
            store.refresh()
            store.schedule(enabled: autoRefresh, seconds: refreshSeconds)
        }
        .onChange(of: autoRefresh) { store.schedule(enabled: autoRefresh, seconds: refreshSeconds) }
        .onChange(of: refreshSeconds) { store.schedule(enabled: autoRefresh, seconds: refreshSeconds) }
        .onChange(of: alwaysOnTop) { window?.level = alwaysOnTop ? .floating : .normal }
    }

    private var table: some View {
        Table(visible, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Port", value: \.port) { r in
                Text(String(r.port)).monospacedDigit().fontWeight(.semibold)
            }
            .width(min: 48, ideal: 60, max: 80)

            TableColumn("Ứng dụng", value: \.app) { r in
                HStack(spacing: 6) {
                    Image(nsImage: IconCache.icon(for: r)).resizable().frame(width: 16, height: 16)
                    Text(r.app).lineLimit(1)
                }
                .help(r.process == r.app ? r.app : "\(r.app) — tiến trình: \(r.process)")
            }
            .width(min: 120, ideal: 190)

            TableColumn("Dùng để làm gì", value: \.desc) { r in
                Text(r.desc.isEmpty ? "—" : r.desc)
                    .foregroundStyle(r.desc.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 210)

            TableColumn("Phạm vi", value: \.scope) { r in
                Label(r.scope, systemImage: r.isPublic ? "globe" : "lock.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(r.isPublic ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .help(r.addrs.joined(separator: ", "))
            }
            .width(min: 100, ideal: 170)

            TableColumn("PID", value: \.pid) { r in
                Text(r.pidText).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 44, ideal: 60, max: 80)

            TableColumn("Người dùng", value: \.user) { r in
                Text(r.user).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 90, max: 140)

            TableColumn("Đường dẫn", value: \.exe) { r in
                Text(r.exe.isEmpty ? "—" : r.exe)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(r.exe)
            }
            .width(min: 120, ideal: 320)
        }
        .contextMenu(forSelectionType: PortRow.ID.self) { ids in
            if let id = ids.first, let r = store.rows.first(where: { $0.id == id }) {
                Button("Xem chi tiết") { detail = r }
                Button("Mở http://localhost:\(r.port) trong trình duyệt") {
                    if let u = URL(string: "http://localhost:\(r.port)") { NSWorkspace.shared.open(u) }
                }
                if !r.exe.isEmpty {
                    Button("Hiện trong Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.bundlePath.isEmpty ? r.exe : r.bundlePath)])
                    }
                }
                Divider()
                Button("Sao chép số port") { copyToPasteboard(String(r.port)) }
                Button("Sao chép PID") { copyToPasteboard(r.pidText) }
                if !r.cmd.isEmpty { Button("Sao chép câu lệnh") { copyToPasteboard(r.cmd) } }
                Divider()
                Button("Dừng ứng dụng...", role: .destructive) { store.askKill(r) }
            }
        } primaryAction: { ids in
            if let id = ids.first { detail = store.rows.first { $0.id == id } }
        }
        .overlay {
            if store.loaded && visible.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("Không có port nào đang mở",
                                           systemImage: "network.slash",
                                           description: Text(showSystem ? "" : "Port hệ thống đang được ẩn. Bật lại trong Cài đặt."))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }
}

struct DetailView: View {
    let row: PortRow
    let onKill: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let cwd = Proc.cwd(row.pid)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: IconCache.icon(for: row)).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.app).font(.title2).bold()
                    Text("Port \(row.port)\(row.desc.isEmpty ? "" : " · \(row.desc)")").foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                field("Tiến trình", row.process)
                field("Phạm vi", "\(row.scope) (\(row.addrs.joined(separator: ", ")))")
                field("PID", row.pidText)
                field("Người dùng", row.user)
                field("File chạy", row.exe.isEmpty ? "-" : row.exe)
                if let cwd { field("Thư mục", cwd) }
                field("Lệnh", row.cmd.isEmpty ? "-" : row.cmd)
            }
            if let hint = settingsHint(for: row) {
                Label(hint.text, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Mở trong trình duyệt") {
                    if let u = URL(string: "http://localhost:\(row.port)") { NSWorkspace.shared.open(u) }
                }
                if !row.exe.isEmpty {
                    Button("Hiện trong Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.bundlePath.isEmpty ? row.exe : row.bundlePath)])
                    }
                }
                Button("Sao chép") { copyToPasteboard(row.summary) }
                Spacer()
                Button("Dừng ứng dụng", role: .destructive) {
                    dismiss()
                    onKill()
                }
                Button("Đóng") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    @ViewBuilder
    private func field(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(6).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MachineInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items = MachineInfo.items()
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Thông tin máy", systemImage: "desktopcomputer").font(.title2).bold()
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                ForEach(items, id: \.0) { k, v in
                    GridRow {
                        Text(k).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(v).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Button(copied ? "Đã sao chép" : "Sao chép") {
                    copyToPasteboard(items.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
                    copied = true
                }
                Spacer()
                Button("Đóng") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                items = MachineInfo.items()
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage(Keys.autoRefresh) private var autoRefresh = true
    @AppStorage(Keys.refreshSeconds) private var refreshSeconds = 5
    @AppStorage(Keys.showInfoButton) private var showInfoButton = true
    @AppStorage(Keys.showSystem) private var showSystem = false
    @AppStorage(Keys.alwaysOnTop) private var alwaysOnTop = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Làm mới") {
                Toggle("Tự động làm mới danh sách port", isOn: $autoRefresh)
                LabeledContent("Làm mới mỗi") {
                    HStack(spacing: 6) {
                        TextField("", value: Binding(
                            get: { refreshSeconds },
                            set: { refreshSeconds = min(3600, max(1, $0)) }
                        ), format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        Stepper("", value: $refreshSeconds, in: 1...3600).labelsHidden()
                        Text("giây")
                    }
                }
                .disabled(!autoRefresh)
            }
            Section("Hiển thị") {
                Toggle("Hiện nút \"Thông tin máy\"", isOn: $showInfoButton)
                Toggle("Hiện port hệ thống của macOS", isOn: $showSystem)
                Toggle("Cửa sổ luôn nằm trên", isOn: $alwaysOnTop)
            }
            Section {
                Toggle("Tự mở khi đăng nhập macOS", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Khởi động")
            } footer: {
                Text("Có thể tắt ở Cài đặt hệ thống → Chung → Mục đăng nhập.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PortDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = PortStore()

    init() {
        // PortDashboard --list : in danh sach port ra man hinh roi thoat (de kiem tra / dung trong CI)
        if CommandLine.arguments.contains("--list") {
            for r in PortScanner.scan() {
                print([String(r.port), r.app, r.process, r.desc, r.scope, String(r.pid), r.user, r.system ? "system" : "", r.exe]
                    .joined(separator: " | "))
            }
            print(MachineInfo.items().map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
            exit(0)
        }
    }

    var body: some Scene {
        Window("Port Dashboard", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 780, minHeight: 360)
        }
        .defaultSize(width: 1180, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
        }
    }
}

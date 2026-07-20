import Foundation
import IOKit
import Darwin

struct BatteryInfo {
    var percent: Int = 0
    var isCharging = false
    var externalPower = false
    var cycleCount: Int = 0
    var healthPercent: Double = 0
}

struct ProcInfo: Identifiable {
    let pid: Int32
    let name: String
    let cpu: Double
    let memPercent: Double
    let rssBytes: Int64
    var id: Int32 { pid }
}

final class StatusMonitor: ObservableObject {
    static let shared = StatusMonitor()

    // CPU
    @Published var cpuUsage: Double = 0
    @Published var cpuHistory: [Double] = []
    @Published var loadAvg: [Double] = [0, 0, 0]
    // 内存
    @Published var memUsed: Int64 = 0
    @Published var memTotal: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    @Published var memHistory: [Double] = []
    @Published var swapUsed: Int64 = 0
    @Published var swapTotal: Int64 = 0
    // 网络
    @Published var netRxRate: Double = 0 // bytes/s
    @Published var netTxRate: Double = 0
    @Published var netRxHistory: [Double] = []
    @Published var netTxHistory: [Double] = []
    // 磁盘
    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    // 电池
    @Published var battery: BatteryInfo?
    // 进程
    @Published var processes: [ProcInfo] = []

    private var timer: Timer?
    private var prevCPUTicks: (busy: UInt64, total: UInt64)?
    private var prevNet: (rx: UInt64, tx: UInt64, time: Date)?
    private var tick = 0

    private init() {}

    func start() {
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
        if tick % 10 == 0 { sampleDisk() }
        if tick % 5 == 0 { sampleBattery() }
        if tick % 3 == 0 { sampleProcesses() }
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        loadAvg = loads
        tick += 1
    }

    private func push(_ value: Double, into history: inout [Double]) {
        history.append(value)
        if history.count > 60 { history.removeFirst(history.count - 60) }
    }

    // MARK: CPU

    private func sampleCPU() {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &numCPUs, &cpuInfo, &numCpuInfo) == KERN_SUCCESS,
              let info = cpuInfo else { return }
        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        let stateMax = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(numCPUs) {
            let user = UInt64(UInt32(bitPattern: info[cpu * stateMax + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[cpu * stateMax + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[cpu * stateMax + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[cpu * stateMax + Int(CPU_STATE_IDLE)]))
            busy += user + system + nice
            total += user + system + nice + idle
        }

        if let prev = prevCPUTicks, total > prev.total {
            let usage = Double(busy - prev.busy) / Double(total - prev.total)
            cpuUsage = min(max(usage, 0), 1)
            push(cpuUsage, into: &cpuHistory)
        }
        prevCPUTicks = (busy, total)
    }

    // MARK: 内存

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride
                                           / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let pageSize = Int64(vm_kernel_page_size)
        let used = (Int64(stats.active_count) + Int64(stats.wire_count)
                    + Int64(stats.compressor_page_count)) * pageSize
        memUsed = used
        push(Double(used) / Double(memTotal), into: &memHistory)

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            swapUsed = Int64(swap.xsu_used)
            swapTotal = Int64(swap.xsu_total)
        }
    }

    // MARK: 网络

    private func sampleNetwork() {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return }
        defer { freeifaddrs(ifaddrPtr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr = ifaddrPtr
        while let p = ptr {
            let ifa = p.pointee
            let name = String(cString: ifa.ifa_name)
            if let addr = ifa.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               name.hasPrefix("en"),
               let dataPtr = ifa.ifa_data {
                let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                rx &+= UInt64(data.ifi_ibytes)
                tx &+= UInt64(data.ifi_obytes)
            }
            ptr = ifa.ifa_next
        }

        let now = Date()
        if let prev = prevNet {
            let dt = now.timeIntervalSince(prev.time)
            if dt > 0, rx >= prev.rx, tx >= prev.tx {
                netRxRate = Double(rx - prev.rx) / dt
                netTxRate = Double(tx - prev.tx) / dt
                push(netRxRate, into: &netRxHistory)
                push(netTxRate, into: &netTxHistory)
            }
        }
        prevNet = (rx, tx, now)
    }

    // MARK: 磁盘

    private func sampleDisk() {
        let url = URL(fileURLWithPath: "/")
        if let rv = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                      .volumeAvailableCapacityForImportantUsageKey]) {
            diskTotal = Int64(rv.volumeTotalCapacity ?? 0)
            diskFree = rv.volumeAvailableCapacityForImportantUsage ?? 0
        }
    }

    // MARK: 电池

    private func sampleBattery() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { battery = nil; return }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            battery = nil
            return
        }

        var info = BatteryInfo()
        info.percent = props["CurrentCapacity"] as? Int ?? 0
        info.isCharging = props["IsCharging"] as? Bool ?? false
        info.externalPower = props["ExternalConnected"] as? Bool ?? false
        info.cycleCount = props["CycleCount"] as? Int ?? 0
        if let design = props["DesignCapacity"] as? Int, design > 0 {
            let nominal = (props["NominalChargeCapacity"] as? Int)
                ?? (props["AppleRawMaxCapacity"] as? Int) ?? design
            info.healthPercent = Double(nominal) / Double(design) * 100
        }
        battery = info
    }

    // MARK: 进程

    private func sampleProcesses() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let result = Shell.run("ps -Aceo pid=,pcpu=,pmem=,rss=,comm= -r | head -14")
            var procs: [ProcInfo] = []
            for line in result.output.split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
                guard parts.count == 5,
                      let pid = Int32(parts[0]),
                      let cpu = Double(parts[1]),
                      let mem = Double(parts[2]),
                      let rssKB = Int64(parts[3]) else { continue }
                procs.append(ProcInfo(pid: pid, name: String(parts[4]),
                                      cpu: cpu, memPercent: mem, rssBytes: rssKB * 1024))
            }
            let final = procs
            await MainActor.run { self.processes = final }
        }
    }

    // MARK: 格式化辅助

    var uptimeText: String {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let days = uptime / 86400
        let hours = (uptime % 86400) / 3600
        let mins = (uptime % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(mins) 分钟" }
        return "\(mins) 分钟"
    }

    static func rateText(_ bytesPerSec: Double) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .binary
        return fmt.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }
}

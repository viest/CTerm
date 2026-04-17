import Foundation
import Darwin.Mach

struct AppPerformanceSnapshot {
    let cpuPercent: Double
    let memoryBytes: UInt64

    var statusText: String {
        "\(formattedCPU)  \(formattedMemory)"
    }

    var tooltip: String {
        "CTerm CPU: \(formattedCPUValue)\nCTerm Memory: \(formattedMemoryValue)"
    }

    private var formattedCPU: String {
        "CPU \(formattedCPUValue)"
    }

    private var formattedMemory: String {
        "MEM \(formattedMemoryValue)"
    }

    private var formattedCPUValue: String {
        String(format: "%.1f%%", cpuPercent)
    }

    private var formattedMemoryValue: String {
        Self.byteFormatter.string(fromByteCount: Int64(memoryBytes))
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}

final class PerformanceMonitor {
    var onSnapshotUpdated: ((AppPerformanceSnapshot) -> Void)?

    private let queue = DispatchQueue(label: "cterm.performance-monitor", qos: .utility)

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.collectSnapshot()
            DispatchQueue.main.async {
                self.onSnapshotUpdated?(snapshot)
            }
        }
    }

    private func collectSnapshot() -> AppPerformanceSnapshot {
        AppPerformanceSnapshot(
            cpuPercent: currentCPUPercent(),
            memoryBytes: currentMemoryBytes()
        )
    }

    private func currentCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS, let threadList else {
            return 0
        }

        defer {
            let byteCount = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), byteCount)
        }

        var totalUsage = 0.0

        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.stride / MemoryLayout<integer_t>.stride)

            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threadList[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }

            guard result == KERN_SUCCESS else { continue }
            if (info.flags & TH_FLAGS_IDLE) == 0 {
                totalUsage += Double(info.cpu_usage) * 100.0 / Double(TH_USAGE_SCALE)
            }
        }

        return max(totalUsage, 0)
    }

    private func currentMemoryBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return info.phys_footprint
        }

        var basicInfo = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.stride / MemoryLayout<integer_t>.stride)

        let fallback = withUnsafeMutablePointer(to: &basicInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
            }
        }

        guard fallback == KERN_SUCCESS else { return 0 }
        return UInt64(basicInfo.resident_size)
    }
}

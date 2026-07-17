import Foundation
import Darwin

/// Polls the process's resident memory size every few seconds via the Mach
/// task info API. Cheap; refreshes ~every 2.5 seconds so we don't churn.
@MainActor
final class MemoryStat: ObservableObject {
    @Published private(set) var bytes: UInt64 = 0
    private var pollTask: Task<Void, Never>?

    var megabytes: Double { Double(bytes) / 1_048_576 }

    init() { start() }

    func start() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                self.bytes = Self.currentResidentBytes()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    deinit { pollTask?.cancel() }

    private static func currentResidentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}

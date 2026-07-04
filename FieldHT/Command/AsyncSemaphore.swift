import Foundation

public final class AsyncSemaphore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.fieldht.async-semaphore")
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(value: Int) {
        availablePermits = max(0, value)
    }

    public func wait() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.availablePermits > 0 {
                    self.availablePermits -= 1
                    continuation.resume()
                } else {
                    self.waiters.append(continuation)
                }
            }
        }
    }

    public func signal() {
        queue.async {
            if self.waiters.isEmpty {
                self.availablePermits += 1
            } else {
                self.waiters.removeFirst().resume()
            }
        }
    }

    public func withPermit<T>(_ operation: () async throws -> T) async rethrows -> T {
        await wait()

        do {
            let result = try await operation()
            signal()
            return result
        } catch {
            signal()
            throw error
        }
    }
}

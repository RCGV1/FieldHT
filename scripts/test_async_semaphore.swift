import Foundation

@main
struct AsyncSemaphoreSmokeTest {
    static func main() async {
        let semaphore = AsyncSemaphore(value: 1)
        var timeline: [String] = []
        let lock = NSLock()

        func append(_ event: String) {
            lock.lock()
            timeline.append(event)
            lock.unlock()
        }

        let first = Task {
            await semaphore.withPermit {
                append("first-start")
                try? await Task.sleep(nanoseconds: 150_000_000)
                append("first-end")
            }
        }

        try? await Task.sleep(nanoseconds: 20_000_000)

        let second = Task {
            await semaphore.withPermit {
                append("second-start")
                append("second-end")
            }
        }

        await first.value
        await second.value

        let expected = ["first-start", "first-end", "second-start", "second-end"]
        guard timeline == expected else {
            fputs("Expected serialized timeline \(expected), got \(timeline)\n", stderr)
            exit(1)
        }
    }
}

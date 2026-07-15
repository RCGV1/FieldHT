import Foundation

@main
enum RadioControlLayoutModelTests {
    static func main() {
        var failures = 0

        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        var layout = RadioControlLayout()
        expect(layout.sections.contains(.primaryChannels), "default layout includes primary channels")

        layout.hide(.primaryChannels)
        expect(layout.sections.contains(.primaryChannels), "primary channels cannot be hidden")

        layout.hide(.signalMeter)
        expect(!layout.sections.contains(.signalMeter), "optional sections can be hidden")

        layout.show(.signalMeter)
        expect(layout.sections.last == .signalMeter, "restored sections append to the visible layout")

        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        expect(layout.sections[2] == .memoryGroup, "moving a section preserves the requested order")

        let normalized = RadioControlLayout(sections: [.quickActions, .quickActions])
        expect(normalized.sections == [.quickActions, .primaryChannels], "saved layouts are deduplicated and retain primary channels")

        if failures > 0 {
            exit(1)
        }

        print("RadioControlLayoutModelTests passed")
    }
}

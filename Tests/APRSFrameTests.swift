import Foundation

@main
enum APRSFrameTests {
    static func main() {
        var failures = 0

        func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
            if actual != expected {
                failures += 1
                fputs("FAIL: \(message). Expected \(expected), got \(actual)\n", stderr)
            }
        }

        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        let sourceFrame = APRSFrame(
            source: "N0CALL-7",
            destination: "APRS",
            path: [
                APRSAddress("WIDE1-1", hasBeenRepeated: true),
                APRSAddress("WIDE2-2")
            ],
            information: "!4903.50N/07201.75W-Test"
        )

        let encoded = sourceFrame.ax25Data
        guard let decoded = APRSFrame(ax25Data: encoded) else {
            fputs("FAIL: valid UV-PRO AX.25 frame should decode\n", stderr)
            exit(1)
        }

        expectEqual(decoded, sourceFrame, "AX.25 radio frame round trips")
        expectEqual(
            decoded.aprsISLine(gatewayCallsign: "N6CH-7"),
            "N0CALL-7>APRS,WIDE1-1*,WIDE2-2,qAO,N6CH-7:!4903.50N/07201.75W-Test",
            "forwarded APRS frame preserves repeated hops and adds qAO"
        )
        expect(decoded.isSafeToGate, "ordinary APRS path is eligible for radio-to-internet forwarding")

        let blocked = APRSFrame(
            source: "N0CALL",
            destination: "APRS",
            path: [APRSAddress("RFONLY")],
            information: ">status"
        )
        expect(!blocked.isSafeToGate, "RFONLY packets are never forwarded to APRS-IS")

        guard let internetFrame = APRSFrame(aprsISLine: "N1ABC>APRS,WIDE1-1:>from APRS-IS") else {
            fputs("FAIL: valid APRS-IS packet should parse\n", stderr)
            exit(1)
        }
        expectEqual(
            APRSFrame(ax25Data: internetFrame.ax25Data),
            internetFrame,
            "APRS-IS packets encode to radio AX.25 frames"
        )

        var assembler = TncPacketAssembler()
        expectEqual(
            assembler.append(TncDataFragment(isFinalFragment: false, fragmentID: 0, data: Data(encoded.prefix(12)))),
            nil,
            "first radio fragment waits for final fragment"
        )
        expectEqual(
            assembler.append(TncDataFragment(isFinalFragment: true, fragmentID: 1, data: Data(encoded.dropFirst(12)))),
            encoded,
            "radio fragments reassemble in order"
        )

        let fragments = TncDataFragment.fragments(for: Data(repeating: 0xAA, count: 120))
        expectEqual(fragments.map(\.data.count), [50, 50, 20], "outbound radio packets split at the documented TNC payload size")
        expectEqual(fragments.map(\.fragmentID), [0, 1, 2], "outbound fragments use sequential IDs")
        expectEqual(fragments.map(\.isFinalFragment), [false, false, true], "only the final outbound fragment is marked final")

        expectEqual(APRSISPasscode.value(for: "N0CALL-7"), "13023", "APRS-IS passcode ignores SSID and matches the standard algorithm")

        if failures > 0 {
            exit(1)
        }

        print("APRSFrameTests passed")
    }
}

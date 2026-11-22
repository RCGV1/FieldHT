import Foundation

struct SatelliteRetuneTarget: Equatable, Sendable {
    let rxHz: Int
    let txHz: Int
    let rxTone: Double?
    let txTone: Double?

    init?(rxMHz: Double, txMHz: Double, rxTone: Double?, txTone: Double?) {
        guard rxMHz.isFinite, txMHz.isFinite,
              (0..<1073.741824).contains(rxMHz), (0..<1073.741824).contains(txMHz),
              rxMHz > 0 || txMHz > 0,
              [rxTone, txTone].allSatisfy({ tone in tone.map { $0.isFinite && $0 > 0 } ?? true }) else { return nil }
        let rx = Int((rxMHz * 1_000_000).rounded())
        let tx = Int((txMHz * 1_000_000).rounded())
        guard rx < 1 << 30, tx < 1 << 30 else { return nil }
        rxHz = rx
        txHz = tx
        self.rxTone = rxTone
        self.txTone = txTone
    }

    var rxMHz: Double { Double(rxHz) / 1_000_000 }
    var txMHz: Double { Double(txHz) / 1_000_000 }
}

struct SatelliteRetunePolicy {
    static let defaultThresholdHz = 1_000.0
    static let thresholdsHz = [0.0, 500, 1_000, 2_000]
    private(set) var lastApplied: SatelliteRetuneTarget?

    func shouldApply(_ target: SatelliteRetuneTarget, thresholdHz: Double,
                     holdDuringReceive: Bool, isReceiving: Bool, force: Bool = false) -> Bool {
        guard let lastApplied else { return true }
        guard target != lastApplied else { return false }
        if force || target.rxTone != lastApplied.rxTone || target.txTone != lastApplied.txTone { return true }
        if holdDuringReceive && isReceiving { return false }
        let delta = max(abs(target.rxHz - lastApplied.rxHz), abs(target.txHz - lastApplied.txHz))
        let threshold = thresholdHz.isFinite ? max(0, thresholdHz) : Self.defaultThresholdHz
        return delta > 0 && Double(delta) >= threshold
    }

    mutating func recordApplied(_ target: SatelliteRetuneTarget) { lastApplied = target }
    mutating func reset() { lastApplied = nil }
}

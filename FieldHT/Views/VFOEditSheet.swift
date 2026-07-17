import SwiftUI

struct VFOEditSheet: View {
    let channel: Channel
    let onUpdate: (Channel) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var rxFreqString: String
    @State private var txFreqString: String
    @State private var isSimplex: Bool
    @State private var bandwidth: BandwidthType
    @State private var txPowerMax: Bool
    @State private var scan: Bool

    init(channel: Channel, onUpdate: @escaping (Channel) -> Void) {
        self.channel = channel
        self.onUpdate = onUpdate
        _rxFreqString = State(initialValue: String(format: "%.5f", channel.rxFreq))
        _txFreqString = State(initialValue: String(format: "%.5f", channel.txFreq))
        _isSimplex = State(initialValue: abs(channel.rxFreq - channel.txFreq) < 0.00001)
        _bandwidth = State(initialValue: channel.bandwidth)
        _txPowerMax = State(initialValue: channel.txAtMaxPower)
        _scan = State(initialValue: channel.scan)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Frequency")) {
                    HStack {
                        Text("RX Freq")
                        Spacer()
                        TextField("145.000", text: $rxFreqString)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .onChange(of: rxFreqString) { _, newValue in
                                if isSimplex {
                                    txFreqString = newValue
                                }
                            }
                    }

                    Toggle("Simplex (TX=RX)", isOn: $isSimplex)
                        .onChange(of: isSimplex) { _, newValue in
                            if newValue {
                                txFreqString = rxFreqString
                            }
                        }

                    if !isSimplex {
                        HStack {
                            Text("TX Freq")
                            Spacer()
                            TextField("145.600", text: $txFreqString)
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section(header: Text("Transmission")) {
                    Picker("Bandwidth", selection: $bandwidth) {
                        Text("Narrow (12.5k)").tag(BandwidthType.narrow)
                        Text("Wide (25k)").tag(BandwidthType.wide)
                    }

                    Toggle("High Power", isOn: $txPowerMax)
                    Toggle("Scan", isOn: $scan)
                }

                Section(footer: Text("Changes will be sent to the radio immediately on save.")) {
                     Button("Save Settings") {
                         save()
                     }
                     .frame(maxWidth: .infinity)
                     .foregroundColor(.orange)
                }
            }
            .navigationTitle("VFO Config")
            .scrollDismissesKeyboard(.interactively)
            .fieldHTKeyboardDismissal()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        if let rx = Double(rxFreqString), let tx = Double(isSimplex ? rxFreqString : txFreqString) {
            var updated = channel
            updated.rxFreq = rx
            updated.txFreq = tx
            updated.bandwidth = bandwidth
            updated.txAtMaxPower = txPowerMax
            updated.scan = scan
            onUpdate(updated)
            dismiss()
        }
    }
}

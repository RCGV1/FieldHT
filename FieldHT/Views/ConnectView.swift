import SwiftUI
import CoreBluetooth

struct ConnectView: View {
    @EnvironmentObject var radioManager: RadioManager
    @Environment(\.openURL) private var openURL
    @StateObject private var scanner = BLEScanner()
    @State private var selectedDevice: DiscoveredDevice?
    @State private var hasStartedInitialScan = false

    private let accentOrange = Color(red: 0.96, green: 0.48, blue: 0.19)
    private let accentBlue = Color(red: 0.28, green: 0.63, blue: 0.95)
    private let pageBackgroundTop = Color(uiColor: .systemGroupedBackground)
    private let pageBackgroundBottom = Color(uiColor: .secondarySystemGroupedBackground)
    private let cardFill = Color(uiColor: .secondarySystemGroupedBackground)
    private let cardStroke = Color.white.opacity(0.08)

    private var isBusy: Bool {
        radioManager.isConnecting || radioManager.isAutoReconnecting || radioManager.isDisconnecting
    }

    private var savedDevice: DiscoveredDevice? {
        guard let uuid = radioManager.lastPairedDeviceUUID else { return nil }
        return scanner.knownDevice(for: uuid)
    }

    private var hasSavedRadio: Bool {
        radioManager.lastPairedDeviceUUID != nil
    }

    private var savedRadioName: String {
        savedDevice?.name ?? "Saved radio"
    }

    private var connectedDeviceName: String {
        if let selectedDevice {
            return selectedDevice.name
        }
        if let savedDevice {
            return savedDevice.name
        }
        if hasSavedRadio {
            return savedRadioName
        }
        return "Your radio"
    }

    private var nearbyDevices: [DiscoveredDevice] {
        scanner.discoveredDevices
    }

    private var heroEyebrow: String {
        if radioManager.isConnected {
            return "Connected Radio"
        }
        if hasSavedRadio {
            return "Saved Radio"
        }
        return "Radio"
    }

    private var heroTitle: String {
        if radioManager.isConnected {
            return connectedDeviceName
        }
        if radioManager.isAutoReconnecting {
            return "Reconnecting to \(connectedDeviceName)"
        }
        if radioManager.isConnecting {
            return selectedDevice?.name ?? "Connecting"
        }
        if let savedDevice {
            return savedDevice.name
        }
        if hasSavedRadio {
            return savedRadioName
        }
        return "Connect your radio"
    }

    private var heroSubtitle: String {
        if radioManager.isConnected {
            return "You are ready to control the radio. Disconnect here if you want to switch devices."
        }
        if radioManager.isAutoReconnecting {
            return "Trying your last radio again."
        }
        if radioManager.isConnecting {
            return "Opening the Bluetooth link."
        }
        if radioManager.isRadioReconnectPaused {
            return "Connection attempts are paused. Reconnect when the radio is nearby, or choose another radio."
        }
        if hasSavedRadio {
            return "Reconnect in one tap, forget this radio, or scan for a different one nearby."
        }
        return "Scan nearby radios, then put your radio into pairing and tap it to connect."
    }

    private var heroSymbol: String {
        if radioManager.isConnected {
            return "checkmark.circle.fill"
        }
        if isBusy {
            return "dot.radiowaves.left.and.right"
        }
        return "antenna.radiowaves.left.and.right"
    }

    private var heroTint: Color {
        if radioManager.isConnected {
            return Color.green
        }
        if scanner.bluetoothState == .poweredOn {
            return accentOrange
        }
        return Color.orange
    }

    private var busyActionTitle: String {
        if radioManager.isDisconnecting { return "Disconnecting..." }
        if radioManager.isAutoReconnecting {
            return "Reconnecting: attempt \(radioManager.reconnectAttempt + 1) of \(ConnectionUXPolicy.maximumAutomaticRadioAttempts)"
        }
        if radioManager.isConnecting {
            return "Connecting..."
        }
        return "Scanning..."
    }

    private var canScan: Bool {
        scanner.bluetoothState == .poweredOn
    }

    private var shouldShowPairingInstructions: Bool {
        !radioManager.isConnected && (!hasSavedRadio || scanner.isScanning) && nearbyDevices.isEmpty && canScan
    }

    private var bluetoothStatusTitle: String {
        switch scanner.bluetoothState {
        case .poweredOff:
            return "Bluetooth is off"
        case .unauthorized:
            return "Bluetooth permission is needed"
        case .unsupported:
            return "Bluetooth is unavailable"
        case .resetting, .unknown:
            return "Preparing Bluetooth"
        case .poweredOn:
            return "Bluetooth is ready"
        @unknown default:
            return "Bluetooth is unavailable"
        }
    }

    private var bluetoothStatusDetail: String {
        switch scanner.bluetoothState {
        case .poweredOff:
            return "Turn on Bluetooth to scan for a different radio."
        case .unauthorized:
            return "Allow Bluetooth access for FieldHT in Settings."
        case .unsupported:
            return "This device cannot scan for Bluetooth radios."
        case .resetting, .unknown:
            return "This usually takes a moment."
        case .poweredOn:
            return ""
        @unknown default:
            return "Bluetooth is not ready yet."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard

                if !radioManager.isConnected,
                   !isBusy,
                   let error = radioManager.connectionError,
                   !error.isEmpty {
                    errorCard(error)
                }

                if !radioManager.isConnected {
                    nearbyRadiosCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(backgroundView.ignoresSafeArea())
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            guard !radioManager.isConnected, !radioManager.isDisconnecting else { return }
            rescan()
        }
        .task {
            updateScanningState()
        }
        .onChange(of: scanner.bluetoothState) {
            updateScanningState()
        }
        .onChange(of: radioManager.isConnected) {
            if radioManager.isConnected,
               selectedDevice == nil,
               let savedDevice {
                selectedDevice = savedDevice
            }
            updateScanningState()
        }
        .onChange(of: radioManager.isConnecting) { updateScanningState() }
        .onChange(of: radioManager.isAutoReconnecting) {
            if radioManager.isAutoReconnecting { selectedDevice = savedDevice }
        }
        .onDisappear {
            scanner.stopScanning()
        }
        .animation(.snappy(duration: 0.25), value: radioManager.isConnected)
        .animation(.snappy(duration: 0.25), value: scanner.isScanning)
    }

    private var backgroundView: some View {
        LinearGradient(
            colors: [pageBackgroundTop, pageBackgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private var heroCard: some View {
        let content = card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(heroTint.opacity(0.14))
                            .frame(width: 52, height: 52)

                        Image(systemName: heroSymbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(heroTint)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(heroEyebrow)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(heroTitle)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(heroSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                if radioManager.isConnected {
                    Button(role: .destructive) {
                        radioManager.disconnect()
                        selectedDevice = nil
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                } else if isBusy {
                    ProgressView(busyActionTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !radioManager.isDisconnecting {
                        Button("Cancel Connection", role: .cancel) {
                            hasStartedInitialScan = true
                            scanner.stopScanning()
                            radioManager.cancelRadioConnection()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("radio.cancelConnection")
                        scanButton(title: "Choose Another Radio")
                    }
                } else if hasSavedRadio {
                    ViewThatFits {
                        HStack(spacing: 10) {
                            reconnectButton
                            scanButton(title: "Find Another Radio")
                        }

                        VStack(spacing: 10) {
                            reconnectButton
                            scanButton(title: "Find Another Radio")
                        }
                    }
                } else {
                    scanButton(title: "Scan Nearby Radios")
                }

                if hasSavedRadio {
                    Toggle("Reconnect Automatically", isOn: $radioManager.autoReconnectEnabled)
                        .disabled(radioManager.isDisconnecting)
                    Text("Automatic attempts stop after three failures. Cancel pauses this session without forgetting the radio.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !radioManager.isConnected {
                        Button("Forget Saved Radio", role: .destructive, action: forgetSavedRadio)
                            .buttonStyle(.borderless)
                            .disabled(radioManager.isDisconnecting)
                    }
                }

                if shouldShowPairingInstructions {
                    Text(pairingInstructionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        content
    }

    private var nearbyRadiosCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nearby Radios")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Choose a radio to connect.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)
                    if scanner.isScanning {
                        Button("Stop Scan") { scanner.stopScanning() }
                            .accessibilityIdentifier("radio.stopScan")
                    } else {
                        Button("Scan", action: rescan)
                            .disabled(!canScan || radioManager.isDisconnecting)
                    }
                }

                if !canScan {
                    nearbyMessageRow(
                        symbol: "bolt.horizontal.circle",
                        tint: Color.orange,
                        title: bluetoothStatusTitle,
                        detail: bluetoothStatusDetail
                    )
                    if scanner.bluetoothState == .unauthorized {
                        Button("Open Settings", systemImage: "gear") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if nearbyDevices.isEmpty {
                    nearbyEmptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(nearbyDevices.enumerated()), id: \.element.id) { index, device in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 54)
                            }

                            nearbyRadioRow(device)
                        }
                    }
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    private var nearbyEmptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            if scanner.isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Looking for radios nearby...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            } else {
                Text("No radios found yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            if shouldShowPairingInstructions {
                Text(pairingInstructionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(scanner.isScanning ? "Scanning for up to 15 seconds. You can stop at any time." : "Tap Scan to refresh nearby radios. Your saved radio does not need to be forgotten first.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func nearbyRadioRow(_ device: DiscoveredDevice) -> some View {
        Button {
            selectedDevice = device
            connectToDevice(device)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accentBlue.opacity(0.14))
                        .frame(width: 40, height: 40)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentBlue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(deviceSubtitle(for: device))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if selectedDevice?.id == device.id && isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(radioManager.isDisconnecting || radioManager.isConnected)
    }

    private func nearbyMessageRow(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
                .padding(.top, 1)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            }
    }

    private func scanButton(title: String) -> some View {
        Button {
            rescan()
        } label: {
            Label(title, systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.primary)
        .disabled(!canScan || radioManager.isDisconnecting)
    }

    private var reconnectButton: some View {
        Button {
            reconnectSavedRadio()
        } label: {
            Label("Reconnect", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(accentOrange)
        .disabled(isBusy)
    }

    private func deviceSubtitle(for device: DiscoveredDevice) -> String {
        let signal = signalLabel(for: device.rssi)
        if device.isPaired {
            return "Saved radio • \(signal)"
        }
        return signal
    }

    private func signalLabel(for rssi: Int) -> String {
        if rssi >= -65 { return "Strong signal" }
        if rssi >= -78 { return "Nearby" }
        return "Farther away"
    }

    private var pairingInstructionText: String {
        if !canScan {
            return "Turn on Bluetooth, then on the radio open Main Menu and toggle Pairing."
        }
        return "On the radio, open Main Menu and toggle Pairing."
    }

    private func rescan() {
        guard canScan, !radioManager.isConnected, !radioManager.isDisconnecting else { return }
        hasStartedInitialScan = true
        radioManager.cancelRadioConnection()
        scanner.stopScanning()
        scanner.startScanning()
    }

    private func updateScanningState() {
        if !radioManager.isConnected,
           !radioManager.isConnecting,
           !hasSavedRadio,
           !hasStartedInitialScan,
           !radioManager.isRadioReconnectPaused,
           canScan,
           !scanner.isScanning {
            hasStartedInitialScan = true
            scanner.startScanning()
        }

        if (radioManager.isConnected || radioManager.isConnecting), scanner.isScanning {
            scanner.stopScanning()
        }
    }

    private func connectToDevice(_ device: DiscoveredDevice) {
        hasStartedInitialScan = true
        scanner.stopScanning()
        radioManager.cancelRadioConnection()
        selectedDevice = device
        radioManager.connect(to: device.id)
    }

    private func reconnectSavedRadio() {
        guard let savedUUID = radioManager.lastPairedDeviceUUID else { return }
        hasStartedInitialScan = true
        scanner.stopScanning()
        selectedDevice = savedDevice
        radioManager.connect(to: savedUUID)
    }

    private func forgetSavedRadio() {
        let savedUUID = radioManager.lastPairedDeviceUUID
        hasStartedInitialScan = true
        scanner.stopScanning()
        radioManager.forgetLastPairedRadio()
        scanner.clearLastPairedDevice()

        if selectedDevice?.id == savedUUID {
            selectedDevice = nil
        }
    }
}

#Preview {
    NavigationStack {
        ConnectView()
            .environmentObject(RadioManager(restoreSavedRadio: false))
    }
}

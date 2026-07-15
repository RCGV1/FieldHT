import SwiftUI
import CoreBluetooth

struct ConnectView: View {
    @EnvironmentObject var radioManager: RadioManager
    @StateObject private var scanner = BLEScanner()
    @State private var selectedDevice: DiscoveredDevice?

    private let accentOrange = Color(red: 0.96, green: 0.48, blue: 0.19)
    private let accentBlue = Color(red: 0.28, green: 0.63, blue: 0.95)
    private let pageBackgroundTop = Color(uiColor: .systemGroupedBackground)
    private let pageBackgroundBottom = Color(uiColor: .secondarySystemGroupedBackground)
    private let cardFill = Color(uiColor: .secondarySystemGroupedBackground)
    private let cardStroke = Color.white.opacity(0.08)

    private var isBusy: Bool {
        radioManager.isConnecting || radioManager.isAutoReconnecting
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
        scanner.discoveredDevices.filter { device in
            guard let savedDevice else { return true }
            return device.id != savedDevice.id
        }
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
        if radioManager.isAutoReconnecting {
            return "Reconnecting..."
        }
        if radioManager.isConnecting {
            return "Connecting..."
        }
        return "Scanning..."
    }

    private var shouldShowHeaderScanAction: Bool {
        !radioManager.isConnected && (hasSavedRadio || !nearbyDevices.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard

                if let error = radioManager.connectionError, !error.isEmpty {
                    errorCard(error)
                }

                nearbyRadiosCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(backgroundView.ignoresSafeArea())
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            guard !radioManager.isConnected, !radioManager.isConnecting else { return }
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
        .onDisappear {
            if !radioManager.isConnected {
                scanner.stopScanning()
            }
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
                } else if isBusy {
                    Button {} label: {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(busyActionTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentOrange)
                    .disabled(true)
                } else if hasSavedRadio {
                    ViewThatFits {
                        HStack(spacing: 10) {
                            if let savedDevice {
                                connectButton(for: savedDevice, title: "Connect \(savedDevice.name)")
                            }
                            scanButton(title: "Scan Nearby")
                        }

                        VStack(spacing: 10) {
                            if let savedDevice {
                                connectButton(for: savedDevice, title: "Connect \(savedDevice.name)")
                            }
                            scanButton(title: "Scan Nearby")
                        }
                    }
                } else {
                    scanButton(title: "Scan Nearby Radios")
                }

                Text(pairingInstructionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if !radioManager.isConnected && !isBusy && hasSavedRadio {
            SwipeActionCard(
                content: content,
                actionLabel: "Forget",
                actionSystemImage: "trash",
                action: forgetSavedRadio
            )
        } else {
            content
        }
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

                    if shouldShowHeaderScanAction {
                        Button(scanner.isScanning ? "Scanning..." : "Scan") {
                            rescan()
                        }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                        .disabled(scanner.bluetoothState != .poweredOn || isBusy)
                    }
                }

                if radioManager.isConnected {
                    nearbyMessageRow(
                        symbol: "checkmark.circle",
                        tint: Color.green,
                        title: "Radio connected",
                        detail: "Disconnect above if you want to switch to a different radio."
                    )
                } else if scanner.bluetoothState != .poweredOn {
                    nearbyMessageRow(
                        symbol: "bolt.horizontal.circle",
                        tint: Color.orange,
                        title: "Bluetooth is off",
                        detail: "Turn on Bluetooth, then scan again."
                    )
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

            Text(pairingInstructionText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if savedDevice == nil {
                scanButton(title: scanner.isScanning ? "Scanning..." : "Start Scan")
                    .disabled(scanner.bluetoothState != .poweredOn || isBusy || scanner.isScanning)
            }
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
        .disabled(isBusy || radioManager.isConnected)
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

    private func connectButton(for device: DiscoveredDevice, title: String) -> some View {
        Button {
            selectedDevice = device
            connectToDevice(device)
        } label: {
            Label(title, systemImage: "dot.radiowaves.left.and.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(accentOrange)
        .disabled(scanner.bluetoothState != .poweredOn || isBusy)
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
        .disabled(scanner.bluetoothState != .poweredOn || isBusy)
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
        if scanner.bluetoothState != .poweredOn {
            return "Turn on Bluetooth, then on the radio open Main Menu and toggle Pairing."
        }
        return "On the radio, open Main Menu and toggle Pairing."
    }

    private func rescan() {
        scanner.stopScanning()
        scanner.startScanning()
    }

    private func updateScanningState() {
        if !radioManager.isConnected,
           !radioManager.isConnecting,
           scanner.bluetoothState == .poweredOn,
           !scanner.isScanning {
            scanner.startScanning()
        }

        if (radioManager.isConnected || radioManager.isConnecting), scanner.isScanning {
            scanner.stopScanning()
        }
    }

    private func connectToDevice(_ device: DiscoveredDevice) {
        scanner.validateRadioService(device) { isRadio in
            guard isRadio else {
                print("Not a radio device")
                return
            }

            scanner.saveLastPairedDevice(device)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                radioManager.connect(to: device.peripheral.identifier)
            }
        }
    }

    private func forgetSavedRadio() {
        let savedUUID = radioManager.lastPairedDeviceUUID

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
            .environmentObject(RadioManager())
    }
}

private struct SwipeActionCard<Content: View>: View {
    let content: Content
    let actionLabel: String
    let actionSystemImage: String
    let action: () -> Void

    @State private var offsetX: CGFloat = 0

    private let revealWidth: CGFloat = 104

    init(
        content: Content,
        actionLabel: String,
        actionSystemImage: String,
        action: @escaping () -> Void
    ) {
        self.content = content
        self.actionLabel = actionLabel
        self.actionSystemImage = actionSystemImage
        self.action = action
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                withAnimation(.snappy(duration: 0.2)) {
                    offsetX = 0
                }
                action()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: actionSystemImage)
                        .font(.headline)
                    Text(actionLabel)
                        .font(.footnote.weight(.semibold))
                }
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .foregroundStyle(.white)
                .padding(.vertical, 22)
            }
            .buttonStyle(.plain)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            content
                .offset(x: offsetX)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            let proposedOffset = value.translation.width
                            offsetX = min(0, max(-revealWidth, proposedOffset))
                        }
                        .onEnded { value in
                            withAnimation(.snappy(duration: 0.2)) {
                                if value.translation.width < -(revealWidth * 0.45) {
                                    offsetX = -revealWidth
                                } else {
                                    offsetX = 0
                                }
                            }
                        }
                )
                .onTapGesture {
                    if offsetX != 0 {
                        withAnimation(.snappy(duration: 0.2)) {
                            offsetX = 0
                        }
                    }
                }
        }
        .clipped()
    }
}

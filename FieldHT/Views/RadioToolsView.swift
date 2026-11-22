import SwiftUI
import UniformTypeIdentifiers

struct RadioToolsView: View {
    @ObservedObject var controller: RadioController

    var body: some View {
        List {
            Section {
                if controller.deviceInfo.supportsRadio {
                    NavigationLink { FMRadioView(controller: controller) } label: { Label("FM Broadcast Radio", systemImage: "radio") }
                }
                NavigationLink { RadioPairingsView(controller: controller) } label: { Label("Radio Bluetooth Pairings", systemImage: "link") }
                NavigationLink { RadioFirmwareView(controller: controller) } label: { Label("Radio Firmware", systemImage: "cpu") }
                NavigationLink { RadioBackupView(controller: controller) } label: { Label("Backup & Restore", systemImage: "externaldrive") }
            }
        }
        .navigationTitle("Radio Tools")
    }
}

private struct RadioPairingsView: View {
    @ObservedObject var controller: RadioController
    @State private var devices: [TrustedBluetoothDevice] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDevice: TrustedBluetoothDevice?

    var body: some View {
        List {
            Section {
                if isLoading { ProgressView("Reading pairings...") }
                if devices.isEmpty && !isLoading && errorMessage == nil {
                    Text("The radio has no saved Bluetooth pairings.").foregroundStyle(.secondary)
                }
                ForEach(devices) { device in
                    LabeledContent {
                        Button("Forget", role: .destructive) { selectedDevice = device }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Forget \(device.name.isEmpty ? device.formattedAddress : device.name)")
                    } label: {
                        VStack(alignment: .leading) {
                            Text(device.name.isEmpty ? "Unnamed Device" : device.name)
                            Text(device.formattedAddress).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("These pairings are stored on the radio. Removing this phone's pairing may disconnect FieldHT and require pairing again.")
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("Bluetooth Pairings")
        .disabled(isLoading || controller.isPerformingMaintenance || !controller.isConnected)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog("Forget Radio Pairing?", isPresented: Binding(
            get: { selectedDevice != nil },
            set: { if !$0 { selectedDevice = nil } }
        ), presenting: selectedDevice) { device in
            Button("Forget \(device.name.isEmpty ? device.formattedAddress : device.name)", role: .destructive) {
                Task {
                    isLoading = true
                    errorMessage = nil
                    do {
                        try await controller.forgetBluetoothDevice(device)
                        devices.removeAll { $0.id == device.id }
                        try await Task.sleep(for: .milliseconds(500))
                        if controller.isConnected { devices = try await controller.trustedBluetoothDevices() }
                    } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
                    isLoading = false
                }
            }
            Button("Cancel", role: .cancel) { selectedDevice = nil }
        } message: { device in Text("Remove \(device.formattedAddress) from the radio's saved devices?") }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { devices = try await controller.trustedBluetoothDevices() }
        catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
}

private struct RadioFirmwareView: View {
    @ObservedObject var controller: RadioController
    @State private var update: RadioFirmwareUpdate?
    @State private var isChecking = false
    @State private var checked = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Connected Radio") {
                LabeledContent("Installed Firmware", value: RadioFirmwareUpdate.describe(controller.deviceInfo.firmwareVersion))
                LabeledContent("Product ID", value: String(controller.deviceInfo.productID))
                Button { Task { await check() } } label: {
                    if isChecking { ProgressView("Checking...") } else { Text("Check for Firmware Updates") }
                }
                .disabled(isChecking || !controller.isConnected)
            }
            if checked {
                Section("Available Firmware") {
                    if let update {
                        LabeledContent("Latest Stable Version", value: update.versionDescription)
                        Text(update.version > controller.deviceInfo.firmwareVersion ? "A newer firmware version is available." : "Your radio is up to date.")
                        if let date = update.releaseDate { LabeledContent("Released", value: date.formatted(date: .abbreviated, time: .omitted)) }
                        if !update.releaseNotes.isEmpty { Text(update.releaseNotes).textSelection(.enabled) }
                    } else { Text("The manufacturer returned no firmware for this radio.") }
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            Section {
                Text("Install firmware using the manufacturer's app. FieldHT checks stable releases without changing the radio.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Radio Firmware")
    }

    private func check() async {
        isChecking = true
        checked = false
        errorMessage = nil
        let productID = controller.deviceInfo.productID
        defer { isChecking = false }
        do {
            let result = try await FirmwareUpdateService().check(productID: productID)
            guard controller.isConnected, controller.deviceInfo.productID == productID else { return }
            update = result
            checked = true
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
}

private struct RadioBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 4 * 1024 * 1024 else { throw RadioBackupError.invalidFile("Unable to read this file.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct RadioBackupView: View {
    @ObservedObject var controller: RadioController
    @State private var document: RadioBackupDocument?
    @State private var importedBackup: RadioBackup?
    @State private var exporting = false
    @State private var importing = false
    @State private var isWorking = false
    @State private var progress = 0.0
    @State private var progressLabel = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button("Create Full Backup", systemImage: "square.and.arrow.up") { Task { await capture() } }
                Button("Restore from Backup", systemImage: "square.and.arrow.down") { importing = true }
            } footer: {
                Text("Includes every memory group, VFOs, radio settings, and programmable buttons. Bluetooth pairings are excluded. Restore requires matching hardware and firmware.")
            }
            if !progressLabel.isEmpty {
                Section { ProgressView(progressLabel, value: progress).accessibilityValue("\(Int(progress * 100)) percent") }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) } }
        }
        .disabled(isWorking || !controller.isConnected)
        .navigationTitle("Backup & Restore")
        .navigationBarBackButtonHidden(isWorking)
        .interactiveDismissDisabled(isWorking)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "FieldHT-Backup") { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 4 * 1024 * 1024 else { throw RadioBackupError.invalidFile("The file is too large.") }
                let backup = try RadioBackup.decode(Data(contentsOf: url, options: .mappedIfSafe))
                try backup.validate(for: controller.deviceInfo)
                importedBackup = backup
            } catch { errorMessage = error.localizedDescription }
        }
        .alert("Replace Radio Configuration?", isPresented: Binding(
            get: { importedBackup != nil },
            set: { if !$0 { importedBackup = nil } }
        ), presenting: importedBackup) { backup in
            Button("Restore", role: .destructive) {
                Task { await restore(backup) }
            }
            Button("Cancel", role: .cancel) { importedBackup = nil }
        } message: { _ in
            Text("This replaces all memory groups, VFOs, settings, and buttons with the selected backup. Keep the radio powered on and nearby until complete.")
        }
    }

    private func capture() async {
        isWorking = true
        errorMessage = nil
        progress = 0
        progressLabel = "Reading radio configuration..."
        defer { isWorking = false }
        do {
            let backup = try await RadioBackupService.capture(from: controller) { progress = $0; progressLabel = $1 }
            document = RadioBackupDocument(data: try backup.encoded())
            exporting = true
        } catch { errorMessage = error.localizedDescription; progressLabel = "" }
    }

    private func restore(_ backup: RadioBackup) async {
        isWorking = true
        errorMessage = nil
        progress = 0
        progressLabel = "Restoring radio configuration..."
        defer { isWorking = false; importedBackup = nil }
        do {
            try await RadioBackupService.restore(backup, to: controller) { progress = $0; progressLabel = $1 }
        } catch { errorMessage = error.localizedDescription; progressLabel = "" }
    }
}

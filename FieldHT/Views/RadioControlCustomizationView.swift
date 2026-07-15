import SwiftUI

struct RadioControlCustomizationView: View {
    @EnvironmentObject private var radioControlLayout: RadioControlLayoutStore

    var body: some View {
        List {
            Section {
                ForEach(radioControlLayout.sections) { section in
                    HStack(spacing: 12) {
                        Image(systemName: section.systemImage)
                            .foregroundStyle(.blue)
                            .frame(width: 22)

                        Text(section.title)

                        Spacer()

                        if section.isRemovable {
                            Button {
                                radioControlLayout.hide(section)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(section.title)")
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("\(section.title) stays visible")
                        }
                    }
                }
                .onMove(perform: radioControlLayout.move)
            } header: {
                Text("Visible")
            }

            if !radioControlLayout.hiddenSections.isEmpty {
                Section {
                    ForEach(radioControlLayout.hiddenSections) { section in
                        Button {
                            radioControlLayout.show(section)
                        } label: {
                            Label(section.title, systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Hidden")
                }
            }

            Section {
                Button("Restore Default Layout") {
                    radioControlLayout.restoreDefaults()
                }
            }
        }
        .navigationTitle("Radio Control Layout")
        .toolbar {
            EditButton()
        }
    }
}

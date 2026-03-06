import SwiftUI

struct ChannelSelectionView: View {
    @ObservedObject var viewModel: ChannelViewModel
    let selectedID: Int
    let onSelect: (Int) -> Void

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        List {
            ForEach(viewModel.channels, id: \.channelID) { channel in
                HStack {
                    Text(String(format: "%03d", channel.channelID + 1))
                        .font(.caption)
                        .monospacedDigit()
                        .padding(4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)

                    VStack(alignment: .leading) {
                        Text(channel.name.isEmpty
                             ? "Channel \(channel.channelID + 1)"
                             : channel.name)
                            .font(.headline)
                        Text(String(format: "%.5f MHz", channel.rxFreq))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if channel.channelID == selectedID {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(channel.channelID)
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .navigationTitle("Select Channel")
    }
}

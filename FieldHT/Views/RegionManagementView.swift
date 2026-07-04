//
//  RegionManagementView.swift
//  FieldHT
//
//  Refactored for better SwiftUI experience
//

import SwiftUI

struct RegionManagementView: View {
    @ObservedObject var viewModel: ChannelViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var editingRegionIndex: Int?
    @State private var editingName: String = ""
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Array(viewModel.regions.enumerated()), id: \.offset) { index, name in
                    regionRow(index: index, name: name)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Memory Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func regionRow(index: Int, name: String) -> some View {
        if editingRegionIndex == index {
            editingRow(index: index)
        } else {
            displayRow(index: index, name: name)
        }
    }
    
    private func displayRow(index: Int, name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundColor(.orange)
                .font(.body)
            
            Text(name.isEmpty ? "Memory Group \(index + 1)" : name)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button {
                startEditing(index: index)
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
                    .font(.body)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func editingRow(index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.circle.fill")
                .foregroundColor(.blue)
                .font(.title3)
            
            TextField("Memory Group Name", text: $editingName)
                .textFieldStyle(.plain)
                .font(.body)
                .autocorrectionDisabled()
                .textContentType(.name)
            
            Spacer()
            
            Button {
                saveRegionName(index: index)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            Button {
                cancelEditing()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func startEditing(index: Int) {
        editingRegionIndex = index
        editingName = viewModel.regions.indices.contains(index) ? viewModel.regions[index] : ""
    }
    
    private func cancelEditing() {
        editingRegionIndex = nil
        editingName = ""
    }
    
    private func saveRegionName(index: Int) {
        let nameToSave = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.renameRegion(index, name: nameToSave)
        editingRegionIndex = nil
        editingName = ""
    }
}

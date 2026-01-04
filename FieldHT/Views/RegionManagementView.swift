//
//  RegionManagementView.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/14/25.
//

import SwiftUI

struct RegionManagementView: View {
    @ObservedObject var viewModel: ChannelViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var editingRegionIndex: Int?
    @State private var editingName: String = ""
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Array(viewModel.regions.enumerated()), id: \.offset) { index, name in
                    HStack {
                        if editingRegionIndex == index {
                            TextField("Region Name", text: $editingName, onCommit: {
                                saveRegionName(index: index)
                            })
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button(action: { saveRegionName(index: index) }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        } else {
                            Button(action: {
                                viewModel.setActiveRegion(index)
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                Text(name.isEmpty ? "Region \(index + 1)" : name)
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                startEditing(index: index, name: name)
                            }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }
            }
            .navigationTitle("Memory Groups")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func startEditing(index: Int, name: String) {
        editingRegionIndex = index
        editingName = name
    }
    
    private func saveRegionName(index: Int) {
        viewModel.renameRegion(index, name: editingName)
        editingRegionIndex = nil
    }
}

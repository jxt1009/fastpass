import SwiftUI

struct CarPickerView: View {
    @Binding var selectedMake: String
    @Binding var selectedModel: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filteredMakes: [(make: String, models: [PerformanceCar])] {
        if searchText.isEmpty { return carsByMake }
        let q = searchText.lowercased()
        return carsByMake.compactMap { group in
            let filtered = group.models.filter {
                $0.make.lowercased().contains(q) || $0.model.lowercased().contains(q)
            }
            return filtered.isEmpty ? nil : (make: group.make, models: filtered)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredMakes, id: \.make) { group in
                    Section(header: Text(group.make).fontWeight(.semibold)) {
                        ForEach(group.models) { car in
                            Button {
                                selectedMake = car.make
                                selectedModel = car.model
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(car.model)
                                            .foregroundColor(.primary)
                                            .fontWeight(.medium)
                                        Text(car.category.rawValue)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedMake == car.make && selectedModel == car.model {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search make or model")
            .navigationTitle("Select Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

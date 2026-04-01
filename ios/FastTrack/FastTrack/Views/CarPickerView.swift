import SwiftUI

// MARK: - Car Selection State

struct CarSelection {
    var make: PerformanceMake?
    var model: String = ""
    var year: Int?
    var trim: String = ""

    var isComplete: Bool { make != nil && !model.isEmpty }

    var displayString: String {
        guard let make = make else { return "" }
        let parts: [String] = [
            year.map { String($0) } ?? "",
            make.displayName,
            model,
            trim
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}

// MARK: - Main Car Picker View

struct CarPickerView: View {
    @Binding var selection: CarSelection
    @Environment(\.dismiss) private var dismiss
    @StateObject private var carService = CarService.shared
    @State private var path = NavigationPath()
    @State private var searchText = ""

    var filteredMakes: [PerformanceMake] {
        if searchText.isEmpty { return performanceMakes }
        return performanceMakes.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(filteredMakes) { make in
                NavigationLink(value: make) {
                    HStack(spacing: 12) {
                        Text(make.displayName)
                            .fontWeight(.medium)
                        Spacer()
                        if selection.make?.displayName == make.displayName {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search makes")
            .navigationTitle("Select Make")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: PerformanceMake.self) { make in
                ModelPickerView(make: make, selection: $selection, path: $path)
            }
            .navigationDestination(for: ModelDestination.self) { dest in
                YearTrimPickerView(make: dest.make, model: dest.model, selection: $selection, dismissAll: { dismiss() })
            }
        }
    }
}

// MARK: - Navigation Destination Wrapper

struct ModelDestination: Hashable {
    let make: PerformanceMake
    let model: String
    func hash(into hasher: inout Hasher) { hasher.combine(make.displayName); hasher.combine(model) }
    static func == (l: ModelDestination, r: ModelDestination) -> Bool { l.make.displayName == r.make.displayName && l.model == r.model }
}

extension PerformanceMake {
    public func hash(into hasher: inout Hasher) { hasher.combine(nhtsa) }
    public static func == (l: PerformanceMake, r: PerformanceMake) -> Bool { l.nhtsa == r.nhtsa }
}

// MARK: - Model Picker

struct ModelPickerView: View {
    let make: PerformanceMake
    @Binding var selection: CarSelection
    @Binding var path: NavigationPath
    @StateObject private var carService = CarService.shared
    @State private var searchText = ""

    var filteredModels: [String] {
        if searchText.isEmpty { return carService.models }
        return carService.models.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if carService.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading \(make.displayName) models…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = carService.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundColor(.orange)
                    Text(err).foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await carService.fetchModels(for: make) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredModels, id: \.self) { model in
                    NavigationLink(value: ModelDestination(make: make, model: model)) {
                        HStack {
                            Text(model)
                            Spacer()
                            if selection.make?.displayName == make.displayName && selection.model == model {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search models")
            }
        }
        .navigationTitle(make.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await carService.fetchModels(for: make) }
    }
}

// MARK: - Year + Trim Picker

struct YearTrimPickerView: View {
    let make: PerformanceMake
    let model: String
    @Binding var selection: CarSelection
    let dismissAll: () -> Void

    private let years = Array(stride(from: 2025, through: 1990, by: -1))
    private var trims: [String]? { trimsFor(make: make.displayName, model: model) }

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedTrim: String = ""
    @State private var customTrim: String = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "car.fill").foregroundColor(.blue)
                    Text(make.displayName)
                        .fontWeight(.semibold)
                    Text(model)
                        .foregroundColor(.secondary)
                }
            }

            Section("Model Year") {
                Picker("Year", selection: $selectedYear) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
            }

            Section("Trim") {
                if let trims = trims {
                    Picker("Trim", selection: $selectedTrim) {
                        Text("Any / Unknown").tag("")
                        ForEach(trims, id: \.self) { trim in
                            Text(trim).tag(trim)
                        }
                        Text("Other…").tag("__custom__")
                    }
                    .pickerStyle(.inline)
                    if selectedTrim == "__custom__" {
                        TextField("Enter trim", text: $customTrim)
                            .autocorrectionDisabled()
                    }
                } else {
                    TextField("Trim level (optional)", text: $customTrim)
                        .autocorrectionDisabled()
                }
            }

            Section {
                Button("Confirm Selection") {
                    var finalTrim = selectedTrim == "__custom__" ? customTrim : selectedTrim
                    if trims == nil { finalTrim = customTrim }
                    selection = CarSelection(
                        make: make,
                        model: model,
                        year: selectedYear,
                        trim: finalTrim
                    )
                    dismissAll()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            }
        }
        .navigationTitle("Year & Trim")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedYear = selection.year ?? Calendar.current.component(.year, from: Date())
            if let existingTrim = Optional(selection.trim), !existingTrim.isEmpty {
                if let trims = trims, trims.contains(existingTrim) {
                    selectedTrim = existingTrim
                } else if !existingTrim.isEmpty {
                    selectedTrim = "__custom__"
                    customTrim = existingTrim
                }
            }
        }
    }
}

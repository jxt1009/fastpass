import SwiftUI

struct CarSelectorView: View {
    @ObservedObject private var profileManager = ProfileManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddCar = false
    
    var body: some View {
        NavigationStack {
            Group {
                if let profile = profileManager.profile, !profile.garage.isEmpty {
                    List(profile.garage) { car in
                        Button {
                            var updatedProfile = profile
                            updatedProfile.selectCar(id: car.id)
                            profileManager.saveProfile(updatedProfile)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(car.shortDisplay)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(car.displayString)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if profile.selectedCarId == car.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Cars in Garage",
                        systemImage: "car",
                        description: Text("Add a car to your garage to start tracking drives")
                    )
                }
            }
            .navigationTitle("Select Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddCar = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCar) {
                AddCarView()
            }
        }
    }
}

struct AddCarView: View {
    @ObservedObject private var profileManager = ProfileManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var carSelection = CarSelection()
    @State private var nickname = ""
    @State private var showingCarPicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Car Details") {
                    if carSelection.isComplete {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(carSelection.displayString)
                                .font(.headline)
                            Button("Change Car") {
                                showingCarPicker = true
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        }
                    } else {
                        Button("Select Car") {
                            showingCarPicker = true
                        }
                    }
                }
                
                Section("Nickname (Optional)") {
                    TextField("e.g., Daily Driver, Track Car", text: $nickname)
                }
            }
            .navigationTitle("Add Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCar()
                    }
                    .disabled(!carSelection.isComplete)
                }
            }
            .sheet(isPresented: $showingCarPicker) {
                CarPickerView(selection: $carSelection)
            }
        }
    }
    
    private func saveCar() {
        guard let make = carSelection.make,
              var profile = profileManager.profile else { return }
        
        let newCar = UserCar(
            make: make.displayName,
            model: carSelection.model,
            year: carSelection.year,
            trim: carSelection.trim,
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        profile.addCarToGarage(newCar)
        profileManager.saveProfile(profile)
        dismiss()
    }
}

#Preview {
    CarSelectorView()
}
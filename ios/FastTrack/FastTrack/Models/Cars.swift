import Foundation

enum CarCategory: String, CaseIterable, Codable {
    case hypercar = "Hypercar"
    case supercar = "Supercar"
    case sportsCar = "Sports Car"
    case muscleCar = "Muscle Car"
    case sportsSedan = "Sports Sedan"
    case electricPerformance = "Electric"
    case jdm = "JDM"
}

struct PerformanceCar: Identifiable, Hashable {
    let id = UUID()
    let make: String
    let model: String
    let category: CarCategory

    var displayName: String { "\(make) \(model)" }
}

let performanceCars: [PerformanceCar] = [
    // Ferrari
    PerformanceCar(make: "Ferrari", model: "296 GTB", category: .supercar),
    PerformanceCar(make: "Ferrari", model: "F8 Tributo", category: .supercar),
    PerformanceCar(make: "Ferrari", model: "SF90 Stradale", category: .hypercar),
    PerformanceCar(make: "Ferrari", model: "812 Superfast", category: .supercar),
    PerformanceCar(make: "Ferrari", model: "812 Competizione", category: .supercar),
    PerformanceCar(make: "Ferrari", model: "Purosangue", category: .supercar),
    PerformanceCar(make: "Ferrari", model: "Roma", category: .sportsCar),
    PerformanceCar(make: "Ferrari", model: "Portofino M", category: .sportsCar),
    PerformanceCar(make: "Ferrari", model: "LaFerrari", category: .hypercar),
    // Lamborghini
    PerformanceCar(make: "Lamborghini", model: "Huracán EVO", category: .supercar),
    PerformanceCar(make: "Lamborghini", model: "Huracán STO", category: .supercar),
    PerformanceCar(make: "Lamborghini", model: "Huracán Tecnica", category: .supercar),
    PerformanceCar(make: "Lamborghini", model: "Revuelto", category: .supercar),
    PerformanceCar(make: "Lamborghini", model: "Aventador SVJ", category: .supercar),
    PerformanceCar(make: "Lamborghini", model: "Urus Performante", category: .sportsCar),
    PerformanceCar(make: "Lamborghini", model: "Sterrato", category: .sportsCar),
    // McLaren
    PerformanceCar(make: "McLaren", model: "Artura", category: .supercar),
    PerformanceCar(make: "McLaren", model: "720S", category: .supercar),
    PerformanceCar(make: "McLaren", model: "765LT", category: .supercar),
    PerformanceCar(make: "McLaren", model: "GT", category: .sportsCar),
    PerformanceCar(make: "McLaren", model: "Senna", category: .hypercar),
    PerformanceCar(make: "McLaren", model: "P1", category: .hypercar),
    // Porsche
    PerformanceCar(make: "Porsche", model: "911 GT3", category: .supercar),
    PerformanceCar(make: "Porsche", model: "911 GT3 RS", category: .supercar),
    PerformanceCar(make: "Porsche", model: "911 Turbo S", category: .supercar),
    PerformanceCar(make: "Porsche", model: "911 GT2 RS", category: .supercar),
    PerformanceCar(make: "Porsche", model: "911 Carrera S", category: .sportsCar),
    PerformanceCar(make: "Porsche", model: "Cayman GT4", category: .sportsCar),
    PerformanceCar(make: "Porsche", model: "Cayman GT4 RS", category: .sportsCar),
    PerformanceCar(make: "Porsche", model: "Taycan Turbo S", category: .electricPerformance),
    PerformanceCar(make: "Porsche", model: "Cayenne Turbo GT", category: .sportsCar),
    // Bugatti
    PerformanceCar(make: "Bugatti", model: "Chiron", category: .hypercar),
    PerformanceCar(make: "Bugatti", model: "Chiron Super Sport", category: .hypercar),
    PerformanceCar(make: "Bugatti", model: "Tourbillon", category: .hypercar),
    // Koenigsegg
    PerformanceCar(make: "Koenigsegg", model: "Agera RS", category: .hypercar),
    PerformanceCar(make: "Koenigsegg", model: "Regera", category: .hypercar),
    PerformanceCar(make: "Koenigsegg", model: "Jesko", category: .hypercar),
    PerformanceCar(make: "Koenigsegg", model: "CC850", category: .hypercar),
    // Pagani
    PerformanceCar(make: "Pagani", model: "Huayra", category: .hypercar),
    PerformanceCar(make: "Pagani", model: "Huayra R", category: .hypercar),
    PerformanceCar(make: "Pagani", model: "Utopia", category: .hypercar),
    // Aston Martin
    PerformanceCar(make: "Aston Martin", model: "Vantage", category: .sportsCar),
    PerformanceCar(make: "Aston Martin", model: "DB11", category: .sportsCar),
    PerformanceCar(make: "Aston Martin", model: "DBS Superleggera", category: .supercar),
    PerformanceCar(make: "Aston Martin", model: "Valkyrie", category: .hypercar),
    PerformanceCar(make: "Aston Martin", model: "DB12", category: .sportsCar),
    PerformanceCar(make: "Aston Martin", model: "Vanquish", category: .supercar),
    // BMW
    PerformanceCar(make: "BMW", model: "M2", category: .sportsCar),
    PerformanceCar(make: "BMW", model: "M3 Competition", category: .sportsSedan),
    PerformanceCar(make: "BMW", model: "M4 Competition", category: .sportsCar),
    PerformanceCar(make: "BMW", model: "M4 CSL", category: .sportsCar),
    PerformanceCar(make: "BMW", model: "M5", category: .sportsSedan),
    PerformanceCar(make: "BMW", model: "M8 Competition", category: .supercar),
    PerformanceCar(make: "BMW", model: "Z4 M40i", category: .sportsCar),
    PerformanceCar(make: "BMW", model: "XM Label Red", category: .sportsCar),
    // Mercedes-AMG
    PerformanceCar(make: "Mercedes-AMG", model: "A45 S", category: .sportsSedan),
    PerformanceCar(make: "Mercedes-AMG", model: "C63 S E Performance", category: .sportsSedan),
    PerformanceCar(make: "Mercedes-AMG", model: "E63 S", category: .sportsSedan),
    PerformanceCar(make: "Mercedes-AMG", model: "GT R", category: .supercar),
    PerformanceCar(make: "Mercedes-AMG", model: "GT Black Series", category: .supercar),
    PerformanceCar(make: "Mercedes-AMG", model: "SL63", category: .sportsCar),
    PerformanceCar(make: "Mercedes-AMG", model: "G63", category: .sportsCar),
    PerformanceCar(make: "Mercedes-AMG", model: "One", category: .hypercar),
    // Audi
    PerformanceCar(make: "Audi", model: "RS3", category: .sportsSedan),
    PerformanceCar(make: "Audi", model: "RS4 Avant", category: .sportsSedan),
    PerformanceCar(make: "Audi", model: "RS5", category: .sportsSedan),
    PerformanceCar(make: "Audi", model: "RS6 Avant", category: .sportsSedan),
    PerformanceCar(make: "Audi", model: "RS7", category: .sportsSedan),
    PerformanceCar(make: "Audi", model: "R8 V10 Plus", category: .supercar),
    PerformanceCar(make: "Audi", model: "TT RS", category: .sportsCar),
    PerformanceCar(make: "Audi", model: "e-tron GT RS", category: .electricPerformance),
    // Alfa Romeo
    PerformanceCar(make: "Alfa Romeo", model: "Giulia Quadrifoglio", category: .sportsSedan),
    PerformanceCar(make: "Alfa Romeo", model: "Stelvio Quadrifoglio", category: .sportsCar),
    PerformanceCar(make: "Alfa Romeo", model: "4C Spider", category: .sportsCar),
    PerformanceCar(make: "Alfa Romeo", model: "33 Stradale", category: .supercar),
    // Bentley
    PerformanceCar(make: "Bentley", model: "Continental GT Speed", category: .sportsCar),
    PerformanceCar(make: "Bentley", model: "Flying Spur Speed", category: .sportsSedan),
    PerformanceCar(make: "Bentley", model: "Bacalar", category: .hypercar),
    // Dodge
    PerformanceCar(make: "Dodge", model: "Challenger SRT Hellcat", category: .muscleCar),
    PerformanceCar(make: "Dodge", model: "Challenger SRT Demon 170", category: .muscleCar),
    PerformanceCar(make: "Dodge", model: "Charger SRT Hellcat", category: .muscleCar),
    PerformanceCar(make: "Dodge", model: "Charger Daytona SRT", category: .electricPerformance),
    PerformanceCar(make: "Dodge", model: "Viper ACR", category: .supercar),
    // Chevrolet
    PerformanceCar(make: "Chevrolet", model: "Corvette Z06", category: .supercar),
    PerformanceCar(make: "Chevrolet", model: "Corvette C8 Stingray", category: .sportsCar),
    PerformanceCar(make: "Chevrolet", model: "Corvette ZR1", category: .supercar),
    PerformanceCar(make: "Chevrolet", model: "Corvette E-Ray", category: .electricPerformance),
    PerformanceCar(make: "Chevrolet", model: "Camaro ZL1", category: .muscleCar),
    PerformanceCar(make: "Chevrolet", model: "Camaro ZL1 1LE", category: .muscleCar),
    // Ford
    PerformanceCar(make: "Ford", model: "Mustang Shelby GT500", category: .muscleCar),
    PerformanceCar(make: "Ford", model: "Mustang Dark Horse", category: .muscleCar),
    PerformanceCar(make: "Ford", model: "Mustang Mach 1", category: .muscleCar),
    PerformanceCar(make: "Ford", model: "GT", category: .supercar),
    PerformanceCar(make: "Ford", model: "Focus RS", category: .sportsSedan),
    // Cadillac
    PerformanceCar(make: "Cadillac", model: "CT5-V Blackwing", category: .sportsSedan),
    PerformanceCar(make: "Cadillac", model: "CT4-V Blackwing", category: .sportsSedan),
    // Tesla
    PerformanceCar(make: "Tesla", model: "Model S Plaid", category: .electricPerformance),
    PerformanceCar(make: "Tesla", model: "Model 3 Performance", category: .electricPerformance),
    PerformanceCar(make: "Tesla", model: "Roadster", category: .electricPerformance),
    // Lucid
    PerformanceCar(make: "Lucid", model: "Air Sapphire", category: .electricPerformance),
    // Rimac
    PerformanceCar(make: "Rimac", model: "Nevera", category: .hypercar),
    // Nissan
    PerformanceCar(make: "Nissan", model: "GT-R Nismo", category: .supercar),
    PerformanceCar(make: "Nissan", model: "GT-R Premium", category: .supercar),
    PerformanceCar(make: "Nissan", model: "Z NISMO", category: .sportsCar),
    PerformanceCar(make: "Nissan", model: "Z Performance", category: .sportsCar),
    // Toyota
    PerformanceCar(make: "Toyota", model: "GR Supra", category: .jdm),
    PerformanceCar(make: "Toyota", model: "GR86", category: .jdm),
    PerformanceCar(make: "Toyota", model: "GR Corolla Morizo", category: .jdm),
    PerformanceCar(make: "Toyota", model: "GR Yaris", category: .jdm),
    // Honda / Acura
    PerformanceCar(make: "Acura", model: "NSX Type S", category: .supercar),
    PerformanceCar(make: "Honda", model: "Civic Type R", category: .jdm),
    PerformanceCar(make: "Acura", model: "Integra Type S", category: .jdm),
    // Subaru
    PerformanceCar(make: "Subaru", model: "WRX STI", category: .jdm),
    PerformanceCar(make: "Subaru", model: "WRX TR", category: .jdm),
    PerformanceCar(make: "Subaru", model: "BRZ tS", category: .jdm),
    // Mazda
    PerformanceCar(make: "Mazda", model: "MX-5 Miata", category: .sportsCar),
    PerformanceCar(make: "Mazda", model: "MX-5 RF", category: .sportsCar),
    // Rolls-Royce
    PerformanceCar(make: "Rolls-Royce", model: "Wraith Black Badge", category: .sportsCar),
    PerformanceCar(make: "Rolls-Royce", model: "Black Badge Ghost", category: .sportsSedan),
    // Maserati
    PerformanceCar(make: "Maserati", model: "MC20", category: .supercar),
    PerformanceCar(make: "Maserati", model: "MC20 Cielo", category: .supercar),
    PerformanceCar(make: "Maserati", model: "GranTurismo Trofeo", category: .sportsCar),
]

var carsByMake: [(make: String, models: [PerformanceCar])] {
    let grouped = Dictionary(grouping: performanceCars, by: \.make)
    return grouped
        .map { (make: $0.key, models: $0.value.sorted { $0.model < $1.model }) }
        .sorted { $0.make < $1.make }
}

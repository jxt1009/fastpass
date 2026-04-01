import Foundation

// MARK: - Curated Performance Makes
// These are the makes shown in the picker. Models come from NHTSA API.

struct PerformanceMake: Identifiable, Hashable {
    let id = UUID()
    let displayName: String   // shown in UI
    let nhtsa: String         // exact name to use in NHTSA API URL (URL-encoded internally)
    let emoji: String

    var urlEncoded: String {
        nhtsa.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nhtsa
    }
    
    public func hash(into hasher: inout Hasher) { hasher.combine(nhtsa) }
    public static func == (l: PerformanceMake, r: PerformanceMake) -> Bool { l.nhtsa == r.nhtsa }
}

let performanceMakes: [PerformanceMake] = [
    PerformanceMake(displayName: "Acura",          nhtsa: "Acura",          emoji: "🏎️"),
    PerformanceMake(displayName: "Alfa Romeo",      nhtsa: "Alfa Romeo",     emoji: "🏎️"),
    PerformanceMake(displayName: "Aston Martin",    nhtsa: "Aston Martin",   emoji: "🏎️"),
    PerformanceMake(displayName: "Audi",            nhtsa: "Audi",           emoji: "🏎️"),
    PerformanceMake(displayName: "Bentley",         nhtsa: "Bentley",        emoji: "🏎️"),
    PerformanceMake(displayName: "BMW",             nhtsa: "BMW",            emoji: "🏎️"),
    PerformanceMake(displayName: "Bugatti",         nhtsa: "Bugatti",        emoji: "🏎️"),
    PerformanceMake(displayName: "Cadillac",        nhtsa: "Cadillac",       emoji: "🏎️"),
    PerformanceMake(displayName: "Chevrolet",       nhtsa: "Chevrolet",      emoji: "🏎️"),
    PerformanceMake(displayName: "Dodge",           nhtsa: "Dodge",          emoji: "🏎️"),
    PerformanceMake(displayName: "Ferrari",         nhtsa: "Ferrari",        emoji: "🐎"),
    PerformanceMake(displayName: "Ford",            nhtsa: "Ford",           emoji: "🏎️"),
    PerformanceMake(displayName: "Honda",           nhtsa: "Honda",          emoji: "🏎️"),
    PerformanceMake(displayName: "Koenigsegg",      nhtsa: "Koenigsegg",     emoji: "🏎️"),
    PerformanceMake(displayName: "Lamborghini",     nhtsa: "Lamborghini",    emoji: "🐂"),
    PerformanceMake(displayName: "Lucid",           nhtsa: "Lucid",          emoji: "⚡"),
    PerformanceMake(displayName: "Maserati",        nhtsa: "Maserati",       emoji: "🏎️"),
    PerformanceMake(displayName: "Mazda",           nhtsa: "Mazda",          emoji: "🏎️"),
    PerformanceMake(displayName: "McLaren",         nhtsa: "McLaren",        emoji: "��️"),
    PerformanceMake(displayName: "Mercedes-Benz",   nhtsa: "Mercedes-Benz",  emoji: "🏎️"),
    PerformanceMake(displayName: "Nissan",          nhtsa: "Nissan",         emoji: "🏎️"),
    PerformanceMake(displayName: "Pagani",          nhtsa: "Pagani",         emoji: "🏎️"),
    PerformanceMake(displayName: "Porsche",         nhtsa: "Porsche",        emoji: "🏎️"),
    PerformanceMake(displayName: "Rimac",           nhtsa: "Rimac",          emoji: "⚡"),
    PerformanceMake(displayName: "Rolls-Royce",     nhtsa: "Rolls-Royce",    emoji: "🏎️"),
    PerformanceMake(displayName: "Subaru",          nhtsa: "Subaru",         emoji: "🏎️"),
    PerformanceMake(displayName: "Tesla",           nhtsa: "Tesla",          emoji: "⚡"),
    PerformanceMake(displayName: "Toyota",          nhtsa: "Toyota",         emoji: "🏎️"),
]

// MARK: - Static Trim Map
// For models where we know the trims, list them. Others get a free-text entry.
// Key format: "Make|Model" (lowercase)

let knownTrims: [String: [String]] = [
    // Porsche 911
    "porsche|911": ["Carrera", "Carrera S", "Carrera 4", "Carrera 4S", "Targa 4", "Targa 4S",
                     "Turbo", "Turbo S", "GT3", "GT3 RS", "GT3 Touring", "GT2 RS",
                     "Dakar", "Sport Classic", "S/T"],
    "porsche|cayman": ["Base", "S", "GTS", "GT4", "GT4 RS"],
    "porsche|718 cayman": ["Base", "S", "GTS 4.0", "GT4", "GT4 RS"],
    "porsche|boxster": ["Base", "S", "GTS", "Spyder"],
    "porsche|718 boxster": ["Base", "S", "GTS 4.0", "Spyder"],
    "porsche|taycan": ["Base", "4S", "GTS", "Turbo", "Turbo S", "Cross Turismo Turbo S"],
    "porsche|panamera": ["Base", "4S", "GTS", "Turbo", "Turbo S E-Hybrid", "Sport Turismo"],
    // Ferrari
    "ferrari|296": ["GTB", "GTS", "GT3", "GT3 Evo"],
    "ferrari|sf90": ["Stradale", "Spider", "XX"],
    "ferrari|812": ["Superfast", "GTS", "Competizione", "Competizione A"],
    "ferrari|f8": ["Tributo", "Spider"],
    "ferrari|roma": ["Base", "Spider"],
    "ferrari|portofino": ["Base", "M"],
    "ferrari|purosangue": ["Base"],
    // Lamborghini
    "lamborghini|huracan": ["EVO", "EVO RWD", "EVO Spyder", "EVO RWD Spyder",
                             "STO", "Tecnica", "Sterrato", "Super Trofeo EVO2"],
    "lamborghini|aventador": ["S", "S Roadster", "SVJ", "SVJ Roadster", "LP 780-4 Ultimae"],
    "lamborghini|revuelto": ["Base", "Opera Unica"],
    "lamborghini|urus": ["Base", "S", "Performante"],
    // McLaren
    "mclaren|artura": ["Base", "Spider", "Trophy"],
    "mclaren|720s": ["Base", "Performance", "Spider"],
    "mclaren|765lt": ["Base", "Spider"],
    "mclaren|gt": ["Base"],
    "mclaren|senna": ["Base", "GTR"],
    "mclaren|765": ["LT", "LT Spider"],
    // BMW
    "bmw|m2": ["Base", "Competition", "CS"],
    "bmw|m3": ["Base", "Competition", "Competition xDrive", "CS", "Touring"],
    "bmw|m4": ["Base", "Competition", "Competition xDrive", "CSL", "GTS"],
    "bmw|m5": ["Base", "Competition", "CS", "Touring"],
    "bmw|m8": ["Base", "Competition", "Gran Coupe Competition", "CSL"],
    "bmw|z4": ["sDrive20i", "sDrive30i", "M40i"],
    // Mercedes-Benz
    "mercedes-benz|amg gt": ["GT", "GT S", "GT R", "GT Black Series", "GT 63", "GT 63 S"],
    "mercedes-benz|c-class": ["C 300", "AMG C 43", "AMG C 63", "AMG C 63 S E Performance"],
    "mercedes-benz|e-class": ["E 350", "E 450", "AMG E 53", "AMG E 63 S"],
    "mercedes-benz|sl-class": ["SL 43", "AMG SL 55", "AMG SL 63"],
    // Audi
    "audi|r8": ["V10", "V10 RWD", "V10 Plus", "V10 Performance"],
    "audi|rs3": ["Base", "Sportback"],
    "audi|rs5": ["Base", "Sportback"],
    "audi|rs6": ["Avant"],
    "audi|rs7": ["Base"],
    "audi|tt": ["TTS", "TT RS"],
    "audi|e-tron gt": ["Base", "RS"],
    // Dodge
    "dodge|challenger": ["R/T", "R/T Scat Pack", "SRT 392", "SRT Hellcat",
                          "SRT Hellcat Widebody", "SRT Hellcat Redeye",
                          "SRT Hellcat Redeye Jailbreak", "SRT Demon 170"],
    "dodge|charger": ["R/T", "Scat Pack", "SRT 392", "SRT Hellcat",
                       "SRT Hellcat Widebody", "SRT Hellcat Redeye", "SRT Hellcat Jailbreak"],
    "dodge|viper": ["Base", "GTS", "ACR", "ACR Extreme"],
    // Chevrolet
    "chevrolet|corvette": ["Stingray", "Stingray Z51", "Grand Sport", "Z06", "Z06 Z07",
                            "ZR1", "E-Ray", "70th Anniversary"],
    "chevrolet|camaro": ["LT1", "SS", "SS 1LE", "ZL1", "ZL1 1LE", "COPO"],
    // Ford
    "ford|mustang": ["EcoBoost", "EcoBoost Premium", "GT", "GT Premium",
                      "Mach 1", "Shelby GT500", "Dark Horse", "Dark Horse Premium",
                      "GTD", "Bullitt"],
    "ford|gt": ["Base"],
    // Nissan
    "nissan|gt-r": ["Premium", "Track Edition", "Nismo", "50th Anniversary"],
    "nissan|z": ["Sport", "Performance", "Proto Spec", "NISMO"],
    // Tesla
    "tesla|model s": ["Long Range", "Plaid"],
    "tesla|model 3": ["RWD", "Long Range AWD", "Performance"],
    "tesla|model x": ["Long Range", "Plaid"],
    "tesla|roadster": ["Base", "Founders Series"],
    // Toyota
    "toyota|gr supra": ["2.0", "3.0", "3.0 Premium", "A91-MT", "A91-CF"],
    "toyota|gr86": ["Base", "Premium"],
    "toyota|gr corolla": ["Core", "Circuit Edition", "Morizo Edition"],
    "toyota|gr yaris": ["Base", "Rally"],
    // Subaru
    "subaru|wrx": ["Base", "Premium", "Limited", "GT", "TR", "STI"],
    "subaru|brz": ["Premium", "Limited", "tS"],
    // Alfa Romeo
    "alfa romeo|giulia": ["Base", "Sprint", "Ti", "Veloce", "Quadrifoglio"],
    "alfa romeo|stelvio": ["Base", "Sprint", "Ti", "Veloce", "Quadrifoglio"],
    "alfa romeo|4c": ["Base", "Spider"],
    // Maserati
    "maserati|mc20": ["Base", "Cielo", "Folgore"],
    "maserati|granturismo": ["Modena", "Trofeo", "Folgore"],
    "maserati|ghibli": ["Base", "S Q4", "Trofeo"],
    "maserati|quattroporte": ["Base", "S Q4", "Trofeo"],
    // Acura
    "acura|nsx": ["Base", "Type S"],
    "acura|integra": ["Base", "A-Spec", "Type S"],
    "acura|tlx": ["Base", "Type S", "Type S PMC Edition"],
    // Honda
    "honda|civic": ["Sport", "EX", "Touring", "Type R", "Type R Limited Edition"],
    "honda|accord": ["Sport", "EX-L", "Touring", "Hybrid Sport"],
    // Koenigsegg
    "koenigsegg|agera": ["Base", "R", "RS", "Final"],
    "koenigsegg|regera": ["Base"],
    "koenigsegg|jesko": ["Base", "Absolut"],
    "koenigsegg|cc850": ["Base"],
    // Pagani
    "pagani|huayra": ["Base", "BC", "Roadster", "Roadster BC", "R", "Tricolore"],
    "pagani|utopia": ["Base", "Roadster"],
    // Bugatti
    "bugatti|chiron": ["Base", "Sport", "Super Sport", "Super Sport 300+",
                        "Pur Sport", "Profilee"],
    "bugatti|tourbillon": ["Base"],
    // Rimac
    "rimac|nevera": ["Base", "Time Attack"],
    // Lucid
    "lucid|air": ["Pure", "Touring", "Grand Touring", "Grand Touring Performance", "Sapphire"],
    // Rolls-Royce
    "rolls-royce|ghost": ["Base", "Extended", "Black Badge", "Series II"],
    "rolls-royce|wraith": ["Base", "Black Badge"],
    "rolls-royce|dawn": ["Base", "Black Badge"],
    "rolls-royce|spectre": ["Base"],
    "rolls-royce|cullinan": ["Base", "Black Badge"],
    // Bentley
    "bentley|continental gt": ["Base", "V8", "Speed", "Mulliner", "Azure", "GT3-R"],
    "bentley|flying spur": ["Base", "V8", "Speed", "Mulliner"],
    "bentley|bentayga": ["Base", "V8", "Speed", "EWB", "Azure"],
]

func trimsFor(make: String, model: String) -> [String]? {
    let key = "\(make.lowercased())|\(model.lowercased())"
    return knownTrims[key]
}

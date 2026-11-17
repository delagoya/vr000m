import Foundation

enum SoundProfile: Int, CaseIterable, Identifiable {
    case jetson   // default: futuristic warbling hover-car
    case v8       // combustion rumble
    case electric // clean EV whine

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .jetson:   return "Space Car"
        case .v8:       return "V8"
        case .electric: return "Electric"
        }
    }

    var symbol: String {
        switch self {
        case .jetson:   return "sparkles"
        case .v8:       return "flame"
        case .electric: return "bolt"
        }
    }
}

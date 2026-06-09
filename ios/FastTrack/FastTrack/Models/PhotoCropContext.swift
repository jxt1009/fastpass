import CoreGraphics

enum PhotoCropContext {
    case avatar
    case car

    var navigationTitle: String {
        switch self {
        case .avatar:
            return "Adjust Avatar"
        case .car:
            return "Adjust Photo"
        }
    }

    var aspectRatio: CGFloat { 1 }

    var locksAspectRatio: Bool { true }
}

import SwiftUI

// MARK: - CarPhotoView
//
// Renders a car photo from a URL, with a gradient+initials placeholder.
// Use for any car hero, card, or thumbnail where the gradient+initials
// placeholder is appropriate (GarageCarCard, CarDetailView,
// PublicCarDetailView). All AsyncImage loading/success/failure/unknown
// phases show the same placeholder when no usable image is available.
//
// The placeholder is always:
//   LinearGradient(.ftBlue.opacity(0.6) → .purple.opacity(0.5))
//   with initials text (make + model first letters) centered.
//
// `cornerRadius` is intentionally left to the caller so the component
// works equally well as a full-bleed hero (cornerRadius 0, clipped by
// the parent) and as a rounded card thumbnail.

struct CarPhotoView: View {
    /// Source car — used to derive the placeholder initials.
    let car: UserCar
    /// Remote photo URL. `nil` always shows the placeholder.
    let url: URL?
    /// Corner radius applied to the image frame. Caller controls shape.
    var cornerRadius: CGFloat
    /// When `false` the placeholder renders the gradient without text.
    var showInitials: Bool = true

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.ftBlue.opacity(0.6), .purple.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if showInitials {
                Text(initials(for: car))
                    .font(FTFont.iconXLarge).minimumScaleFactor(0.6)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
}

// MARK: - Initials helper

private func initials(for car: UserCar) -> String {
    let first = car.make.first.map(String.init) ?? ""
    let second = car.model.first.map(String.init) ?? ""
    let combined = (first + second).uppercased()
    return combined.isEmpty ? "?" : combined
}

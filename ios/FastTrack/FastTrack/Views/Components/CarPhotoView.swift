import SwiftUI

// MARK: - CarPhotoView
//
// Renders a car photo from a URL with a placeholder fallback.
//
// Two modes, selected by the `size` argument:
//   - Hero (size == nil): full-bleed card that fills its parent's frame.
//     Placeholder is a LinearGradient(ftBlue→purple) with the car's
//     make+model initials centered. Used by GarageCarCard, CarDetailView,
//     PublicCarDetailView, and any place where the car takes visual
//     prominence. The `showInitials` toggle turns the initials text on
//     or off (off in the editor preview). The caller owns the frame,
//     corner radius, and border.
//   - Thumbnail (size != nil): a fixed `size x size` rounded square
//     with a 0.5pt secondary border. Placeholder is a tinted
//     `car.fill` SF Symbol on a translucent `ftBlue` background. Used
//     by leaderboard rows, the private garage cards, and the public
//     garage card. No initials, no gradient.
//
// In both modes, the AsyncImage phase handling routes empty/failure/
// unknown back to the same placeholder, so a missing photo always
// shows the appropriate fallback.

struct CarPhotoView: View {
    /// Source car — used to derive the hero placeholder initials.
    let car: UserCar
    /// Remote photo URL. `nil` always shows the placeholder.
    let url: URL?
    /// Corner radius applied to the image frame. Caller controls shape.
    var cornerRadius: CGFloat
    /// When `false` the hero placeholder renders the gradient without
    /// text. Ignored in thumbnail mode.
    var showInitials: Bool = true
    /// When set, renders a fixed-size thumbnail with a car-icon
    /// placeholder (no initials, no gradient). When `nil`, preserves
    /// the hero gradient+initials behavior.
    var size: CGFloat? = nil

    var body: some View {
        if let size {
            thumbnailBody(size: size)
        } else {
            heroBody
        }
    }

    // MARK: - Hero mode (size == nil)

    @ViewBuilder
    private var heroBody: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    heroPlaceholder
                @unknown default:
                    heroPlaceholder
                }
            }
        } else {
            heroPlaceholder
        }
    }

    private var heroPlaceholder: some View {
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

    // MARK: - Thumbnail mode (size != nil)

    @ViewBuilder
    private func thumbnailBody(size: CGFloat) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure:
                        thumbnailPlaceholder(size: size)
                    @unknown default:
                        thumbnailPlaceholder(size: size)
                    }
                }
            } else {
                thumbnailPlaceholder(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func thumbnailPlaceholder(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.ftBlue.opacity(0.15))
            Image(systemName: "car.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(Color.ftBlue)
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

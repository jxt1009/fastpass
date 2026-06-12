import SwiftUI

// MARK: - DriveDetailAttemptsList

struct DriveDetailAttemptsList: View {
    let zeroToSixtyAttempts: [ZeroToSixtyAttemptDisplay]

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.ftAmber)
                .frame(width: 18, height: 4)
            Text("0-60 attempts")
                .font(.caption)
                .foregroundColor(.secondary)
            if zeroToSixtyAttempts.contains(where: { $0.isPersonalBest }) {
                Capsule()
                    .fill(Color.ftGold)
                    .frame(width: 18, height: 4)
                Text("personal best")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(zeroToSixtyAttempts.count) capture\(zeroToSixtyAttempts.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

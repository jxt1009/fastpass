import SwiftUI

// MARK: - DriveDetailActions

struct DriveDetailActions: View {
    let isOwner: Bool
    let isDeleting: Bool
    let onDelete: () -> Void

    var body: some View {
        if isOwner {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(isDeleting)
        }
    }
}

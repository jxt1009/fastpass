import SwiftUI

// MARK: - CarDetailPhotoEditor

struct CarDetailPhotoEditor: View {
    let carId: String
    let existingPhotoURL: String?
    let onUploadComplete: (URL) -> Void
    @Binding var isPresented: Bool

    var body: some View {
        CarHeroPhotoEditorSheet(
            carId: carId,
            existingPhotoURL: existingPhotoURL,
            onUploadComplete: onUploadComplete
        )
    }
}

import SwiftUI

/// Reusable follow/unfollow button. When `isFollowing` is `true`, the
/// button is filled with `Color(.systemFill)` and reads "Following".
/// When `false`, it's filled with `Color.ftBlue` and reads "Follow".
/// While an API call is in flight, a ProgressView is shown.
///
/// On error, calls `onError(message)` so the caller can surface a
/// toast. The internal `isFollowing` state is only updated on success
/// (the caller's bound state remains untouched on failure).
struct FollowButton: View {
    @Binding var isFollowing: Bool
    @State private var isLoading = false
    /// Username passed to the API. Required.
    let username: String
    /// Whether the current user is themselves; if so, the button is hidden.
    let isSelf: Bool
    /// Width of the button.
    var width: CGFloat = 80
    /// Height of the button.
    var height: CGFloat = 28
    /// Called on API failure with a user-presentable message.
    var onError: (String) -> Void = { _ in }

    @EnvironmentObject var apiService: APIService

    var body: some View {
        if isSelf {
            EmptyView()
        } else {
            Button {
                Task { await toggle() }
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(width: width, height: height)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isFollowing ? .secondary : .white)
                        .frame(width: width, height: height)
                        .background(
                            Capsule().fill(isFollowing ? Color(.systemFill) : Color.ftBlue)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }

    private func toggle() async {
        isLoading = true
        let previous = isFollowing
        do {
            if isFollowing {
                try await apiService.unfollowUser(username: username)
                isFollowing = false
            } else {
                try await apiService.followUser(username: username)
                isFollowing = true
            }
        } catch {
            onError("Couldn't \(previous ? "unfollow" : "follow") @\(username). Try again.")
        }
        isLoading = false
    }
}

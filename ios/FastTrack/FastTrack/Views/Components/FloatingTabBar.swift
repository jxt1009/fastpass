import SwiftUI

enum AppTab: Int, CaseIterable {
    case track, garage, social, profile

    var icon: String {
        switch self {
        case .track:   return "speedometer"
        case .garage:  return "car.2.fill"
        case .social:  return "trophy.fill"
        case .profile: return "person.fill"
        }
    }

    var label: String {
        switch self {
        case .track:   return "Track"
        case .garage:  return "Garage"
        case .social:  return "Social"
        case .profile: return "Profile"
        }
    }

    var accentColor: Color {
        switch self {
        case .track:   return .ftBlue
        case .garage:  return .ftAmber
        case .social:  return .ftGold
        case .profile: return .ftGreen
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    var isHidden: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    if selectedTab == tab {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(tab.label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(tab.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(tab.accentColor.opacity(0.20))
                        .clipShape(Capsule())
                    } else {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.50))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(
            Capsule()
                .stroke(Color.ftGlassCardStroke, lineWidth: 1)
        )
        .clipShape(Capsule())
        .offset(y: isHidden ? 100 : 0)
        .opacity(isHidden ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: isHidden)
    }
}

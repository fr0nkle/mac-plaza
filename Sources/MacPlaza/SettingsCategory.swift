import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case sound, apps, display, motion, friends, appearance, data, updates, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sound: "Music & Sound"
        case .apps: "Home Screen"
        case .display: "Screen & Startup"
        case .motion: "Miis & Motion"
        case .friends: "Friends"
        case .appearance: "Mii Appearance"
        case .data: "Data Management"
        case .updates: "System Update"
        case .system: "System & Recovery"
        }
    }
    var symbol: String {
        switch self {
        case .sound: "speaker.wave.3.fill"
        case .apps: "square.grid.2x2.fill"
        case .display: "desktopcomputer"
        case .motion: "figure.walk"
        case .friends: "person.2.fill"
        case .appearance: "person.crop.square.fill"
        case .data: "externaldrive.fill"
        case .updates: "arrow.down.circle.fill"
        case .system: "wrench.and.screwdriver.fill"
        }
    }
    var subtitle: String {
        switch self {
        case .sound: "Choose soundtracks, preview music and adjust volume."
        case .apps: "Arrange your apps and add Steam games."
        case .display: "Use the plaza as wallpaper and choose how it starts."
        case .motion: "Adjust your crowd, movement and speech bubbles."
        case .friends: "Manage your Discord connection and plaza friends."
        case .appearance: "Choose your Mii face, body and animation resources."
        case .data: "Export your plaza, import a saved plaza or restore a backup."
        case .updates: "Keep Mac Plaza up to date."
        case .system: "View app information and recovery options."
        }
    }
    var color: Color {
        switch self {
        case .sound: Color(red: 0.94, green: 0.52, blue: 0.13)
        case .apps: Color(red: 0.18, green: 0.62, blue: 0.83)
        case .display: Color(red: 0.23, green: 0.62, blue: 0.64)
        case .motion: Color(red: 0.43, green: 0.66, blue: 0.21)
        case .friends: Color(red: 0.92, green: 0.56, blue: 0.22)
        case .appearance: Color(red: 0.78, green: 0.43, blue: 0.57)
        case .data: Color(red: 0.34, green: 0.55, blue: 0.76)
        case .updates: Color(red: 0.83, green: 0.59, blue: 0.19)
        case .system: Color(red: 0.51, green: 0.57, blue: 0.61)
        }
    }
}

struct SettingsCategoryTile: View {
    let category: SettingsCategory
    let height: CGFloat
    let select: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: select) {
            VStack(spacing: height < 110 ? 8 : 14) {
                Image(systemName: category.symbol).symbolRenderingMode(.hierarchical)
                    .font(.system(size: height < 110 ? 28 : height < 130 ? 36 : 48, weight: .medium))
                    .foregroundStyle(category.color)
                    .frame(height: height < 110 ? 32 : height < 130 ? 40 : 56)
                    .shadow(color: category.color.opacity(0.18), radius: 2, y: 2)
                Text(category.title).font(.system(size: height < 110 ? 13 : 15, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: height)
            .background(LinearGradient(colors: [.white, Color(red: 0.96, green: 0.97, blue: 0.98)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(hovered || focused ? Color.orange.opacity(0.85) : .white, lineWidth: 3))
            .shadow(color: .black.opacity(hovered || focused ? 0.12 : 0.06), radius: 5, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 19))
        }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }
            .accessibilityLabel("\(category.title) settings").help(category.subtitle)
    }
}

struct SettingsBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(red: 0.96, green: 0.97, blue: 0.98), Color(red: 0.88, green: 0.91, blue: 0.92)], startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    for y in stride(from: CGFloat(0), to: size.height, by: 22) {
                        for x in stride(from: CGFloat(0), to: size.width, by: 22) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.75)))
                        }
                    }
                }
                Ellipse().fill(.white.opacity(0.40)).frame(width: proxy.size.width * 1.7, height: proxy.size.height * 0.75)
                    .rotationEffect(.degrees(-12)).position(x: proxy.size.width * 0.8, y: proxy.size.height * 0.85)
            }.clipped()
        }.accessibilityHidden(true)
    }
}

import SwiftUI

/// One native hit surface keeps these controls clickable above either renderer,
/// in the ordinary window and on the wallpaper.
struct PlazaHomeControls: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject private var updater = PlazaUpdater.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                control(model.editing ? "Back to Plaza" : model.rotatingHomeEnabled ? "Edit Pins" : "Change Apps",
                        icon: model.editing ? "checkmark" : "square.grid.2x2", width: 104) {
                    if model.editing { model.editing = false }
                    else { model.beginChangingApps() }
                }.help(model.editing ? "Finish changing apps and return to the plaza. Changes are saved automatically." : "Add, replace, remove and arrange home screen apps")
                control("Friends", icon: "person.2.fill", width: 78) {
                    model.sheet = .friends
                }.help("View friends, their status and assigned Miis")
                control("Settings", icon: "gearshape", width: 78) {
                    model.sheet = .preferences
                }.modifier(PlazaUpdateIndicator(available: updater.updateAvailable, label: "Settings"))
                control("Mii Maker", icon: "person.crop.square", width: 78) {
                    model.sheet = .characters
                }.help("Open Mii Maker to create and edit your Miis")
            }
            if model.editing {
                HStack(spacing: 16) {
                    PlazaButton { model.pickApp() } label: { Label("Add App", systemImage: "plus") }
                    PlazaButton { model.pickSteamGame() } label: { Label("Add Steam Game", systemImage: "gamecontroller") }
                    Spacer(minLength: 0)
                    PlazaButton { model.undoLayout() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .buttonStyle(.plain).padding(.horizontal, 16).frame(height: 42)
                .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
            }
        }.foregroundStyle(PlazaStyle.teal)
    }

    private func control(_ title: String, icon: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        PlazaButton(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 24))
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
            }.frame(width: width, height: 70).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(.white, lineWidth: 2).allowsHitTesting(false))
            .shadow(color: PlazaStyle.ink.opacity(0.09), radius: 8, y: 3)
    }
}

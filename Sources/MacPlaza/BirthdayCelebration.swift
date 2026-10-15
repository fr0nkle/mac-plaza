import AppKit
import SwiftUI
import PlazaCore

/// Local receipt contains only the last celebrated year, never a birthday or
/// profile copy. It is deliberately excluded from shareable plaza documents.
final class BirthdayCelebrationReceipt {
    let url: URL
    private(set) var year: Int?
    init(url: URL) {
        self.url = url
        year = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Int.self, from: $0) }
    }
    func claim(avatar: Avatar, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let currentYear = parts.year, year != currentYear,
              avatar.features.birthMonth > 0, avatar.features.birthDay > 0,
              parts.month == avatar.features.birthMonth, parts.day == avatar.features.birthDay else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(currentYear).write(to: url, options: .atomic)
            year = currentYear
            return true
        } catch { return false }
    }
}

@MainActor
final class BirthdayCelebrationController {
    private(set) var panel: NSPanel?
    private var finishTask: Task<Void, Never>?
    func show(name: String, screen: NSScreen, reducedMotion: Bool) {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .fullScreenNone, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: BirthdayCelebrationTimeline(name: name, reducedMotion: reducedMotion))
        self.panel = panel
        panel.orderFrontRegardless()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(reducedMotion ? 3 : 6))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
    func dismiss() {
        finishTask?.cancel(); finishTask = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
    }
}

private struct BirthdayCelebrationTimeline: View {
    let name: String
    let reducedMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var started = Date()
    var body: some View {
        let still = reducedMotion || systemReduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            BirthdayCelebrationView(name: name, reducedMotion: still, elapsed: context.date.timeIntervalSince(started))
        }
    }
}

struct BirthdayCelebrationView: View {
    let name: String
    let reducedMotion: Bool
    let elapsed: TimeInterval
    var body: some View {
        ZStack(alignment: .top) {
            if !reducedMotion {
                Canvas { context, size in
                    let colors: [Color] = [.yellow, .orange, .yellow, .mint, .yellow, .white]
                    for index in 0..<96 {
                        let seed = Double(index)
                        let delay = Double(index % 12) * 0.065
                        let age = max(0, elapsed - delay)
                        let life = min(1, age / 4.7)
                        let x = size.width * (Double((index * 37) % 101) / 100) + sin(seed * 2.7 + age) * 28
                        let y = -18 + size.height * (age / 5.4) + Double(index % 7) * 25
                        let radius = 2.5 + Double(index % 4)
                        let alpha = min(1, age * 2) * max(0, 1 - life) * 0.85
                        var particle = Path()
                        if index % 3 == 0 {
                            particle.move(to: CGPoint(x: x, y: y - radius * 1.7))
                            particle.addLine(to: CGPoint(x: x + radius * 0.4, y: y - radius * 0.4))
                            particle.addLine(to: CGPoint(x: x + radius * 1.7, y: y))
                            particle.addLine(to: CGPoint(x: x + radius * 0.4, y: y + radius * 0.4))
                            particle.addLine(to: CGPoint(x: x, y: y + radius * 1.7))
                            particle.addLine(to: CGPoint(x: x - radius * 0.4, y: y + radius * 0.4))
                            particle.addLine(to: CGPoint(x: x - radius * 1.7, y: y))
                            particle.addLine(to: CGPoint(x: x - radius * 0.4, y: y - radius * 0.4)); particle.closeSubpath()
                        } else { particle.addEllipse(in: CGRect(x: x, y: y, width: radius, height: radius * 1.5)) }
                        context.fill(particle, with: .color(colors[index % colors.count].opacity(alpha)))
                    }
                }.accessibilityHidden(true)
            }
            HStack(spacing: 14) {
                Image(systemName: "birthday.cake.fill").font(.system(size: 30)).foregroundStyle(Color(red: 0.73, green: 0.43, blue: 0.11))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Happy birthday, \(name)!").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("A little sparkle for your special day.").font(.system(size: 13))
                }
            }.foregroundStyle(PlazaStyle.ink).padding(.horizontal, 25).padding(.vertical, 19)
                .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.yellow.opacity(0.65), lineWidth: 2))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4).padding(.top, 68)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(reducedMotion ? 1 : min(1, max(0, elapsed * 2)) * min(1, max(0, (6 - elapsed) / 1.2)))
            .allowsHitTesting(false).preferredColorScheme(.light)
    }
}

extension PlazaModel {
    func checkBirthday(now: Date = Date()) {
        guard loaded, !demo, !recoveryRequired, !document.preferences.safeMode,
              sessionActive, renderVisible, sheet == nil, previewAppID == nil,
              !otherAppFullScreen, !otherAppCoversPlaza,
              let screen = wallpaperEnabled ? DesktopPlazaController.targetScreen : window?.screen,
              birthdayCelebration.panel == nil else { return }
        guard birthdayReceipt.claim(avatar: document.primaryAvatar, now: now) else { return }
        birthdayCelebration.show(name: document.primaryAvatar.name, screen: screen,
            reducedMotion: document.preferences.pauseMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

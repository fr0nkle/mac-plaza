import AppKit
import SwiftUI
import PlazaCore

enum FriendNotePlanner {
    static func positions(anchors: [CGPoint], size: CGSize, card: CGSize,
                          obstacles: [CGRect], limit: Int = 2) -> [(Int, CGRect)] {
        guard limit > 0, card.width > 0, card.height > 0,
              size.width > card.width + 24, size.height > card.height + 24 else { return [] }
        var reserved = obstacles, result: [(Int, CGRect)] = []
        for (index, point) in anchors.enumerated() {
            guard point.x.isFinite, point.y.isFinite, point.x >= 12, point.x <= size.width - 12,
                  point.y >= 12, point.y <= size.height - 12 else { continue }
            var options: [CGRect] = []
            let rises: [CGFloat] = [8, 24, 40]
            let shifts: [CGFloat] = [0, -0.2, 0.2, -0.4, 0.4]
            for rise in rises {
                for shift in shifts {
                    let x = min(size.width - card.width - 12, max(12, point.x - card.width/2 + shift * card.width))
                    options.append(CGRect(x: x, y: point.y - card.height - rise, width: card.width, height: card.height))
                }
            }
            guard let rect = options.first(where: { rect in
                // Keep the pointer over its speaker; never put a panel below
                // them or across the plaza just to find an empty rectangle.
                rect.minY >= 12 && rect.maxY < point.y && rect.maxY < size.height - 30 &&
                point.x >= rect.minX + 27 && point.x <= rect.maxX - 27 &&
                !reserved.contains(where: { $0.intersects(rect.insetBy(dx: -6, dy: -6)) })
            }) else { continue }
            result.append((index, rect)); reserved.append(rect)
            if result.count == limit { break }
        }
        return result
    }
}

struct FriendNotesLayer: NSViewRepresentable {
    let scene: PlazaScene
    @ObservedObject var social: SocialController
    @ObservedObject private var resource = FFLResources.shared
    @ObservedObject private var bodyResource = PlazaBodyResources.shared
    var paused: Bool
    var showPosts = true
    var onHoldChanged: (Bool) -> Void = { _ in }
    var journalPosts: [PlazaSpeechPost] = []
    var maxPosts = 1
    var onSelectJournal: (UUID?) -> Void = { _ in }
    var largerText: Bool
    var islands: [CGPoint]
    var reserved: [CGRect]
    var onSelect: (SharedMii) -> Void
    func makeNSView(context: Context) -> FriendNotesView { FriendNotesView() }
    func updateNSView(_ view: FriendNotesView, context: Context) {
        view.configure(scene: scene, friends: social.friends, paused: paused,
                       largerText: largerText, islands: islands, reserved: reserved,
                       showPosts: showPosts, onHoldChanged: onHoldChanged,
                       journalPosts: journalPosts, maxPosts: maxPosts, onSelectJournal: onSelectJournal, onSelect: onSelect)
    }
    static func dismantleNSView(_ view: FriendNotesView, coordinator: ()) { view.stop() }
}

final class FriendNotesView: NSView {
    private let owner = UUID()
    private weak var scene: PlazaScene?
    private var friends: [SharedMii] = []
    private var friendPostVariations: [String: Int] = [:]
    private var selectedVariations: [String: Int] = [:]
    private var variationRotation: Int?
    private var candidates: [PlazaSpeechPost] = []
    private var journalPosts: [PlazaSpeechPost] = []
    private var activePostIDs = Set<String>()
    private var maxPosts = 1
    private var positions: [UUID: CGPoint] = [:]
    private var buttons: [FriendNoteButton] = []
    private var rotation = 0
    private var showPosts = false
    private var largerText = false
    private var islands: [CGPoint] = []
    private var reserved: [CGRect] = []
    private var selected: ((SharedMii) -> Void)?
    private var selectedJournal: (UUID?) -> Void = { _ in }
    private var holdChanged: (Bool) -> Void = { _ in }
    var visibleCardCount: Int { buttons.filter { !$0.isHidden }.count }
    var visiblePosts: [(id: String, speakerID: UUID, frame: CGRect, head: CGPoint, pointerX: CGFloat)] {
        buttons.compactMap { button in
            guard !button.isHidden, let post = button.post, let head = positions[post.speaker.id] else { return nil }
            return (post.id, post.speaker.id, button.frame, head, button.frame.minX + button.tailX)
        }
    }
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setAccessibilityElement(false) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
    func configure(scene: PlazaScene, friends: [SharedMii], paused: Bool, largerText: Bool,
                   islands: [CGPoint], reserved: [CGRect], showPosts: Bool = true,
                   onHoldChanged: @escaping (Bool) -> Void = { _ in },
                   journalPost: PlazaSpeechPost? = nil, journalPosts: [PlazaSpeechPost] = [], maxPosts: Int = 1, onSelectJournal: @escaping (UUID?) -> Void = { _ in },
                   onSelect: @escaping (SharedMii) -> Void) {
        self.scene = scene; self.friends = friends.filter { !$0.overheadText.isEmpty }
        let posts = journalPost.map { [$0] } ?? journalPosts
        let limit = min(3, max(1, maxPosts))
        if showPosts != self.showPosts || posts.map(\.id) != self.journalPosts.map(\.id) || limit != self.maxPosts { activePostIDs.removeAll() }
        self.journalPosts = posts; self.maxPosts = limit; selectedJournal = onSelectJournal
        if showPosts && !self.showPosts { rotation += 1 }
        self.showPosts = showPosts; self.largerText = largerText; self.islands = islands
        self.reserved = reserved; selected = onSelect
        holdChanged = onHoldChanged
        chooseCandidates()
    }
    private func chooseCandidates() {
        // Large Discord lists can exceed the crowd limit. Rotate only through
        // Miis actually in the scene so off-plaza friends cannot create long gaps.
        let rendered = Set(scene?.fflCharacters.map(\.id) ?? [])
        let visible = showPosts ? friends.filter { rendered.contains($0.avatar.id) } : []
        let selected = visible.isEmpty ? [] : (0..<min(6, visible.count)).map { visible[(rotation + $0) % visible.count] }
        if !selected.isEmpty, variationRotation != rotation {
            let ids = Set(friends.map(\.id))
            friendPostVariations = friendPostVariations.filter { ids.contains($0.key) }
            selectedVariations = [:]
            for friend in selected {
                let variation = friendPostVariations[friend.id, default: 0]
                selectedVariations[friend.id] = variation
                friendPostVariations[friend.id] = variation + 1
            }
            variationRotation = rotation
        }
        var speakers = Set<UUID>()
        candidates = (selected.map { PlazaSpeechPost.friend($0, variation: selectedVariations[$0.id, default: 0]) } + journalPosts)
            .filter { rendered.contains($0.speaker.id) && speakers.insert($0.speaker.id).inserted }
        activePostIDs.formIntersection(Set(candidates.map(\.id)))
        scene?.attachNotes(owner: owner, targets: candidates.map { $0.speaker.id }) { [weak self] positions in
            self?.positions = positions; self?.arrange()
        }
        arrange()
    }
    override func layout() { super.layout(); arrange() }
    private func arrange() {
        let eligible = candidates.filter { positions[$0.speaker.id] != nil }
        // Keep existing speakers throughout an interval; fill remaining slots as
        // renderer anchors arrive, rather than locking permanently to the first one.
        let available = eligible.filter { activePostIDs.contains($0.id) } +
            (activePostIDs.count < maxPosts ? eligible.filter { !activePostIDs.contains($0.id) } : [])
        let card = CGSize(width: largerText ? 260 : 230, height: 108)
        let controls = islands.map { PlazaLayout.controlRect(at: $0, in: bounds.size) }
        let anchors = available.compactMap { positions[$0.speaker.id] }
        var placements = FriendNotePlanner.positions(anchors: anchors, size: bounds.size, card: card,
                                                     obstacles: controls + reserved, limit: maxPosts)
        // Miis gather immediately under icons, so their overhead space can be
        // occupied by the icon itself. Prefer clearing it, then allow a speech
        // panel in front of the artwork rather than detaching it from its Mii.
        if placements.count < maxPosts {
            let used = Set(placements.map { $0.0 })
            let remaining = available.indices.filter { !used.contains($0) }
            let extra = FriendNotePlanner.positions(anchors: remaining.compactMap { positions[available[$0].speaker.id] },
                size: bounds.size, card: card, obstacles: reserved + placements.map { $0.1 }, limit: maxPosts - placements.count)
            placements += extra.map { (remaining[$0.0], $0.1) }
        }
        var selectedIDs = activePostIDs
        placements = placements.filter { index, _ in
            let id = available[index].id
            if selectedIDs.contains(id) { return true }
            guard selectedIDs.count < maxPosts else { return false }
            selectedIDs.insert(id); return true
        }
        activePostIDs = selectedIDs
        while buttons.count < placements.count {
            let button = FriendNoteButton(); button.target = self; button.action = #selector(clicked(_:))
            addSubview(button); buttons.append(button)
        }
        for (i, button) in buttons.enumerated() {
            guard placements.indices.contains(i) else { button.isHidden = true; button.clearHold(); continue }
            let (index, rect) = placements[i]
            activePostIDs.insert(available[index].id)
            button.isHidden = false; button.frame = rect; button.post = available[index]
            if let head = positions[available[index].speaker.id] {
                button.tailX = head.x - rect.minX
            }
            button.onHoldChanged = { [weak self] _ in
                guard let self else { return }
                self.holdChanged(self.buttons.contains { !$0.isHidden && $0.held })
            }
            button.largerText = largerText; button.needsDisplay = true
        }
    }
    @objc private func clicked(_ button: FriendNoteButton) {
        guard let post = button.post else { return }
        PlazaUISounds.shared.play(.click)
        switch post.destination {
        case .journal(let id): selectedJournal(id)
        case .friend(let id): if let friend = friends.first(where: { $0.id == id }) { selected?(friend) }
        }
    }
    func stop() { holdChanged(false); buttons.forEach { $0.cancelPortrait() }; scene?.detachNotes(owner: owner) }
}

private final class FriendNoteButton: NSButton {
    var post: PlazaSpeechPost? {
        didSet {
            updatePortrait()
            if post?.drawing != oldValue?.drawing { drawing = post.flatMap { $0.drawing.isEmpty ? nil : try? NSImage(data: InkRasterizer.png(strokes: $0.drawing)) } }
            setAccessibilityLabel(post.map { "\($0.name): \($0.accessibleText)" })
        }
    }
    private var portrait: NSImage?
    private var portraitKey: String?
    private var portraitTask: Task<Void, Never>?
    private var drawing: NSImage?
    var largerText = false
    private var hovered = false
    private var focused = false
    var held: Bool { hovered || focused }
    var onHoldChanged: (Bool) -> Void = { _ in }
    var tailX: CGFloat = 30
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); isBordered = false; title = ""; setAccessibilityElement(true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updatePortrait() {
        guard let avatar = post?.speaker else { cancelPortrait(); portrait = nil; return }
        let key = MiiHeadPictures.key(for: avatar)
        guard portraitKey != key else { return }
        portraitTask?.cancel(); portraitKey = key
        portrait = MiiHeadPictures.fallback(avatar)
        portraitTask = Task { [weak self] in
            let head = await MiiHeadPictures.image(avatar)
            guard !Task.isCancelled, let self, self.portraitKey == key else { return }
            self.portrait = head; self.portraitTask = nil; self.needsDisplay = true
        }
    }
    func cancelPortrait() { portraitTask?.cancel(); portraitTask = nil; portraitKey = nil }
    deinit { portraitTask?.cancel() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; onHoldChanged(held) }
    override func mouseExited(with event: NSEvent) { hovered = false; onHoldChanged(held) }
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); focused = result; onHoldChanged(held); return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); if result { focused = false; onHoldChanged(held) }; return result }
    func clearHold() { guard held else { return }; hovered = false; focused = false; onHoldChanged(false) }
    override func draw(_ dirtyRect: NSRect) {
        guard let post else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let outline = PlazaPostStyle.outline(in: CGRect(x: 1, y: 12, width: bounds.width - 2, height: bounds.height - 15), tailX: tailX)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: NSColor.black.withAlphaComponent(0.12).cgColor)
        context.addPath(outline.cgPath)
        context.setFillColor(NSColor.white.withAlphaComponent(isHighlighted ? 0.85 : 0.98).cgColor); context.fillPath()
        context.restoreGState()
        context.addPath(outline.cgPath); context.setStrokeColor(NSColor(white: 0.76, alpha: 0.65).cgColor)
        context.setLineWidth(1); context.strokePath()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let header: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: largerText ? 12 : 10, weight: .medium),
                                                   .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
        let tabWidth = min(bounds.width - 30, (post.name as NSString).size(withAttributes: header).width + 18)
        NSColor(white: 0.28, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 12, y: 3, width: tabWidth, height: 21), xRadius: 10.5, yRadius: 10.5).fill()
        (post.name as NSString).draw(in: CGRect(x: 21, y: 6, width: tabWidth - 18, height: 17), withAttributes: header)
        let picture = CGRect(x: 12, y: 33, width: 42, height: 42)
        NSColor(white: 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: picture, xRadius: 9, yRadius: 9).fill()
        portrait?.draw(in: picture.insetBy(dx: 2, dy: 2), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let wrapping = NSMutableParagraphStyle(); wrapping.lineBreakMode = .byWordWrapping
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: largerText ? 14 : 12),
            .foregroundColor: NSColor(white: 0.24, alpha: 1), .paragraphStyle: wrapping]
        if let drawing {
            drawing.draw(in: CGRect(x: 64, y: 29, width: 65, height: 65), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else { (post.text as NSString).draw(with: CGRect(x: 64, y: 33, width: bounds.width - 78, height: bounds.height - 49),
                                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: body)
        }
    }
}

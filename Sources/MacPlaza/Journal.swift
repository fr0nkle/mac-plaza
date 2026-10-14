import SwiftUI
import PlazaCore
import UniformTypeIdentifiers

struct NoteComposer: View {
    @ObservedObject var model: PlazaModel
    var appID: UUID?
    var existing: LocalNote?
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var strokes: [InkStroke] = []
    @State private var description = ""
    @State private var eraser = false
    @State private var drawing = false
    @State private var authorID = UUID()
    @State private var topicID: UUID?
    @State private var saveError: String?
    @State private var ready=false
    @State private var committed=false
    @State private var initialDraft: NoteDraft?
    @State private var shared = true
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: existing == nil ? "Leave a little something" : "Edit your note", subtitle: "Public notes are shared with your Plaza friends.") { close() }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("Character", selection: shared ? .constant(model.document.primaryAvatar.id) : $authorID) { ForEach(model.document.avatars) { avatar in Text(avatar.name).tag(avatar.id) } }.frame(width: 220).disabled(shared)
                    Spacer()
                    Picker("Topic", selection: $topicID) {
                        Text("The plaza").tag(nil as UUID?)
                        ForEach(model.topicApps) { app in Text(app.label).tag(Optional(app.id)) }
                    }.frame(width: 240)
                }
                if shared {
                    Text("Public as \(model.social.account?.displayName ?? "your linked Discord name") · Primary Mii: \(model.document.primaryAvatar.name)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
                TextEditor(text: $text).font(.system(size: 15)).scrollContentBackground(.hidden)
                    .padding(14).frame(height: drawing ? 80 : 150)
                    .modifier(PlazaPostSurface())
                    .accessibilityLabel("Note text")
                    .onChange(of: text) { _, value in if value.count > 280 { text = String(value.prefix(280)) } }
                HStack {
                    Toggle("Add a drawing", isOn: $drawing).toggleStyle(.checkbox)
                    Spacer()
                    Text("\(text.count) / 280").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                if drawing {
                    HStack(alignment: .top, spacing: 16) {
                        DrawingPad(strokes: $strokes, eraser: eraser).frame(width: 300, height: 300)
                            .overlay { RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.12)) }
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Tool", selection: $eraser) { Text("Pen").tag(false); Text("Eraser").tag(true) }.pickerStyle(.segmented)
                            HStack { Button("Undo") { if !strokes.isEmpty { strokes.removeLast() } }.disabled(strokes.isEmpty); Button("Clear") { strokes.removeAll() } }
                            Text("A small black-ink sketch. Draw with your mouse or trackpad.").font(.caption).foregroundStyle(.secondary)
                            TextField("Describe your drawing", text: $description, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3...5)
                                .onChange(of: description) { _, value in if value.count > 160 { description = String(value.prefix(160)) } }
                            Text("A description is required so everyone can read your drawing.").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                HStack {
                    Toggle("Public · Plaza friends", isOn: $shared).toggleStyle(.checkbox).font(.caption).help("Share this note using your linked Discord name and primary Mii. Uncheck to keep it on this Mac.")
                    Spacer()
                    Button("Keep Draft & Close") { close() }
                    Button(existing == nil ? "Save Note" : "Save Changes") { save() }
                        .buttonStyle(.borderedProminent).tint(PlazaStyle.teal).keyboardShortcut(.defaultAction).disabled(!canSave)
                }
            }.padding(22)
        }.frame(width: 650)
            .onAppear {
                model.beginWritingNote()
                authorID = existing.flatMap { n in model.document.avatars.first(where: { $0.id == n.authorID })?.id } ?? model.document.primaryAvatar.id
                topicID = existing?.appID ?? appID
                if existing == nil, let draft=model.document.draft, appID == nil || draft.appID == appID {
                    text=draft.text; strokes=draft.drawing; description=draft.description; drawing = !strokes.isEmpty; topicID=draft.appID
                    if let id=draft.authorID, model.document.avatars.contains(where:{$0.id==id}) { authorID=id }
                }
                if let existing { shared = existing.shared == true; text = existing.text; strokes = existing.drawing; description = existing.drawingDescription; drawing = !strokes.isEmpty }
                initialDraft=draft
                ready=true
            }
            .onDisappear { model.endWritingNote() }
            .onChange(of:draft) { _,value in
                if ready && !committed && existing == nil && value != initialDraft {
                    initialDraft=value
                    model.storeDraft(value)
                }
            }
    }
    private func close() { if let onClose { onClose() } else { dismiss() } }
    private var draft: NoteDraft { var d=NoteDraft(); d.text=text; d.drawing=drawing ? strokes:[]; d.description=description; d.appID=topicID; d.authorID=authorID; return d }
    private var canSave: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (drawing && !strokes.isEmpty)) &&
        (!drawing || strokes.isEmpty || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (existing != nil || model.document.notes.count < 200)
    }
    private func save() {
        guard let author = shared ? model.document.primaryAvatar : model.document.avatars.first(where: { $0.id == authorID }) else { return }
        var note = LocalNote(authorID: author.id, author: author.name, appID: topicID, text: text.trimmingCharacters(in: .whitespacesAndNewlines), drawing: drawing ? strokes : [], drawingDescription: description.trimmingCharacters(in: .whitespacesAndNewlines))
        note.shared = shared
        if let existing { note.id = existing.id; note.created = existing.created; note.acknowledged = existing.acknowledged; note.replies=existing.replies; note.read=existing.read }
        let saved = model.mutate { doc in
            if let index = doc.notes.firstIndex(where: { $0.id == note.id }) { doc.notes[index] = note }
            else { doc.notes.insert(note, at: 0) }
        }
        if saved { committed=true; if existing == nil { model.clearDraft() }; model.status = "Your note is saved in the plaza journal."; close() }
        else { saveError = model.error ?? "The note could not be saved."; model.error = nil }
    }
}

struct InkCanvas: View {
    var strokes: [InkStroke]
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                var path = Path(); path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                if stroke.points.count == 1 { path.addLine(to: CGPoint(x: first.x * size.width + 0.1, y: first.y * size.height + 0.1)) }
                for point in stroke.points.dropFirst() { path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height)) }
                context.stroke(path, with: .color(stroke.eraser ? .white : Color(white: 0.14)), style: StrokeStyle(lineWidth: size.width * (stroke.eraser ? 0.045 : 0.008), lineCap: .round, lineJoin: .round))
            }
        }
    }
}
struct DrawingPad: View {
    @Binding var strokes: [InkStroke]
    var eraser: Bool
    @State private var current: [InkPoint] = []
    var body: some View {
        GeometryReader { geometry in
            InkCanvas(strokes: strokes + (current.isEmpty ? [] : [InkStroke(points: current, eraser: eraser)]))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard strokes.count < 512, strokes.reduce(0, { $0 + $1.points.count }) + current.count < 20000 else { return }
                    let point = InkPoint(min(1, max(0, value.location.x / geometry.size.width)), min(1, max(0, value.location.y / geometry.size.height)))
                    if let last = current.last, hypot(last.x - point.x, last.y - point.y) < 0.002 { return }
                    current.append(point)
                }.onEnded { _ in
                    if !current.isEmpty { strokes.append(InkStroke(points: current, eraser: eraser)); current.removeAll(keepingCapacity: true) }
                })
                .accessibilityLabel("Drawing canvas. Use the note text field to write an accessible text note.")
        }
    }
}

struct FeedView: View {
    @ObservedObject var model: PlazaModel
    var authorID: UUID?
    var miiverse = false
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var composing = false
    @State private var editing: LocalNote?
    @State private var deleted: LocalNote?
    @State private var replyTo: LocalNote?
    @State private var section = "all"
    @State private var sort = MiiverseSort.newest
    var notes: [LocalNote] { model.allJournalNotes.filter { (authorID == nil || $0.authorID == authorID) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || model.noteDisplayName($0).localizedCaseInsensitiveContains(query) || $0.drawingDescription.localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        let catalog = model.miiverseCatalog
        let selected = catalog.sections.first { $0.id == section } ?? catalog.sections[0]
        let entries = catalog.filtered(section: selected.id, query: query, sort: sort)
        let labels = Dictionary(uniqueKeysWithValues: catalog.entries.map { ($0.id, $0.sectionLabel) })
        let ownIDs = Set(catalog.entries.filter(\.own).map(\.id))
        HStack(spacing: 0) {
            if miiverse { sidebar(catalog, selected: selected.id); Divider() }
            journal(notes: miiverse ? entries.map(\.note) : notes, labels: labels, ownIDs: ownIDs, selected: selected)
        }.frame(width: miiverse ? 960 : 660, height: miiverse ? 720 : 670).background(PlazaStyle.paper)
            .sheet(isPresented: $composing) { NoteComposer(model: model, appID: miiverse ? selected.appID : nil) }
            .sheet(item: $editing) { note in NoteComposer(model: model, existing: note) }
            .sheet(item:$replyTo) { note in ReplyComposer(model:model,noteID:note.id) }
    }
    private func journal(notes: [LocalNote], labels: [UUID: String], ownIDs: Set<UUID>, selected: MiiverseSection) -> some View {
        VStack(spacing: 0) {
            SheetHeader(title: miiverse ? selected.label : "Plaza journal", subtitle: miiverse ? "Miiverse · \(notes.count) notes · Your plaza and friends" : "Your notes and public notes from Plaza friends.") {
                if let onClose { onClose() } else { dismiss() }
            }
            HStack {
                TextField(miiverse ? "Search Miiverse" : "Search your journal", text: $query).textFieldStyle(.roundedBorder)
                if miiverse {
                    Picker("Sort notes", selection: $sort) { ForEach(MiiverseSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .labelsHidden().frame(width: 120).accessibilityLabel("Sort notes")
                    Button { Task { await model.social.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh Miiverse").help("Refresh shared notes")
                }
                Button { composing = true } label: { Label("New Note", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal).disabled(model.document.notes.count >= 200)
            }.padding(18)
            ScrollViewReader { scrollProxy in
              ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if notes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "text.bubble").font(.system(size: 35)).foregroundStyle(PlazaStyle.teal)
                            Text(query.isEmpty ? (miiverse ? "No notes in this section yet." : "A little room for your thoughts.") : "No notes found.").font(.title3)
                            Text("Write a reminder, celebrate a finished project, or leave a sketch. Choose Public to share a note with your Plaza friends.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(36)
                    }
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                MiiHeadIcon(avatar: model.noteAvatar(note)).frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(ownIDs.contains(note.id) ? (note.shared == true ? "Your public note · Plaza friends" : "Private · This Mac") : "Friend’s public note") · \(note.created.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(labels[note.id] ?? "The Plaza").font(.caption).padding(7).background(PlazaStyle.teal.opacity(0.06), in: Capsule())
                            }
                            if !note.text.isEmpty { Text(note.text).font(.system(size: 14, design: .rounded)).foregroundStyle(PlazaPostStyle.text).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                            if !note.drawing.isEmpty {
                                InkCanvas(strokes: note.drawing).frame(width: 280, height: 280).border(.black.opacity(0.06)).accessibilityLabel(note.drawingDescription)
                                Text(note.drawingDescription).font(.caption).foregroundStyle(.secondary)
                            }
                            if note.shared == true { SharedNoteInteractions(model: model, social: model.social, note: note) }
                            HStack {
                                if model.isOwnNote(note) {
                                if note.shared != true {
                                Button {
                                    model.mutate { doc in if let i = doc.notes.firstIndex(where: { $0.id == note.id }) { doc.notes[i].acknowledged.toggle() } }
                                } label: { Label(note.acknowledged ? "Appreciated" : "Appreciate", systemImage: note.acknowledged ? "heart.fill" : "heart") }.foregroundStyle(note.acknowledged ? Color.pink : PlazaStyle.teal)
                                Button("Reply (\((note.replies ?? []).count))") { replyTo=note }
                                }
                                Spacer()
                                if !note.drawing.isEmpty { Button("Export Drawing") { exportDrawing(note) } }
                                Button("Edit") { editing = note }
                                Button("Delete", role: .destructive) { deleted = note; model.mutate { $0.notes.removeAll { $0.id == note.id } } }
                                } else {
                                    Label(ownIDs.contains(note.id) ? "Your shared note" : "Shared by a Plaza friend", systemImage: "person.2")
                                    Spacer()
                                    if !note.drawing.isEmpty { Button("Export Drawing") { exportDrawing(note) } }
                                }
                            }.font(.caption).buttonStyle(.borderless)
                            ForEach(note.replies ?? []) { reply in
                                HStack(alignment:.top) {
                                    VStack(alignment:.leading,spacing:4) { Text("\(reply.author) · Local reply").font(.caption).foregroundStyle(PlazaStyle.teal); Text(reply.text).font(.callout).textSelection(.enabled) }
                                    Spacer()
                                    Button { model.mutate { doc in if let i=doc.notes.firstIndex(where:{$0.id==note.id}) { doc.notes[i].replies?.removeAll { $0.id==reply.id } } } } label:{Image(systemName:"trash")}.buttonStyle(.borderless).accessibilityLabel("Delete reply by \(reply.author)")
                                }.padding(12).modifier(PlazaPostSurface())
                            }
                        }.padding(18).padding(.bottom, 9).frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(PlazaPostSurface(tailX: 38))
                            .overlay(alignment: .topLeading) { PlazaNameTab(name: model.noteDisplayName(note), large: true).padding(.leading, 18).offset(y: -9) }
                            .padding(.top, 9).id(note.id)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Plaza Guide", systemImage: "sparkle").font(.caption).foregroundStyle(PlazaStyle.teal)
                        Text(model.social.journalSyncMessage).font(.caption).foregroundStyle(.secondary)
                        Text("Public notes sync with your authorized Plaza friends. Public replies and likes sync too. Private notes, drafts and earlier local replies stay on this Mac. Edits and deletions sync when connected.").font(.callout).foregroundStyle(.secondary)
                    }.padding(18)
                }.padding(.horizontal, 18).padding(.bottom, 18)
              }.background(PlazaStyle.paper)
               .onAppear { if !miiverse, let id = model.selectedNoteID { scrollProxy.scrollTo(id, anchor: .top) } }
               .onChange(of: section) { _, _ in if let id = notes.first?.id { scrollProxy.scrollTo(id, anchor: .top) } }
            }
            if let deleted {
                HStack { Text("Note deleted.").font(.caption); Spacer(); Button("Undo") { model.mutate { $0.notes.insert(deleted, at: 0) }; self.deleted = nil } }.padding(12)
            }
            if miiverse {
                Divider()
                HStack(spacing: 10) {
                    Label("Miiverse music", systemImage: "speaker.wave.2").font(.caption)
                    Slider(value: Binding(get: { model.document.preferences.miiverseMusicVolume ?? 0.10 }, set: { value in
                        if model.mutate({ $0.preferences.miiverseMusicVolume = value }) { model.updateAudio() }
                    }), in: 0...0.35).frame(width: 140).accessibilityLabel("Miiverse music volume")
                    Text("\(Int((model.document.preferences.miiverseMusicVolume ?? 0.10) * 100))%")
                        .font(.caption).monospacedDigit().frame(width: 34)
                    Spacer()
                    Text("\(model.music.title(for: .miiverse)) · On this Mac").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.padding(14)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(PlazaStyle.paper)
    }
    private func sidebar(_ catalog: MiiverseCatalog, selected: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Miiverse", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 23, weight: .bold, design: .rounded)).foregroundStyle(PlazaStyle.teal).padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(catalog.sections.prefix(4))) { item in sectionButton(item, selected: selected) }
                    Text("APP COMMUNITIES").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).padding(.top, 18).padding(.horizontal, 10)
                    ForEach(Array(catalog.sections.dropFirst(4))) { item in sectionButton(item, selected: selected) }
                }.padding(.horizontal, 12).padding(.bottom, 16)
            }
            Text("Your private notes stay on this Mac. Public notes come from your Plaza friends.")
                .font(.caption).foregroundStyle(.secondary).padding(18)
        }.frame(width: 225).background(PlazaStyle.teal.opacity(0.04))
    }
    private func sectionButton(_ item: MiiverseSection, selected: String) -> some View {
        Button { section = item.id } label: {
            HStack(spacing: 8) {
                Image(systemName: item.id == "all" ? "square.grid.2x2" : item.id == "mine" ? "person.crop.circle" : item.id == "friends" ? "person.2" : item.id == "plaza" ? "sun.max" : "app")
                    .frame(width: 20)
                Text(item.label).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(String(item.count)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 13, weight: selected == item.id ? .semibold : .regular))
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected == item.id ? PlazaStyle.teal.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).foregroundStyle(PlazaStyle.ink)
            .accessibilityLabel(item.label).accessibilityValue("\(item.count) notes\(selected == item.id ? ", selected" : "")")
    }
    private func exportDrawing(_ note: LocalNote) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Plaza Drawing.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let png = try InkRasterizer.png(strokes: note.drawing)
            try png.write(to: url, options: .atomic)
            model.status = "Drawing exported as a 1024 × 1024 PNG."
        } catch { model.error = error.localizedDescription }
    }
}

enum InkRasterizer {
    static func png(strokes: [InkStroke]) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: rep) else { throw PlazaError.invalid("The drawing could not be rendered.") }
        let c = graphics.cgContext
        c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        c.translateBy(x: 0, y: 1024); c.scaleBy(x: 1, y: -1)
        c.setLineCap(.round); c.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            c.setStrokeColor(stroke.eraser ? NSColor.white.cgColor : NSColor(white: 0.14, alpha: 1).cgColor)
            c.setLineWidth(1024 * (stroke.eraser ? 0.045 : 0.008))
            c.beginPath(); c.move(to: CGPoint(x: first.x * 1024, y: first.y * 1024))
            if stroke.points.count == 1 { c.addLine(to: CGPoint(x: first.x * 1024 + 0.1, y: first.y * 1024 + 0.1)) }
            for point in stroke.points.dropFirst() { c.addLine(to: CGPoint(x: point.x * 1024, y: point.y * 1024)) }
            c.strokePath()
        }
        guard let png = rep.representation(using: .png, properties: [:]), png.count <= 2_000_000 else { throw PlazaError.invalid("The drawing could not be exported within the 2 MB limit.") }
        return png
    }
}

struct ReplyComposer: View {
    @ObservedObject var model: PlazaModel
    let noteID: UUID
    var existingSharedReply: SharedJournalReply? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var authorID = UUID()
    @State private var replyID = UUID()
    @State private var publicReply = false
    @State private var saving = false
    @State private var saveError: String?
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: publicReply ? "A shared reply" : "A local reply",
                subtitle: publicReply ? "Visible to the note’s Plaza friends." : "Saved only on this Mac.") { if !saving { dismiss() } }
            VStack(alignment: .leading, spacing: 15) {
                Picker("Character", selection: publicReply ? .constant(model.document.primaryAvatar.id) : $authorID) { ForEach(model.document.avatars) { Text($0.name).tag($0.id) } }.disabled(publicReply)
                if publicReply { Text("Public as \(model.social.account?.displayName ?? "your linked Discord name") · Primary Mii: \(model.document.primaryAvatar.name)").font(.caption).foregroundStyle(.secondary) }
                TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).frame(height: 130)
                    .padding(14).modifier(PlazaPostSurface()).accessibilityLabel("Reply text")
                    .onChange(of: text) { _, value in if value.count > 280 { text = String(value.prefix(280)) } }
                if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
                HStack {
                    Text("\(text.count) / 280").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(saving ? "Sending…" : (publicReply ? "Share Reply" : "Save Reply")) { Task { await save() } }
                        .buttonStyle(.borderedProminent).tint(PlazaStyle.teal).keyboardShortcut(.defaultAction)
                        .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(20).disabled(saving)
        }.frame(width: 540).interactiveDismissDisabled(saving)
        .onAppear {
            model.beginWritingNote()
            publicReply = existingSharedReply != nil || model.journalNote(noteID)?.shared == true
            authorID = existingSharedReply.flatMap { reply in model.document.avatars.first { $0.name == reply.author.name }?.id } ?? model.document.primaryAvatar.id
            if let existingSharedReply { text = existingSharedReply.text; replyID = existingSharedReply.id }
        }
        .onDisappear { model.endWritingNote() }
    }
    @MainActor private func save() async {
        guard !saving, let author = publicReply ? model.document.primaryAvatar : model.document.avatars.first(where: { $0.id == authorID }),
              let note = model.journalNote(noteID) else {
            saveError = "This note is no longer available."; return
        }
        saving = true; defer { saving = false }
        if publicReply {
            guard let thread = model.sharedThread(for: note) else { saveError = "Connect to Plaza and wait for this public note to sync."; return }
            if await model.social.reply(noteID: thread.id, replyID: replyID, author: author, text: text) { dismiss() }
            else { saveError = model.social.journalInteractionMessage ?? "The reply could not be shared. Your text is still here." }
        } else {
            let reply = LocalReply(authorID: author.id, author: author.name, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            if model.mutate({ doc in
                if let index = doc.notes.firstIndex(where: { $0.id == noteID }) {
                    if doc.notes[index].replies == nil { doc.notes[index].replies = [] }
                    doc.notes[index].replies?.append(reply)
                }
            }) { dismiss() } else { saveError = model.error }
        }
    }
}

struct CharacterProfileView: View {
    @ObservedObject var model: PlazaModel
    let avatar:Avatar
    @Environment(\.dismiss) private var dismiss
    @State private var angle:CGFloat=0
    @State private var journal=false
    @State private var editing=false
    private var saved:Bool { model.document.avatars.contains(where:{$0.id==avatar.id}) }
    var body: some View {
        VStack(spacing:18) {
            SheetHeader(title:avatar.name,subtitle:saved ? "Your local character":"A decorative visitor on this Mac") { dismiss() }
            if model.document.preferences.safeMode { Image(nsImage:AvatarArtwork.face(avatar)).resizable().scaledToFit().frame(height:260) }
            else { CharacterPreview(avatar:avatar,angle:angle,pose:3).frame(height:260).gesture(DragGesture().onChanged { angle=CGFloat($0.translation.width)*0.015 }) }
            if saved {
                Text("\(model.document.notes.filter { $0.authorID==avatar.id }.count) local notes").foregroundStyle(.secondary)
                HStack { Button("Read Character’s Notes") { journal=true }; Button("Customize Character") { editing=true }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal) }
            } else { Text("This visitor is generated locally. They have no account or online activity.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal,35) }
            Spacer(minLength:12)
        }.frame(width:500,height:470)
        .sheet(isPresented:$journal) { FeedView(model:model,authorID:avatar.id) }
        .sheet(isPresented:$editing) { CharacterEditor(model:model,initialID:avatar.id) }
    }
}

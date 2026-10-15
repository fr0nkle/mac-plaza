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
    @State private var audience = NoteAudience.everyone
    private var shared: Bool { audience != .privateOnly }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: existing == nil ? "New Miiverse Post" : "Edit Miiverse Post", subtitle: "Choose who can see your post.") { close() }
            VStack(alignment: .leading, spacing: 16) {
                Picker("Post visibility", selection: $audience) {
                    ForEach(NoteAudience.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).accessibilityLabel("Post visibility")
                Text(audience.explanation)
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("Character", selection: shared ? .constant(model.document.primaryAvatar.id) : $authorID) { ForEach(model.document.avatars) { avatar in Text(avatar.name).tag(avatar.id) } }.frame(width: 220).disabled(shared)
                    Spacer()
                    Picker("Topic", selection: $topicID) {
                        Text("The plaza").tag(nil as UUID?)
                        ForEach(model.topicApps) { app in Text(app.label).tag(Optional(app.id)) }
                    }.frame(width: 240)
                }
                if shared {
                    Text("Post as \(model.social.account?.displayName ?? "your linked Discord name") · Primary Mii: \(model.document.primaryAvatar.name)")
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
                            HStack { PlazaButton("Undo") { if !strokes.isEmpty { strokes.removeLast() } }.disabled(strokes.isEmpty); PlazaButton("Clear") { strokes.removeAll() } }
                            Text("A small black-ink sketch. Draw with your mouse or trackpad.").font(.caption).foregroundStyle(.secondary)
                            TextField("Describe your drawing", text: $description, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3...5)
                                .onChange(of: description) { _, value in if value.count > 160 { description = String(value.prefix(160)) } }
                            Text("A description is required so everyone can read your drawing.").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                HStack {
                    Spacer()
                    PlazaButton("Keep Draft & Close") { close() }
                    PlazaButton(existing == nil ? "Post" : "Save Changes") { save() }
                        .buttonStyle(.borderedProminent).tint(PlazaStyle.teal).keyboardShortcut(.defaultAction).disabled(!canSave)
                }
                Text(NoteRetention.disclaimer).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(22)
        }.frame(width: 650)
            .onAppear {
                model.beginWritingNote()
                authorID = existing.flatMap { n in model.document.avatars.first(where: { $0.id == n.authorID })?.id } ?? model.document.primaryAvatar.id
                topicID = existing?.appID ?? appID
                if existing == nil, let draft=model.document.draft, appID == nil || draft.appID == appID {
                    text=draft.text; strokes=draft.drawing; description=draft.description; drawing = !strokes.isEmpty; topicID=draft.appID
                    audience=draft.visibility
                    if let id=draft.authorID, model.document.avatars.contains(where:{$0.id==id}) { authorID=id }
                }
                if let existing { audience = existing.visibility; text = existing.text; strokes = existing.drawing; description = existing.drawingDescription; drawing = !strokes.isEmpty }
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
    private var draft: NoteDraft { var d=NoteDraft(); d.text=text; d.drawing=drawing ? strokes:[]; d.description=description; d.appID=topicID; d.authorID=authorID; d.visibility=audience; return d }
    private var canSave: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (drawing && !strokes.isEmpty)) &&
        (!drawing || strokes.isEmpty || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (existing != nil || model.document.notes.count < 200)
    }
    private func save() {
        if let existing, NoteRetention.isExpired(existing.created) {
            saveError = "This note has expired. Copy your text into a new note to post it again."
            model.expireNotes()
            return
        }
        guard let author = shared ? model.document.primaryAvatar : model.document.avatars.first(where: { $0.id == authorID }) else { return }
        var note = LocalNote(authorID: author.id, author: author.name, appID: topicID, text: text.trimmingCharacters(in: .whitespacesAndNewlines), drawing: drawing ? strokes : [], drawingDescription: description.trimmingCharacters(in: .whitespacesAndNewlines))
        note.visibility = audience
        if let existing { note.id = existing.id; note.created = existing.created; note.acknowledged = existing.acknowledged; note.replies=existing.replies; note.read=existing.read }
        let saved = model.mutate { doc in
            if let index = doc.notes.firstIndex(where: { $0.id == note.id }) { doc.notes[index] = note }
            else { doc.notes.insert(note, at: 0) }
        }
        if saved { committed=true; if existing == nil { model.clearDraft() }; model.status = "Your post is saved in Miiverse."; close() }
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

struct MiiversePostsView: View {
    @ObservedObject var model: PlazaModel
    var authorID: UUID?
    @Binding var section: String
    var onBack: () -> Void
    var onAccount: () -> Void
    var onActivity: () -> Void
    @State private var query = ""
    @State private var composing = false
    @State private var editing: LocalNote?
    @State private var deleted: LocalNote?
    @State private var replyTo: LocalNote?
    @State private var sort = MiiverseSort.newest
    var body: some View {
        let catalog = model.miiverseCatalog
        let selected = catalog.sections.first { $0.id == section } ?? catalog.sections[0]
        let entries = catalog.filtered(section: selected.id, query: query, sort: sort).filter { authorID == nil || $0.note.authorID == authorID }
        let labels = Dictionary(uniqueKeysWithValues: catalog.entries.map { ($0.id, $0.sectionLabel) })
        let ownIDs = Set(catalog.entries.filter(\.own).map(\.id))
        posts(notes: entries.map(\.note), labels: labels, ownIDs: ownIDs, selected: selected)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(PlazaStyle.paper)
            .sheet(isPresented: $composing) { NoteComposer(model: model, appID: selected.appID) }
            .sheet(item: $editing) { note in NoteComposer(model: model, existing: note) }
            .sheet(item:$replyTo) { note in ReplyComposer(model:model,noteID:note.id) }
    }
    private func posts(notes: [LocalNote], labels: [UUID: String], ownIDs: Set<UUID>, selected: MiiverseSection) -> some View {
        VStack(spacing: 0) {
            if selected.id != "all" {
                HStack {
                    PlazaButton(action: onBack) { Label("Communities", systemImage: "chevron.left") }
                    Spacer()
                    Text("\(selected.label) · \(notes.count) posts").font(.headline)
                    Spacer()
                }.padding(18)
            }
            if !model.social.hasSession {
                HStack {
                    Text("Sign in with Discord to browse Public and Friends Only posts.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    PlazaButton("Connect Discord", action: onAccount)
                }.padding(.horizontal, 18).padding(.top, 12)
            }
            HStack {
                TextField("Search Miiverse", text: $query).textFieldStyle(.roundedBorder)
                Group {
                    Picker("Sort notes", selection: $sort) { ForEach(MiiverseSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .labelsHidden().frame(width: 120).accessibilityLabel("Sort notes")
                    PlazaButton { Task { await model.social.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh Miiverse").help("Refresh shared notes")
                    PlazaMiiverseActivityButton(social: model.social, onOpen: onActivity)
                }
                PlazaButton { composing = true } label: { Label("New Post", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal).disabled(model.document.notes.count >= 200)
            }.padding(18)
            ScrollViewReader { scrollProxy in
              ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if notes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "text.bubble").font(.system(size: 35)).foregroundStyle(PlazaStyle.teal)
                            Text(query.isEmpty ? "No posts in this section yet." : "No notes found.").font(.title3)
                            Text("Write a reminder, celebrate a finished project, or leave a sketch. New posts are public to everyone signed in with Discord. Choose Friends Only or Private for a smaller audience.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(36)
                    }
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                MiiHeadIcon(avatar: model.noteAvatar(note)).frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(ownIDs.contains(note.id) ? "Your note · " + note.visibility.label : note.visibility.label + " post") · \(note.created.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
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
                                PlazaButton {
                                    model.mutate { doc in if let i = doc.notes.firstIndex(where: { $0.id == note.id }) { doc.notes[i].acknowledged.toggle() } }
                                } label: { Label(note.acknowledged ? "Appreciated" : "Appreciate", systemImage: note.acknowledged ? "heart.fill" : "heart") }.foregroundStyle(note.acknowledged ? Color.pink : PlazaStyle.teal)
                                PlazaButton("Reply (\((note.replies ?? []).count))") { replyTo=note }
                                }
                                Spacer()
                                if !note.drawing.isEmpty { PlazaButton("Export Drawing") { exportDrawing(note) } }
                                PlazaButton("Edit") { editing = note }
                                PlazaButton("Delete", role: .destructive) { deleted = note; model.mutate { $0.notes.removeAll { $0.id == note.id } } }
                                } else {
                                    Label(ownIDs.contains(note.id) ? "Your shared note" : "Shared in Miiverse", systemImage: "person.2")
                                    Spacer()
                                    if !ownIDs.contains(note.id), let owner = model.sharedThread(for: note)?.ownerID {
                                        PlazaButton("Block Author", role: .destructive) { model.social.remove(owner, block: true) }
                                            .disabled(model.social.busy)
                                    }
                                    if !note.drawing.isEmpty { PlazaButton("Export Drawing") { exportDrawing(note) } }
                                }
                            }.font(.caption).buttonStyle(.borderless)
                            ForEach(note.replies ?? []) { reply in
                                HStack(alignment:.top) {
                                    VStack(alignment:.leading,spacing:4) { Text("\(reply.author) · Local reply").font(.caption).foregroundStyle(PlazaStyle.teal); Text(reply.text).font(.callout).textSelection(.enabled) }
                                    Spacer()
                                    PlazaButton { model.mutate { doc in if let i=doc.notes.firstIndex(where:{$0.id==note.id}) { doc.notes[i].replies?.removeAll { $0.id==reply.id } } } } label:{Image(systemName:"trash")}.buttonStyle(.borderless).accessibilityLabel("Delete reply by \(reply.author)")
                                }.padding(12).modifier(PlazaPostSurface())
                            }
                        }.padding(18).padding(.bottom, 9).frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(PlazaPostSurface(tailX: 38))
                            .overlay(alignment: .topLeading) { PlazaNameTab(name: model.noteDisplayName(note), large: true).padding(.leading, 18).offset(y: -9) }
                            .padding(.top, 9).id(note.id)
                    }
                }.padding(.horizontal, 18).padding(.bottom, 18)
              }.background(PlazaStyle.paper)
               .task(id: model.selectedNoteID) {
                   if authorID == nil, let id = model.selectedNoteID {
                       section = "all"; query = ""
                       await Task.yield()
                       scrollProxy.scrollTo(id, anchor: .top)
                   }
               }
               .onChange(of: section) { _, _ in if let id = notes.first?.id { scrollProxy.scrollTo(id, anchor: .top) } }
            }
            if let deleted {
                HStack { Text("Note deleted.").font(.caption); Spacer(); PlazaButton("Undo") { model.mutate { $0.notes.insert(deleted, at: 0) }; self.deleted = nil } }.padding(12)
            }
            Group {
                Divider()
                HStack(spacing: 10) {
                    Label("Miiverse music", systemImage: "speaker.wave.2").font(.caption)
                    Slider(value: Binding(get: { model.document.preferences.miiverseMusicVolume ?? 0.10 }, set: { value in
                        if model.mutate({ $0.preferences.miiverseMusicVolume = value }) { model.updateAudio() }
                    }), in: 0...0.35).frame(width: 140).accessibilityLabel("Miiverse music volume")
                    Text("\(Int((model.document.preferences.miiverseMusicVolume ?? 0.10) * 100))%")
                        .font(.caption).monospacedDigit().frame(width: 34)
                    Spacer()
                    Text("\(model.music.title(for: model.miiverseMusicTrack)) · On this Mac").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.padding(14)
            }
            Divider()
            Text(NoteRetention.disclaimer).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 18).padding(.vertical, 10)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(PlazaStyle.paper)
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
                subtitle: publicReply ? "Visible to the same audience as the post." : "Saved only on this Mac.") { if !saving { dismiss() } }
            VStack(alignment: .leading, spacing: 15) {
                Picker("Character", selection: publicReply ? .constant(model.document.primaryAvatar.id) : $authorID) { ForEach(model.document.avatars) { Text($0.name).tag($0.id) } }.disabled(publicReply)
                if publicReply { Text("Post as \(model.social.account?.displayName ?? "your linked Discord name") · Primary Mii: \(model.document.primaryAvatar.name)").font(.caption).foregroundStyle(.secondary) }
                TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).frame(height: 130)
                    .padding(14).modifier(PlazaPostSurface()).accessibilityLabel("Reply text")
                    .onChange(of: text) { _, value in if value.count > 280 { text = String(value.prefix(280)) } }
                if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
                HStack {
                    Text("\(text.count) / 280").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    PlazaButton(saving ? "Sending…" : (publicReply ? "Share Reply" : "Save Reply")) { Task { await save() } }
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
    @State private var editing=false
    private var saved:Bool { model.document.avatars.contains(where:{$0.id==avatar.id}) }
    var body: some View {
        VStack(spacing:18) {
            SheetHeader(title:avatar.name,subtitle:saved ? "Your local character":"A decorative visitor on this Mac") { dismiss() }
            if model.document.preferences.safeMode { Image(nsImage:AvatarArtwork.face(avatar)).resizable().scaledToFit().frame(height:260) }
            else { CharacterPreview(avatar:avatar,angle:angle,pose:3).frame(height:260).gesture(DragGesture().onChanged { angle=CGFloat($0.translation.width)*0.015 }) }
            if saved {
                HStack { PlazaButton("Open Miiverse") { model.openMiiverse() }; PlazaButton("Customize Character") { editing=true }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal) }
            } else { Text("This visitor is generated locally. They have no account or online activity.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal,35) }
            Spacer(minLength:12)
        }.frame(width:500,height:470)
        .sheet(isPresented:$editing) { CharacterEditor(model:model,initialID:avatar.id) }
    }
}

import SwiftUI
import PlazaCore
import UniformTypeIdentifiers

struct NoteComposer: View {
    @ObservedObject var model: PlazaModel
    var appID: UUID?
    var existing: LocalNote?
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
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: existing == nil ? "Leave a little something" : "Edit your note", subtitle: "Saved only on this Mac. No account needed.") { dismiss() }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("Character", selection: $authorID) { ForEach(model.document.avatars) { avatar in Text(avatar.name).tag(avatar.id) } }.frame(width: 220)
                    Spacer()
                    Picker("Topic", selection: $topicID) {
                        Text("The plaza").tag(nil as UUID?)
                        ForEach(model.document.apps) { app in Text(app.label).tag(Optional(app.id)) }
                    }.frame(width: 240)
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
                    Label("Only you · Local note", systemImage: "lock").font(.caption).foregroundStyle(PlazaStyle.teal)
                    Spacer()
                    Button("Keep Draft & Close") { dismiss() }
                    Button(existing == nil ? "Save Note" : "Save Changes") { save() }
                        .buttonStyle(.borderedProminent).tint(PlazaStyle.teal).keyboardShortcut(.defaultAction).disabled(!canSave)
                }
            }.padding(22)
        }.frame(width: 650)
            .onAppear {
                authorID = existing.flatMap { n in model.document.avatars.first(where: { $0.id == n.authorID })?.id } ?? model.document.primaryAvatar.id
                topicID = existing?.appID ?? appID
                if existing == nil, let draft=model.document.draft, appID == nil || draft.appID == appID {
                    text=draft.text; strokes=draft.drawing; description=draft.description; drawing = !strokes.isEmpty; topicID=draft.appID
                    if let id=draft.authorID, model.document.avatars.contains(where:{$0.id==id}) { authorID=id }
                }
                ready=true
                if let existing { text = existing.text; strokes = existing.drawing; description = existing.drawingDescription; drawing = !strokes.isEmpty }
            }
            .onChange(of:draft) { _,value in if ready && !committed && existing == nil { model.storeDraft(value) } }
    }
    private var draft: NoteDraft { var d=NoteDraft(); d.text=text; d.drawing=drawing ? strokes:[]; d.description=description; d.appID=topicID; d.authorID=authorID; return d }
    private var canSave: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (drawing && !strokes.isEmpty)) &&
        (!drawing || strokes.isEmpty || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (existing != nil || model.document.notes.count < 200)
    }
    private func save() {
        guard let author = model.document.avatars.first(where: { $0.id == authorID }) else { return }
        var note = LocalNote(authorID: author.id, author: author.name, appID: topicID, text: text.trimmingCharacters(in: .whitespacesAndNewlines), drawing: drawing ? strokes : [], drawingDescription: description.trimmingCharacters(in: .whitespacesAndNewlines))
        if let existing { note.id = existing.id; note.created = existing.created; note.acknowledged = existing.acknowledged; note.replies=existing.replies; note.read=existing.read }
        let saved = model.mutate { doc in
            if let index = doc.notes.firstIndex(where: { $0.id == note.id }) { doc.notes[index] = note }
            else { doc.notes.insert(note, at: 0) }
        }
        if saved { committed=true; if existing == nil { model.clearDraft() }; model.status = "Your note is saved in the plaza journal."; dismiss() }
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
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var composing = false
    @State private var editing: LocalNote?
    @State private var deleted: LocalNote?
    @State private var replyTo: LocalNote?
    var notes: [LocalNote] { model.document.notes.filter { (authorID == nil || $0.authorID == authorID) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query) || $0.drawingDescription.localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Plaza journal", subtitle: "Thoughts and sketches from your local characters.") { dismiss() }
            HStack {
                TextField("Search your journal", text: $query).textFieldStyle(.roundedBorder)
                Button { composing = true } label: { Label("New Note", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal).disabled(model.document.notes.count >= 200)
            }.padding(18)
            ScrollViewReader { scrollProxy in
              ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if notes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "text.bubble").font(.system(size: 35)).foregroundStyle(PlazaStyle.teal)
                            Text(query.isEmpty ? "A little room for your thoughts." : "No notes found.").font(.title3)
                            Text("Write a reminder, celebrate a finished project, or leave a sketch. Everything stays on this Mac.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(36)
                    }
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                MiiHeadIcon(avatar: model.document.avatars.first(where: { $0.id == note.authorID }) ?? Avatar(name: note.author)).frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Local character · \(note.created.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(note.appID.flatMap { id in model.document.apps.first(where: { $0.id == id })?.label } ?? "The plaza").font(.caption).padding(7).background(PlazaStyle.teal.opacity(0.06), in: Capsule())
                            }
                            if !note.text.isEmpty { Text(note.text).font(.system(size: 14, design: .rounded)).foregroundStyle(PlazaPostStyle.text).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                            if !note.drawing.isEmpty {
                                InkCanvas(strokes: note.drawing).frame(width: 280, height: 280).border(.black.opacity(0.06)).accessibilityLabel(note.drawingDescription)
                                Text(note.drawingDescription).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button {
                                    model.mutate { doc in if let i = doc.notes.firstIndex(where: { $0.id == note.id }) { doc.notes[i].acknowledged.toggle() } }
                                } label: { Label(note.acknowledged ? "Appreciated" : "Appreciate", systemImage: note.acknowledged ? "heart.fill" : "heart") }.foregroundStyle(note.acknowledged ? Color.pink : PlazaStyle.teal)
                                Button("Reply (\((note.replies ?? []).count))") { replyTo=note }
                                Spacer()
                                if !note.drawing.isEmpty { Button("Export Drawing") { exportDrawing(note) } }
                                Button("Edit") { editing = note }
                                Button("Delete", role: .destructive) { deleted = note; model.mutate { $0.notes.removeAll { $0.id == note.id } } }
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
                            .overlay(alignment: .topLeading) { PlazaNameTab(name: note.author, large: true).padding(.leading, 18).offset(y: -9) }
                            .padding(.top, 9).id(note.id)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Plaza Guide", systemImage: "sparkle").font(.caption).foregroundStyle(PlazaStyle.teal)
                        Text("This is your offline plaza. The visitors are decorative local characters, and your journal is private to this Mac.").font(.callout).foregroundStyle(.secondary)
                    }.padding(18)
                }.padding(.horizontal, 18).padding(.bottom, 18)
              }.background(PlazaStyle.paper)
               .onAppear { if let id = model.selectedNoteID { scrollProxy.scrollTo(id, anchor: .top) } }
            }
            if let deleted {
                HStack { Text("Note deleted.").font(.caption); Spacer(); Button("Undo") { model.mutate { $0.notes.insert(deleted, at: 0) }; self.deleted = nil } }.padding(12)
            }
        }.frame(width: 660, height: 670).background(PlazaStyle.paper)
            .sheet(isPresented: $composing) { NoteComposer(model: model) }
            .sheet(item: $editing) { note in NoteComposer(model: model, existing: note) }
            .sheet(item:$replyTo) { note in ReplyComposer(model:model,noteID:note.id) }
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
    @Environment(\.dismiss) private var dismiss
    @State private var text=""
    @State private var authorID=UUID()
    var body: some View {
        VStack(spacing:0) {
            SheetHeader(title:"A local reply",subtitle:"A conversation between your characters, saved on this Mac.") { dismiss() }
            VStack(alignment:.leading,spacing:15) {
                Picker("Character",selection:$authorID) { ForEach(model.document.avatars) { Text($0.name).tag($0.id) } }
                TextEditor(text:$text).font(.body).scrollContentBackground(.hidden).frame(height:130).padding(14).modifier(PlazaPostSurface()).accessibilityLabel("Reply text").onChange(of:text) { _,s in if s.count>280 { text=String(s.prefix(280)) } }
                HStack { Text("\(text.count) / 280").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Save Reply") {
                    guard let a=model.document.avatars.first(where:{$0.id==authorID}) else { return }
                    if model.mutate({ doc in if let i=doc.notes.firstIndex(where:{$0.id==noteID}) { if doc.notes[i].replies == nil { doc.notes[i].replies=[] }; doc.notes[i].replies?.append(LocalReply(authorID:a.id,author:a.name,text:text.trimmingCharacters(in:.whitespacesAndNewlines))) } }) { dismiss() }
                }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal).keyboardShortcut(.defaultAction).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || (model.document.notes.first(where:{$0.id==noteID})?.replies?.count ?? 0)>=50) }
            }.padding(20)
        }.frame(width:540).onAppear { authorID=model.document.primaryAvatar.id }
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

import SwiftUI
import PlazaCore
import UniformTypeIdentifiers

enum FeatureTab: String, CaseIterable {
    case face="Face", hair="Hair", brows="Brows", eyes="Eyes", nose="Nose", mouth="Mouth", glasses="Glasses", facialHair="Mustache", beard="Beard", mole="Mole", body="Body", profile="Profile"
    static let main: [FeatureTab] = [.face,.hair,.brows,.eyes,.nose,.mouth,.glasses,.body]
    static let accessories: [FeatureTab] = [.glasses,.facialHair,.beard,.mole]
    var symbol: MiiFeatureIcon.Kind { switch self {
        case .face:return .face;case .hair:return .hair;case .brows:return .brows;case .eyes:return .eyes
        case .nose:return .nose;case .mouth:return .mouth;case .glasses:return .accessories
        case .facialHair:return .mustache;case .beard:return .beard;case .mole:return .mole;case .body,.profile:return .body
    } }
    var count: Int { switch self { case .face:return 12;case .hair:return 132;case .eyes:return 60;case .brows:return 24;case .nose:return 18;case .mouth:return 36;case .glasses:return 9;case .facialHair,.beard:return 6;default:return 0 } }
    var adjustments: [String] { switch self {
        case .eyes,.brows:return ["Vertical position","Spacing","Rotation","Size","Stretch"]
        case .nose,.mouth,.glasses,.facialHair:return self == .mouth ? ["Vertical position","Size","Stretch"]:["Vertical position","Size"]
        case .mole:return ["Vertical position","Horizontal position","Size"]
        default:return []
    } }
}

struct CharacterEditor: View {
    @ObservedObject var model: PlazaModel
    var initialID: UUID?
    var initialAvatar: Avatar?
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var avatar=Avatar()
    @State private var tab: FeatureTab = .face
    @State private var page=0
    @State private var faceSection=0
    @State private var adjustment="Vertical position"
    @State private var angle: CGFloat=0
    @State private var dragAngle: CGFloat=0
    @State private var pose=0
    @State private var history:[Avatar]=[]
    @State private var isNew=false
    @State private var message=""
    @State private var suppressHistory=true
    var body: some View {
        VStack(spacing:0) {
            categoryBar
            HStack(alignment:.top,spacing:26) {
                preview.frame(width:300)
                featurePanel.frame(maxWidth:.infinity)
            }.padding(.horizontal,28).padding(.top,22).frame(maxHeight:.infinity)
            editorFooter
        }
        .frame(width:960,height:760)
        .background(MakerBackground())
        .foregroundStyle(MiiEditorStyle.ink)
        .preferredColorScheme(.light)
        .onAppear {
            model.makerEditorVisible=true;model.updateAudio()
            suppressHistory=true;history.removeAll()
            avatar=initialAvatar ?? model.document.avatars.first(where:{$0.id==initialID}) ?? model.document.primaryAvatar
            isNew=initialAvatar != nil
        }
        .onDisappear {model.makerEditorVisible=false;model.updateAudio()}
        .onChange(of:avatar) {old,_ in
            if suppressHistory {suppressHistory=false} else {history.append(old);if history.count>100 {history.removeFirst()}}
        }
        .onChange(of:tab) {_,_ in
            let index=tab == .hair ? HairGeometry.displayOrder.firstIndex(of:avatar.hair) ?? 0:selection.wrappedValue
            page=tab.count>0 ? min((tab.count-1)/12,index/12):0
            adjustment=tab.adjustments.first ?? "Size"
        }
    }
    private var categoryBar: some View {
        HStack(spacing:0) {
            HStack(spacing:0) {
                ForEach(FeatureTab.main,id:\.self) {item in
                    let selected=tab==item || (item == .glasses && FeatureTab.accessories.contains(tab)) || (item == .body && tab == .profile)
                    PlazaButton {tab=item} label: {
                        MiiFeatureIcon(kind:item.symbol).frame(width:44,height:44)
                            .foregroundStyle(selected ? MiiEditorStyle.darkGreen:.white)
                            .frame(maxWidth:.infinity).frame(height:74)
                            .background(selected ? .white.opacity(0.25):.clear)
                            .overlay(alignment:.bottom) {if selected {Capsule().fill(.white.opacity(0.95)).frame(height:4).padding(.horizontal,13)}}
                            .overlay(alignment:.trailing) {Rectangle().fill(MiiEditorStyle.darkGreen.opacity(0.22)).frame(width:1)}
                    }.buttonStyle(.plain).help(item == .glasses ? "Glasses, facial hair & mole":item.rawValue)
                        .accessibilityLabel("\(item.rawValue) category").accessibilityAddTraits(selected ? .isSelected:[])
                }
            }
            .background(LinearGradient(colors:[Color(red:0.78,green:0.94,blue:0.36),Color(red:0.48,green:0.73,blue:0.18)],startPoint:.top,endPoint:.bottom))
            .clipShape(RoundedRectangle(cornerRadius:22))
            .overlay(RoundedRectangle(cornerRadius:22).strokeBorder(.white.opacity(0.7),lineWidth:2))
            .shadow(color:MiiEditorStyle.green.opacity(0.20),radius:2,y:3)
            PlazaButton(action:exportPortrait) {MiiFeatureIcon(kind:.camera).frame(width:42,height:42).foregroundStyle(MiiEditorStyle.green).frame(width:92,height:74)}
                .buttonStyle(MiiControlStyle()).padding(.leading,12).help("Export a portrait PNG").accessibilityLabel("Export Portrait PNG")
                .disabled(model.document.preferences.safeMode)
        }.padding(.horizontal,20).padding(.top,14)
    }
    private var preview: some View {
        VStack(spacing:12) {
            HStack {Text(avatar.name).font(.system(size:23,weight:.medium,design:.rounded)).lineLimit(1);Spacer()}
                .padding(.top,4)
            ZStack(alignment:.bottom) {
                Ellipse().fill(.white.opacity(0.8)).frame(width:235,height:34).padding(.bottom,12)
                if model.document.preferences.safeMode {OptionPortrait(avatar:avatar,hair:true).frame(width:245,height:310)}
                else {CharacterPreview(avatar:avatar,angle:angle,pose:pose).frame(height:380)
                    .gesture(DragGesture().onChanged {value in angle=dragAngle+CGFloat(value.translation.width)*0.015}.onEnded {_ in dragAngle=angle})}
            }.frame(height:380)
            HStack(spacing:12) {
                PlazaButton {angle -= .pi/4;dragAngle=angle} label:{Image(systemName:"arrow.counterclockwise").frame(width:52,height:38)}.accessibilityLabel("Rotate Mii left")
                PlazaButton {angle=0;dragAngle=0} label:{Text("Front").frame(width:70,height:38)}
                PlazaButton {angle += .pi/4;dragAngle=angle} label:{Image(systemName:"arrow.clockwise").frame(width:52,height:38)}.accessibilityLabel("Rotate Mii right")
            }.buttonStyle(MiiControlStyle()).font(.system(size:14,weight:.medium))
            Text("Drag your Mii to turn").font(.system(size:11)).foregroundStyle(.secondary)
            HStack {
                Picker("Pose",selection:$pose) {Text("Stand").tag(0);Text("Walk").tag(1);Text("Wave").tag(3);Text("Celebrate").tag(4);Text("React").tag(5)}.frame(width:145)
                Menu("More") {
                    Menu("Presets") {ForEach(0..<4) {i in PlazaButton(["Classic","Friendly","Thoughtful","Creative"][i]) {preset(i)}}}
                    PlazaButton("Shuffle") {shuffle()}
                    PlazaButton("Reset") {let id=avatar.id;avatar=Avatar(name:avatar.name);avatar.id=id}
                    Divider()
                    Menu("Saved Miis") {ForEach(model.document.avatars) {saved in PlazaButton(saved.name) {suppressHistory=true;avatar=saved;isNew=false;history.removeAll();message="";page=0}}}
                    PlazaButton("New Mii") {suppressHistory=true;avatar=Avatar(name:"New Mii",outfit:0);isNew=true;history.removeAll()}.disabled(model.document.avatars.count>=PlazaDocument.maximumCustomMiis)
                }.menuStyle(.borderlessButton).frame(width:80)
            }.font(.system(size:12))
        }
    }
    private var featurePanel: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text(tab == .profile ? "Mii information":tab.rawValue).font(.system(size:22,weight:.medium,design:.rounded))
                Spacer()
                if optionCount>12 {
                    PlazaButton {page=max(0,page-1)} label:{Image(systemName:"chevron.left").frame(width:38,height:32)}.disabled(page==0).accessibilityLabel("Previous feature page")
                    Text("\(page+1) / \((optionCount+11)/12)").font(.system(size:14)).monospacedDigit()
                    PlazaButton {page=min((optionCount-1)/12,page+1)} label:{Image(systemName:"chevron.right").frame(width:38,height:32)}.disabled((page+1)*12>=optionCount).accessibilityLabel("Next feature page")
                }
            }.buttonStyle(MiiControlStyle()).frame(height:34)
            if tab == .face {faceTabs}
            else if FeatureTab.accessories.contains(tab) {accessoryTabs}
            if tab == .body {
                HStack(alignment:.top,spacing:18) {bodyControls;palette}
            } else if tab == .profile {
                ScrollView {controls.padding(20)}.background(.white.opacity(0.65),in:RoundedRectangle(cornerRadius:20))
            } else {
                HStack(alignment:.top,spacing:14) {
                    if !tab.adjustments.isEmpty {adjustmentRail}
                    if optionCount>0 {catalog.frame(maxWidth:.infinity)}
                    else {MiiFeatureIcon(kind:.mole).frame(width:145,height:200).foregroundStyle(MiiEditorStyle.darkGreen).frame(maxWidth:.infinity)}
                    palette
                }
                ScrollView {controls.padding(.vertical,8)}.frame(maxHeight:155)
            }
        }
    }
    private var faceTabs: some View {
        HStack(spacing:8) {
            ForEach(0..<3) {index in
                PlazaButton {faceSection=index;page=0} label: {
                    HStack(spacing:6) {MiiFeatureIcon(kind:[.face,.makeup,.wrinkles][index]).frame(width:25,height:25);Text(["Shape","Makeup","Wrinkles"][index]).font(.system(size:12,weight:.medium))}.frame(maxWidth:.infinity).frame(height:39)
                }.buttonStyle(MiiControlStyle(selected:faceSection==index)).accessibilityLabel(["Face shapes","Face makeup","Face wrinkles"][index])
            }
        }
    }
    private var accessoryTabs: some View {
        HStack(spacing:8) {
            ForEach(FeatureTab.accessories,id:\.self) {item in
                PlazaButton {tab=item} label: {
                    VStack(spacing:2) {MiiFeatureIcon(kind:item.symbol).frame(width:28,height:28);Text(item.rawValue).font(.system(size:10))}.frame(maxWidth:.infinity).frame(height:47)
                }.buttonStyle(MiiControlStyle(selected:tab==item)).accessibilityLabel("\(item.rawValue) category")
            }
        }
    }
    private var adjustmentRail: some View {
        VStack(spacing:6) {
            ForEach(tab.adjustments,id:\.self) {title in
                PlazaButton {adjustment=title} label: {Image(systemName:adjustmentIcon(title)).font(.system(size:22,weight:.semibold)).frame(width:51,height:51)}
                    .buttonStyle(MiiControlStyle(selected:adjustment==title)).accessibilityLabel("Adjust \(title)").help(title)
            }
        }.padding(6).background(LinearGradient(colors:[MiiEditorStyle.lime,.yellow.opacity(0.48)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:16))
    }
    private func adjustmentIcon(_ title:String)->String {
        switch title {case "Vertical position":return "arrow.up.arrow.down";case "Horizontal position","Spacing":return "arrow.left.arrow.right";case "Rotation":return "arrow.clockwise";case "Stretch":return "arrow.up.and.down.square";default:return "arrow.up.left.and.arrow.down.right"}
    }
    @ViewBuilder private var palette: some View {
        if let colors=colorPalette {
            VStack(spacing:12) {
                LazyVGrid(columns:[GridItem(.fixed(34)),GridItem(.fixed(34))],spacing:10) {
                    ForEach(colors.values.indices,id:\.self) {i in
                        PlazaButton {colors.binding.wrappedValue=i} label:{RoundedRectangle(cornerRadius:6).fill(Color(nsColor:colors.values[i])).frame(width:34,height:34).padding(4)}
                            .buttonStyle(MiiControlStyle(selected:colors.binding.wrappedValue==i))
                            .accessibilityLabel("\(colors.title) \(i+1)").accessibilityAddTraits(colors.binding.wrappedValue==i ? .isSelected:[])
                    }
                }
                if tab == .hair {
                    PlazaButton {avatar.features.flipHair.toggle()} label:{Image(systemName:"arrow.left.and.right.righttriangle.left.righttriangle.right").font(.system(size:23)).frame(width:76,height:42)}
                        .buttonStyle(MiiControlStyle(selected:avatar.features.flipHair)).accessibilityLabel("Mirror hair")
                }
            }.frame(width:86).padding(.top,4)
        }
    }
    private var colorPalette:(title:String,values:[NSColor],binding:Binding<Int>)? {
        switch tab {
        case .face:return ("Skin",AvatarArtwork.skins,$avatar.skin)
        case .hair:return ("Hair color",AvatarArtwork.hairs,$avatar.hairColor)
        case .brows:return ("Brow color",AvatarArtwork.hairs,$avatar.features.browColor)
        case .eyes:return ("Eye color",AvatarArtwork.eyeColors,$avatar.features.eyeColor)
        case .mouth:return ("Lip color",AvatarArtwork.lipColors,$avatar.features.mouthColor)
        case .glasses:return ("Frame color",AvatarArtwork.glassColors,$avatar.features.glassesColor)
        case .facialHair,.beard:return ("Facial hair color",AvatarArtwork.hairs,$avatar.features.facialHairColor)
        case .body:return ("Favorite color",AvatarArtwork.outfits,$avatar.outfit)
        default:return nil
        }
    }
    private var bodyControls: some View {
        VStack(spacing:20) {
            bodySlider("Height",value:$avatar.height,short:true)
            bodySlider("Build",value:$avatar.build,short:false)
            Picker("Body",selection:$avatar.features.gender) {Text("Male").tag(0);Text("Female").tag(1)}.pickerStyle(.segmented).padding(.top,10)
        }
    }
    private func bodySlider(_ title:String,value:Binding<Double>,short:Bool)->some View {
        VStack(alignment:.leading,spacing:10) {
            Text(title).font(.system(size:14,weight:.medium))
            HStack(spacing:12) {
                MiiFeatureIcon(kind:.body).frame(width:35,height:short ? 45:60).scaleEffect(x:short ? 0.8:0.65,y:1)
                Slider(value:value,in:0...1).tint(MiiEditorStyle.green).accessibilityLabel(title)
                MiiFeatureIcon(kind:.body).frame(width:short ? 40:56,height:72).scaleEffect(x:short ? 1:1.3,y:1)
            }.frame(height:76).padding(12).background(.white.opacity(0.86),in:RoundedRectangle(cornerRadius:17))
                .overlay(RoundedRectangle(cornerRadius:17).strokeBorder(.white,lineWidth:2))
        }
    }
    private var editorFooter: some View {
        HStack(spacing:15) {
            PlazaButton(sound: .back, action:closeEditor) {Label("Cancel",systemImage:"arrow.uturn.backward").frame(width:126,height:47)}.keyboardShortcut(.cancelAction)
            PlazaButton {if let last=history.popLast() {suppressHistory=true;avatar=last}} label:{Image(systemName:"arrow.uturn.backward.circle").font(.system(size:22)).frame(width:47,height:47)}.disabled(history.isEmpty).accessibilityLabel("Undo Mii change")
            filesMenu.font(.system(size:14)).frame(width:80)
            Text(message).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
            if tab == .profile {
                PlazaButton {tab = .body} label:{Text("Back").frame(width:70,height:47)}
                if !isNew {PlazaButton {if save() {model.mutate {$0.primaryAvatarID=avatar.id};message="Primary Mii updated."}} label:{Text("Make Primary").font(.system(size:12)).frame(width:100,height:47)}}
            }
            PlazaButton {if tab == .profile {save()} else {tab = .profile}} label: {
                HStack(spacing:12) {Text(tab == .profile ? "Save Mii":"Next");Image(systemName:tab == .profile ? "checkmark":"arrow.right").font(.system(size:22,weight:.semibold))}.frame(width:155,height:47)
            }.keyboardShortcut(.defaultAction)
        }.buttonStyle(MiiControlStyle()).font(.system(size:17,weight:.medium,design:.rounded))
            .padding(.horizontal,24).padding(.vertical,18).background(.white.opacity(0.3))
    }
    private func closeEditor() {if let onClose {onClose()} else {dismiss()}}
    private var filesMenu: some View {
        Menu {
                    PlazaButton("Use Console Face Layout") {
                        avatar.eyeSpacing=2.0/12;avatar.featureHeight=0.5
                        avatar.features.eyeY=12.0/18;avatar.features.browY=7.0/15;avatar.features.browSpacing=2.0/12
                        avatar.features.noseY=9.0/18;avatar.features.mouthY=13.0/18
                        avatar.features.glassesY=10.0/20
                        message="Console face positions applied. Save Mii to keep them."
                    }
                    if !isNew && model.document.avatars.count>1 { PlazaButton("Delete Character",role:.destructive) { let id=avatar.id; model.mutate { $0.avatars.removeAll { $0.id==id }; if $0.primaryAvatarID==id { $0.primaryAvatarID=$0.avatars.first?.id } }; suppressHistory=true; avatar=model.document.primaryAvatar; model.rebuildScene() } }
                    PlazaButton("Import Mii or Character JSON…") { importCharacter() }
                    PlazaButton("Export Wii U / 3DS Mii…") { exportCharacter(binary:true) }
                    PlazaButton("Export Character JSON…") { exportCharacter(binary:false) }
                    PlazaButton("Export Portrait PNG…") { exportPortrait() }
                } label:{Text("Files").frame(width:80,height:47)}
                .menuStyle(.borderlessButton)
    }
    private var selection: Binding<Int> {
        switch tab {
        case .face:return faceSection == 1 ? $avatar.features.makeup:faceSection == 2 ? $avatar.features.wrinkles:$avatar.face; case .hair:return $avatar.hair; case .eyes:return $avatar.eyes; case .brows:return $avatar.brows; case .nose:return $avatar.nose; case .mouth:return $avatar.mouth
        case .glasses:return Binding(get:{avatar.glasses ? avatar.features.glassesType:0},set:{avatar.glasses=$0>0; avatar.features.glassesType=$0})
        case .facialHair:return $avatar.features.mustache
        case .beard:return Binding(get:{avatar.beard ? avatar.features.beardType:0},set:{avatar.beard=$0>0;avatar.features.beardType=$0})
        default:return $avatar.face
        }
    }
    private var optionCount:Int {tab.count}
    private var shownOptions:[Int] {
        let ids=tab == .hair ? HairGeometry.displayOrder:Array(0..<tab.count)
        let start=min(max(0,page),max(0,(ids.count-1)/12))*12
        return Array(ids[start..<min(ids.count,start+12)])
    }
    private var catalog: some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
            ForEach(shownOptions,id:\.self) { index in
                PlazaButton { selection.wrappedValue=index } label: {
                    FeatureThumbnail(avatar:option(index),safe:model.document.preferences.safeMode,feature:MiiTileFeature(tab:tab)).frame(height:64).padding(3).frame(maxWidth:.infinity)
                }.buttonStyle(MiiControlStyle(selected:selection.wrappedValue==index)).accessibilityLabel("\(tab.rawValue) style \(index+1)").accessibilityAddTraits(selection.wrappedValue==index ? .isSelected:[])
            }
        }
    }
    private func option(_ index: Int) -> Avatar { var a=avatar; switch tab { case .face:if faceSection == 1 {a.features.makeup=index} else if faceSection == 2 {a.features.wrinkles=index} else {a.face=index}; case .hair:a.hair=index; case .eyes:a.eyes=index; case .brows:a.brows=index; case .nose:a.nose=index; case .mouth:a.mouth=index; case .glasses:a.glasses=index>0;a.features.glassesType=index; case .facialHair:a.features.mustache=index; case .beard:a.beard=index>0;a.features.beardType=index; default:break }; return a }
    @ViewBuilder private var controls: some View {
        switch tab {
        case .face: slider("All features vertically",value:$avatar.featureHeight)
        case .hair: EmptyView()
        case .eyes: adjustments(size:$avatar.features.eyeSize,stretch:$avatar.features.eyeStretch,rotation:$avatar.features.eyeRotation,spacing:$avatar.eyeSpacing,y:$avatar.features.eyeY)
        case .brows: adjustments(size:$avatar.features.browSize,stretch:$avatar.features.browStretch,rotation:$avatar.features.browRotation,spacing:$avatar.features.browSpacing,y:$avatar.features.browY)
        case .nose: slider(adjustment,value:adjustment == "Size" ? $avatar.features.noseSize:$avatar.features.noseY)
        case .mouth: slider(adjustment,value:adjustment == "Size" ? $avatar.features.mouthSize:adjustment == "Stretch" ? $avatar.features.mouthStretch:$avatar.features.mouthY)
        case .glasses: slider(adjustment,value:adjustment == "Size" ? $avatar.features.glassesSize:$avatar.features.glassesY)
        case .facialHair: slider(adjustment,value:adjustment == "Size" ? $avatar.features.mustacheSize:$avatar.features.mustacheY)
        case .beard: EmptyView()
        case .mole:
            Toggle("Beauty mark",isOn:$avatar.features.mole).toggleStyle(.checkbox)
            slider(adjustment,value:adjustment == "Size" ? $avatar.features.moleSize:adjustment == "Horizontal position" ? $avatar.features.moleX:$avatar.features.moleY)
        case .body: EmptyView()
        case .profile:
            VStack(alignment:.leading,spacing:18) {
                Text("Nickname").font(.system(size:14,weight:.medium))
                TextField("Nickname",text:$avatar.name).textFieldStyle(.roundedBorder).accessibilityLabel("Character nickname").onChange(of:avatar.name) {_,s in if s.count>24 {avatar.name=String(s.prefix(24))}}
                Text("Creator").font(.system(size:14,weight:.medium))
                TextField("Creator",text:$avatar.features.creator).textFieldStyle(.roundedBorder).onChange(of:avatar.features.creator) {_,s in if s.count>24 {avatar.features.creator=String(s.prefix(24))}}
                HStack {Picker("Birth month",selection:$avatar.features.birthMonth) {Text("Unset").tag(0);ForEach(1..<13) {Text("\($0)").tag($0)}};Picker("Day",selection:$avatar.features.birthDay) {Text("Unset").tag(0);ForEach(1..<32) {Text("\($0)").tag($0)}}}
                Toggle("Favorite Mii",isOn:$avatar.features.favorite)
                Toggle("Allow copying in Mii file",isOn:$avatar.features.allowCopying)
                Toggle("Allow sharing in Mii file",isOn:$avatar.features.sharing)
                Text("Save Mii to keep your changes and return your creation to the plaza.").font(.system(size:12)).foregroundStyle(.secondary)
            }
        }
    }
    private func adjustments(size:Binding<Double>,stretch:Binding<Double>,rotation:Binding<Double>,spacing:Binding<Double>,y:Binding<Double>) -> some View {
        slider(adjustment,value:adjustment == "Size" ? size:adjustment == "Stretch" ? stretch:adjustment == "Rotation" ? rotation:adjustment == "Spacing" ? spacing:y)
    }
    private func slider(_ title:String,value:Binding<Double>) -> some View {
        VStack(alignment:.leading,spacing:10) {
            Text(title).font(.system(size:13,weight:.medium))
            HStack(spacing:14) {
                PlazaButton {value.wrappedValue=max(0,value.wrappedValue-0.05)} label:{Image(systemName:"minus").font(.system(size:18,weight:.semibold)).frame(width:44,height:40)}.accessibilityLabel("Decrease \(title)")
                Slider(value:value,in:0...1).tint(MiiEditorStyle.green).accessibilityLabel(title)
                PlazaButton {value.wrappedValue=min(1,value.wrappedValue+0.05)} label:{Image(systemName:"plus").font(.system(size:18,weight:.semibold)).frame(width:44,height:40)}.accessibilityLabel("Increase \(title)")
            }.buttonStyle(MiiControlStyle())
        }.padding(12).background(.white.opacity(0.65),in:RoundedRectangle(cornerRadius:16))
    }
    @discardableResult private func save() -> Bool {
        do { _=try avatar.validated() } catch { message=error.localizedDescription; return false }
        guard model.document.avatars.contains(where:{$0.id==avatar.id}) || model.document.avatars.count<PlazaDocument.maximumCustomMiis else { message="Your library is full. Choose a saved character to edit."; return false }
        let result=model.saveMii(avatar)
        if result { isNew=false; message="\(avatar.name) is saved in the plaza." }; return result
    }
    private func preset(_ index:Int) {
        let id=avatar.id,name=avatar.name; var a=Avatar(name:name,outfit:[0,6,4,8][index]); a.id=id
        a.hair=[33,12,44,28][index]; a.eyes=[2,0,8,24][index]; a.brows=[0,3,7,11][index]; a.mouth=[23,6,19,5][index]; a.face=[0,4,8,11][index]; a.skin=index%6; a.glasses=index==2; a.features.gender=index%2; avatar=a
    }
    private func shuffle() {
        avatar.skin=Int.random(in:0...5); avatar.face=Int.random(in:0...11); avatar.hair=Int.random(in:0...131); avatar.hairColor=Int.random(in:0...7)
        avatar.eyes=Int.random(in:0...59); avatar.brows=Int.random(in:0...23); avatar.nose=Int.random(in:0...17); avatar.mouth=Int.random(in:0...35); avatar.outfit=Int.random(in:0...11)
        avatar.height=Double.random(in:0...1); avatar.build=Double.random(in:0...1); avatar.glasses=Int.random(in:0...4)==0; avatar.beard=Int.random(in:0...7)==0
    }
    private func importCharacter() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.json,UTType(filenameExtension:"mii") ?? .data,UTType(filenameExtension:"ffsd") ?? .data]; panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do { guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<100_000 else { throw PlazaError.invalid("Character files must be smaller than 100 KB.") }; let data=try Data(contentsOf:url); var imported:Avatar
            if url.pathExtension.lowercased()=="json" { imported=try JSONDecoder().decode(Avatar.self,from:data).validated() } else { imported=try MiiFile.decode(data) }
            imported.id=UUID(); suppressHistory=true; avatar=imported; isNew=true; message="Imported. Save Mii to add it to the plaza."; history.removeAll()
        } catch { message=error.localizedDescription }
    }
    private func exportPortrait() {
        guard !model.document.preferences.safeMode else { message="Turn off safe mode to export a 3D portrait."; return }
        Task {
        let image:NSImage
        do {if FFLResources.shared.installed {image=try await FFLPortraits.shared.image(avatar,angle:angle,pose:pose,width:512,height:768)} else {image=AvatarArtwork.image(avatar,direction:Int((angle / (.pi/4)).rounded()) % 8 + 8,size:CGSize(width:512,height:768),pose:pose)}} catch {message=error.localizedDescription;return}
        guard let tiff=image.tiffRepresentation,let png=NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) else { message="The portrait could not be created."; return }
        let panel=NSSavePanel(); panel.allowedContentTypes=[.png]; panel.nameFieldStringValue=avatar.name+" Portrait.png"
        guard panel.runModal() == .OK,let url=panel.url else { return }; do { try png.write(to:url,options:.atomic); message="Portrait exported." } catch { message=error.localizedDescription }
        }
    }
    private func exportCharacter(binary:Bool) {
        do { let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]; let data=binary ? try MiiFile.encode(avatar):try encoder.encode(avatar.validated())
            let panel=NSSavePanel(); panel.allowedContentTypes=binary ? [UTType(filenameExtension:"mii") ?? .data]:[.json]; panel.nameFieldStringValue=avatar.name+(binary ? ".mii":".json")
            if panel.runModal() == .OK,let url=panel.url { try data.write(to:url,options:.atomic); message="Character exported." }
        } catch { message=error.localizedDescription }
    }
}

private struct OptionPortrait: View {
    let avatar: Avatar
    let hair: Bool
    var body: some View {
        GeometryReader { g in
            let width=g.size.width*0.73, height=g.size.height*0.93
            ZStack {
                FaceSilhouette(style:avatar.face).fill(Color(nsColor:AvatarArtwork.skins[avatar.skin])).frame(width:width*(0.88+Double(avatar.face%4)*0.06),height:height*(0.90+Double(avatar.face/4)*0.045))
                Image(nsImage:AvatarArtwork.face(avatar)).resizable().scaledToFit().frame(width:width*1.13,height:height*1.13)
                if hair && avatar.hair != 30 {
                    Canvas { c,s in
                        let family=avatar.hair%22,variant=avatar.hair/22
                        var p=Path(); p.move(to:CGPoint(x:s.width*0.11,y:s.height*0.48)); p.addQuadCurve(to:CGPoint(x:s.width*0.89,y:s.height*0.45),control:CGPoint(x:s.width*0.5,y:-s.height*0.27)); p.addLine(to:CGPoint(x:s.width*0.82,y:s.height*(0.22+Double(family%5)*0.025))); p.addQuadCurve(to:CGPoint(x:s.width*0.16,y:s.height*0.32),control:CGPoint(x:s.width*Double(2+variant)/9,y:s.height*Double(2+family%3)/8)); p.closeSubpath(); c.fill(p,with:.color(Color(nsColor:AvatarArtwork.hairs[avatar.hairColor])))
                        if [4,7,9,13,16,19].contains(family) { c.fill(Path(ellipseIn:CGRect(x:s.width*0.08,y:s.height*0.33,width:s.width*0.16,height:s.height*0.50)),with:.color(Color(nsColor:AvatarArtwork.hairs[avatar.hairColor]))) }
                    }
                }
                Ellipse().fill(Color(nsColor:AvatarArtwork.skins[avatar.skin]).shadow(.drop(color:.black.opacity(0.18),radius:1,x:1,y:1))).frame(width:3+Double(avatar.nose%3)*1.4,height:4+Double(avatar.nose/3)*0.7).offset(y:3)

            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
    private var number: Int { avatar.face+1 }
}

struct SheetHeader: View {
    let title:String; let subtitle:String
    var backToPlaza:(()->Void)? = nil
    let close:()->Void
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            if let backToPlaza {
                PlazaButton(sound: .back, action:backToPlaza) { Label("Back to Plaza",systemImage:"chevron.left") }
                    .buttonStyle(.plain).font(.system(size:13,weight:.semibold))
                    .foregroundStyle(PlazaStyle.teal)
            }
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(.system(size:22,weight:.semibold,design:.rounded))
                    Text(subtitle).font(.system(size:12)).foregroundStyle(.secondary)
                }
                Spacer()
                PlazaButton(sound: .back, action:close) {
                    Image(systemName:"xmark").font(.system(size:12,weight:.semibold))
                        .padding(8).background(.black.opacity(0.05),in:Circle())
                }.buttonStyle(.plain).keyboardShortcut(.cancelAction).help("Close").accessibilityLabel("Close")
            }
        }.padding(20).background(PlazaStyle.paper)
    }
}

private struct FaceSilhouette: Shape {
    let style:Int
    func path(in r:CGRect) -> Path {
        let jaw=0.12+Double(style%4)*0.035
        var p=Path(); p.move(to:CGPoint(x:r.midX,y:r.minY))
        p.addCurve(to:CGPoint(x:r.maxX,y:r.height*0.44),control1:CGPoint(x:r.width*0.84,y:0),control2:CGPoint(x:r.maxX,y:r.height*0.18))
        p.addCurve(to:CGPoint(x:r.midX,y:r.maxY),control1:CGPoint(x:r.maxX,y:r.height*0.76),control2:CGPoint(x:r.width*(0.84-jaw),y:r.maxY))
        p.addCurve(to:CGPoint(x:0,y:r.height*0.44),control1:CGPoint(x:r.width*(0.16+jaw),y:r.maxY),control2:CGPoint(x:0,y:r.height*0.76))
        p.addCurve(to:CGPoint(x:r.midX,y:0),control1:CGPoint(x:0,y:r.height*0.18),control2:CGPoint(x:r.width*0.16,y:0)); p.closeSubpath(); return p
    }
}

private struct FeatureThumbnail: View {
    let avatar:Avatar
    let safe:Bool
    var feature:MiiTileFeature?
    @State private var rendered:NSImage?
    @ObservedObject private var resource=FFLResources.shared
    var body:some View {
        Group {
            if !safe,let rendered {Image(nsImage:rendered).resizable().scaledToFit()}
            else if resource.installed && !safe {ProgressView().controlSize(.small)}
            else if let feature {Image(nsImage:feature.fallback(sample)).resizable().scaledToFit()}
            else {OptionPortrait(avatar:avatar,hair:true)}
        }.accessibilityHidden(true).task(id:String(describing:sample)+(feature?.rawValue ?? "head")+resource.revision.uuidString+String(safe)) {
            rendered=nil
            guard !safe else {return}
            await Task.yield();guard !Task.isCancelled else {return}
            let image:NSImage?
            if resource.installed {image=try? await FFLPortraits.shared.image(sample,headOnly:true,width:feature == nil ? 96:144,feature:feature)}
            else {image=feature?.fallback(sample) ?? AvatarArtwork.headshot(avatar)}
            guard !Task.isCancelled else {return}
            rendered=image ?? feature?.fallback(sample)
        }
    }
    private var sample:Avatar {feature?.sample(from:avatar) ?? avatar}
}

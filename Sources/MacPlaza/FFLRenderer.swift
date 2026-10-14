import AppKit
import SwiftUI
import WebKit
import CryptoKit
import PlazaCore

/// Resource bytes and character data only cross an in-process WebKit bridge.
/// The renderer has no HTTP listener and no permitted network destinations.
@MainActor
final class FFLResources: ObservableObject {
    static let shared = FFLResources()
    @Published private(set) var installed: Bool
    @Published private(set) var revision = UUID()
    @Published var message: String
    @Published private(set) var importing = false
    let url: URL
    private var validator: FFLSurface?
    init(directory: URL? = nil) {
        let base = directory ?? PlazaDataLocation.root.appendingPathComponent("Renderer")
        url=base.appendingPathComponent("FFLResHigh.dat")
        let exists=FileManager.default.fileExists(atPath:url.path)
        installed=exists
        let info=(try? String(contentsOf:base.appendingPathComponent("resource-info.txt"),encoding:.utf8)) ?? ""
        message=exists ? (info.contains("AFLRes") ? "Miitomo resource installed locally with the Wii U shader. Import Wii U FFLResHigh.dat for the original Wii U assets.":"Local FFL resource installed. Wii U FFL shader enabled.") : "Original face and hair resources required. The plaza currently uses the built-in approximation."
    }
    static func checkedData(at url:URL) throws -> Data {
        let size=try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
        guard size.isRegularFile == true,let count=size.fileSize,count>=1024,count<=64*1024*1024 else {throw FFLError.message("Choose an uncompressed FFLResHigh.dat resource (1 KB–64 MB).")}
        let data=try Data(contentsOf:url,options:.mappedIfSafe)
        guard data.prefix(4)==Data("FFRA".utf8) else{throw FFLError.message("This is not an uncompressed FFL high-resolution resource (FFRA header missing).")}
        return data
    }
    func reloadInstalled() {
        installed = (try? Self.checkedData(at: url)) != nil
        message = installed ? "Local FFL resource validated and installed. Wii U FFL shader enabled." : "Original face and hair resources required."
        revision = UUID(); FFLPortraits.shared.reset(); AvatarArtwork.clearCaches()
    }
    func importResource() {
        let panel=NSOpenPanel();panel.title="Import Wii U Mii resources";panel.message="Choose FFLResHigh.dat from your Wii U. It stays on this Mac.";panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let selected=panel.url else{return}
        Task { await install(selected) }
    }
    func install(_ selected:URL) async {
        guard !importing else{return};importing=true;defer{importing=false;validator=nil}
        do {
            let data=try Self.checkedData(at:selected)
            message="Checking resource with FFL and rendering a test Mii…"
            let surface=FFLSurface(mode:"portrait",resource:data,useInstalledBody:false);validator=surface
            try await surface.waitUntilReady()
            _=try await surface.portrait(Avatar(name:"Resource test"),headOnly:true,width:96,height:96)
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:url,options:.atomic)
            let checksum=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
            let info="Imported: \(selected.lastPathComponent)\nSHA-256: \(checksum)\n"
            try? Data(info.utf8).write(to:url.deletingLastPathComponent().appendingPathComponent("resource-info.txt"),options:.atomic)
            installed=true;revision=UUID();FFLPortraits.shared.reset();AvatarArtwork.clearCaches()
            message=selected.lastPathComponent.hasPrefix("AFL") ? "Miitomo resource installed locally with the Wii U shader. Import Wii U FFLResHigh.dat for the original Wii U assets." : "Local FFL resource validated and installed. Wii U FFL shader enabled."
        } catch { message="Resource was not installed: \(error.localizedDescription)" }
    }
    func remove() {
        do { if FileManager.default.fileExists(atPath:url.path){try FileManager.default.removeItem(at:url)};installed=false;revision=UUID();FFLPortraits.shared.reset();message="Resource removed. Using the built-in approximation." }
        catch {message=error.localizedDescription}
    }
}

enum FFLError: LocalizedError {case message(String);var errorDescription:String?{if case .message(let value)=self{return value};return nil}}

/// A fixed local document. File reads are restricted to its bundled asset directory;
/// CSP denies connections, and navigation cannot leave this document.
@MainActor
final class FFLSurface: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private static let localDataStore=WKWebsiteDataStore.nonPersistent()
    let webView: WKWebView
    let mode: String
    private let resource:Data?
    private let bodyResource:Data?
    private var ready=false
    private var failure:String?
    private var loaded=false
    private var requestID=0
    private var replies:[Int:(Result<Any,Error>)->Void]=[:]
    private var deadlines:[Int:Task<Void,Never>]=[:]
    var onReady:(()->Void)?
    var onResize:((CGSize)->Void)?
    var onSelect:((Int)->Void)?
    var onNoteAnchors: (([[Double]]) -> Void)?
    private var noteTargets: [Int] = []
    func setNoteTargets(_ indices: [Int]) {
        noteTargets = Array(indices.prefix(6))
        if ready { invoke("setNoteTargets", [noteTargets]) }
    }
    var onFailure:((String)->Void)?
    private var frameBusy=false
    private var pendingFrame:(values:[[Double]],identities:[String])?
    private var frameIdentities:[String]=[]
    init(mode:String,resource:Data?=nil,bodyResource:Data?=nil,useInstalledBody:Bool=true) {
        self.mode=mode;self.resource=resource;self.bodyResource=bodyResource ?? (useInstalledBody ? PlazaBodyResources.shared.data:nil)
        let config=WKWebViewConfiguration();config.websiteDataStore = Self.localDataStore
        // Disable WebKit's network-capable content features. Only local scripts run.
        config.preferences.javaScriptCanOpenWindowsAutomatically=false
        webView=FFLWebView(frame:NSRect(x:0,y:0,width:512,height:768),configuration:config)
        super.init()
        config.userContentController.add(WeakFFLHandler(self),name:"ffl")
        (webView as? FFLWebView)?.onResize={[weak self] in self?.onResize?($0)}
        webView.navigationDelegate=self;webView.setValue(false,forKey:"drawsBackground")
        webView.setAccessibilityElement(false)
        let root=Self.assetRoot
        webView.loadFileURL(root.appendingPathComponent("index.html"),allowingReadAccessTo:root)
    }
    static var assetRoot:URL {
        PlazaResources.url(for: "index", extension: "html", directory: "FFL")?.deletingLastPathComponent()
            ?? (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("FFL")
    }
    static func avatar(_ a:Avatar) throws -> [String:Any] {
        var rendering=a
        // Nicknames do not affect appearance; local names may exceed the console's limit.
        rendering.name="Mii";rendering.features.creator=""
        let shift=(a.featureHeight-0.5)*0.25
        rendering.features.eyeY=min(1,max(0,a.features.eyeY+shift))
        rendering.features.browY=min(1,max(0,a.features.browY+shift))
        rendering.features.noseY=min(1,max(0,a.features.noseY+shift))
        rendering.features.mouthY=min(1,max(0,a.features.mouthY+shift))
        return ["id":a.id.uuidString,"data":try MiiFile.encode(rendering).base64EncodedString(),"height":a.height,"build":a.build,"outfit":a.outfit,"gender":a.features.gender]
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame,let body=message.body as? [String:Any],let type=body["type"] as? String else{return}
        switch type {
        case "loaded":
            guard !loaded else{return};loaded=true
            do {
                let data=try resource ?? FFLResources.checkedData(at:FFLResources.shared.url)
                let root=Self.assetRoot
                let wasm=try Data(contentsOf:root.appendingPathComponent("vendor/ffl-emscripten.wasm"))
                invoke("initialize",[data.base64EncodedString(),wasm.base64EncodedString(),mode,bodyResource?.base64EncodedString() as Any? ?? NSNull()])
            } catch { fail(error.localizedDescription) }
        case "ready": ready=true;if mode == "plaza" {invoke("setRenderScale",[plazaRenderScale])};setNoteTargets(noteTargets);onReady?();if pendingFrame != nil{sendFrame()}
        case "noteAnchors": if let values = body["value"] as? [[Double]] { onNoteAnchors?(values) }
        case "select":if let i=body["value"] as? Int{onSelect?(i)}
        case "reply":
            guard let value=body["value"] as? [String:Any],let id=value["id"] as? Int,let callback=replies.removeValue(forKey:id) else{return}
            deadlines.removeValue(forKey:id)?.cancel()
            if let error=value["error"] as? String{callback(.failure(FFLError.message(error)))}else{callback(.success(value["value"] ?? NSNull()))}
        case "error":fail(body["value"] as? String ?? "Unknown FFL error")
        default:break
        }
    }
    private func fail(_ message:String){
        failure=message;onFailure?(message)
        let callbacks=Array(replies.values);replies.removeAll();deadlines.values.forEach{$0.cancel()};deadlines.removeAll()
        callbacks.forEach{$0(.failure(FFLError.message(message)))}
    }
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView){fail("The local graphics process stopped. Reopen the plaza or use safe mode.")}
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        let expected=Self.assetRoot.appendingPathComponent("index.html").standardizedFileURL
        decisionHandler(navigationAction.request.url?.standardizedFileURL == expected ? .allow:.cancel)
    }
    func invalidate(){
        onFailure=nil;fail("Renderer closed.");ready=false
        if loaded{webView.evaluateJavaScript("window.plazaFFL?.dispose();null",completionHandler:nil)}
        webView.stopLoading()
    }
    func waitUntilReady() async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+20
        while !ready {
            if let failure{throw FFLError.message(failure)}
            guard ProcessInfo.processInfo.systemUptime<deadline else{throw FFLError.message("The local FFL renderer did not start within 20 seconds.")}
            try await Task.sleep(nanoseconds:20_000_000)
        }
    }
    private func request(_ method:String,_ args:[Any],completion:@escaping(Result<Any,Error>)->Void) {
        do {
            let encoded=try JSONSerialization.data(withJSONObject:args,options:[.fragmentsAllowed])
            let json=String(decoding:encoded,as:UTF8.self)
            requestID += 1;let id=requestID;replies[id]=completion
            webView.evaluateJavaScript("window.plazaFFL.dispatch(\(id),'\(method)',\(json));null") { [weak self] _,error in
                if let error{self?.deadlines.removeValue(forKey:id)?.cancel();self?.replies.removeValue(forKey:id)?(.failure(error))}
            }
            deadlines[id]=Task { [weak self] in
                do{try await Task.sleep(nanoseconds:20_000_000_000)}catch{return}
                self?.deadlines.removeValue(forKey:id)
                self?.replies.removeValue(forKey:id)?(.failure(FFLError.message("Local FFL operation timed out.")))
            }
        } catch{completion(.failure(error))}
    }
    func invoke(_ method:String,_ args:[Any],completion:((Error?)->Void)?=nil) {
        request(method,args){[weak self] result in
            if case .failure(let error)=result{self?.fail(error.localizedDescription);completion?(error)}else{completion?(nil)}
        }
    }
    var plazaRenderScale=1.0
    func identifyFrames(_ avatars:[Avatar]) {frameIdentities=avatars.map { $0.id.uuidString }}
    func configure(_ avatars:[Avatar],completion:((Error?)->Void)?=nil){do{
        let payload=try avatars.map(Self.avatar)
        frameIdentities=avatars.map { $0.id.uuidString }
        invoke("configure",[payload],completion:completion)
    }catch{fail(error.localizedDescription);completion?(error)}}
    func importMenu(_ data:Data) async throws->Data {
        try await waitUntilReady()
        let value:Any=try await withCheckedThrowingContinuation{c in request("importMenu",[data.base64EncodedString()]){c.resume(with:$0)}}
        guard let json=value as? String else{throw FFLError.message("The menu converter returned no body resource.")};return Data(json.utf8)
    }
    func preview(_ avatar:Avatar,angle:CGFloat,pose:Int) async throws {
        let args:[Any]=[try Self.avatar(avatar),Double(angle),pose,false]
        let _:Any=try await withCheckedThrowingContinuation{ continuation in request("preview",args){continuation.resume(with:$0)} }
    }
    func frame(_ values:[[Double]]) {
        pendingFrame=(values,frameIdentities);guard ready,!frameBusy else{return};sendFrame()
    }
    private func sendFrame(){guard let values=pendingFrame else{return};pendingFrame=nil;frameBusy=true
        // Pose rows contain numbers and a parallel list identifies their Miis.
        // Structured WebKit arguments
        // avoid NSNumber JSON formatting/parsing and a request/deadline task
        // for every display update. Keep one frame in flight and the newest
        // pending snapshot, including when the renderer is briefly busy.
        webView.callAsyncJavaScript("window.plazaFFL.frame(values, identities); return null;",
            arguments:["values":values.values,"identities":values.identities],in:nil,in:.page){[weak self] result in
            guard let self else{return};self.frameBusy=false
            if case .failure(let error)=result {self.pendingFrame=nil;self.fail(error.localizedDescription);return}
            if self.ready,self.pendingFrame != nil{self.sendFrame()}
        }
    }
    func portrait(_ avatar:Avatar,angle:CGFloat=0,pose:Int=0,headOnly:Bool=false,width:Int=512,height:Int=768,feature:MiiTileFeature?=nil) async throws -> NSImage {
        try await waitUntilReady()
        let args:[Any]=try feature.map { [try Self.avatar(avatar),$0.rawValue,width,height] } ?? [try Self.avatar(avatar),Double(angle),pose,headOnly,width,height]
        let value:Any = try await withCheckedThrowingContinuation { continuation in
            request(feature == nil ? "portrait" : "featureIcon",args){continuation.resume(with:$0)}
        }
        guard let encoded=value as? String,let payload=encoded.split(separator:",",maxSplits:1).last,let data=Data(base64Encoded:String(payload)),let image=NSImage(data:data) else{throw FFLError.message("FFL did not return a PNG portrait.")};return image
    }
}
private final class WeakFFLHandler:NSObject,WKScriptMessageHandler {
    weak var target:FFLSurface?
    init(_ target:FFLSurface){self.target=target}
    func userContentController(_ c:WKUserContentController,didReceive m:WKScriptMessage){target?.userContentController(c,didReceive:m)}
}

@MainActor
final class FFLPortraits {
    static let shared=FFLPortraits()
    private var surface:FFLSurface?
    private var busy=false
    private var idleRelease:Task<Void,Never>?
    private let cache:NSCache<NSString,NSImage> = {let c=NSCache<NSString,NSImage>();c.countLimit=192;c.totalCostLimit=12*1024*1024;return c}()
    func reset(){idleRelease?.cancel();surface?.invalidate();surface=nil;cache.removeAllObjects()}
    private func releaseWhenIdle(){
        idleRelease?.cancel()
        idleRelease=Task{[weak self] in
            do{try await Task.sleep(nanoseconds:3_000_000_000)}catch{return}
            guard let self,!self.busy else{return};self.surface?.invalidate();self.surface=nil
        }
    }
    func image(_ a:Avatar,headOnly:Bool=false,angle:CGFloat=0,pose:Int=0,width:Int=96,height:Int=96,feature:MiiTileFeature?=nil) async throws -> NSImage {
        let key=(String(describing:a)+"\(feature?.rawValue ?? "portrait")-\(headOnly)-\(angle)-\(pose)-\(width)x\(height)-\(FFLResources.shared.revision)-\(PlazaBodyResources.shared.revision)") as NSString
        if let cached=cache.object(forKey:key){return cached}
        while busy{try await Task.sleep(nanoseconds:15_000_000)}
        try Task.checkCancellation();if let cached=cache.object(forKey:key){return cached}
        idleRelease?.cancel();busy=true;defer{busy=false;releaseWhenIdle()}
        if surface==nil{surface=FFLSurface(mode:"portrait")}
        let image=try await surface!.portrait(a,angle:angle,pose:pose,headOnly:headOnly,width:width,height:height,feature:feature)
        if width*height<100_000{cache.setObject(image,forKey:key,cost:width*height*4)}
        return image
    }
}

struct FFLPreview:NSViewRepresentable {
    let avatar:Avatar
    var angle:CGFloat=0
    var pose:Int=0
    func makeCoordinator()->Coordinator{Coordinator()}
    func makeNSView(context:Context)->WKWebView{context.coordinator.surface.webView}
    func updateNSView(_ view:WKWebView,context:Context){let c=context.coordinator;c.avatar=avatar;c.angle=angle;c.pose=pose;c.update()}
    static func dismantleNSView(_ view:WKWebView,coordinator:Coordinator){coordinator.surface.invalidate()}
    @MainActor final class Coordinator {
        let surface=FFLSurface(mode:"preview")
        var avatar:Avatar?;var angle:CGFloat=0;var pose=0
        var busy=false;var needsUpdate=false
        init(){surface.onReady={[weak self] in self?.update()}}
        func update(){needsUpdate=true;guard !busy,let avatar else{return};busy=true;needsUpdate=false
            Task {do{try await surface.waitUntilReady();try await surface.preview(avatar,angle:angle,pose:pose)}catch{};busy=false;if needsUpdate{update()}}
        }
    }
}
struct CharacterPreview:View {
    let avatar:Avatar
    var angle:CGFloat=0
    var pose:Int=0
    @ObservedObject private var resource=FFLResources.shared
    @ObservedObject private var bodyResource=PlazaBodyResources.shared
    var body:some View {Group{if resource.installed{FFLPreview(avatar:avatar,angle:angle,pose:pose).id(resource.revision.uuidString+bodyResource.revision.uuidString)}else{LegacyCharacterPreview(avatar:avatar,angle:angle,pose:pose)}}}
}
struct AvatarPortrait:View {
    let avatar:Avatar
    @ObservedObject private var resource=FFLResources.shared
    @ObservedObject private var bodyResource=PlazaBodyResources.shared
    @State private var image:NSImage?
    var body:some View {Group{if let image{Image(nsImage:image).resizable().scaledToFit()}else{Image(systemName:"person.fill").resizable().scaledToFit()}}.task(id:String(describing:avatar)+resource.revision.uuidString+bodyResource.revision.uuidString){if resource.installed{image=try? await FFLPortraits.shared.image(avatar,width:96,height:128)}else{image=AvatarArtwork.image(avatar)}}}
}

struct SceneView:View {
    let scene:PlazaScene
    var moving:Bool
    var onSelect:(Avatar)->Void
    var renderScale:CGFloat=1
    @ObservedObject private var resource=FFLResources.shared
    @ObservedObject private var bodyResource=PlazaBodyResources.shared
    var body:some View {Group{if resource.installed{FFLSceneView(scene:scene,moving:moving,onSelect:onSelect,renderScale:renderScale).id(resource.revision.uuidString+bodyResource.revision.uuidString)}else{LegacySceneView(scene:scene,moving:moving,onSelect:onSelect,renderScale:renderScale)}}}
}
struct FFLSceneView:NSViewRepresentable {
    let scene:PlazaScene
    let moving:Bool
    let onSelect:(Avatar)->Void
    var renderScale:CGFloat=1
    func makeCoordinator()->Coordinator {scene.setRendererScale(renderScale);return Coordinator(scene,renderScale:renderScale)}
    func makeNSView(context:Context)->WKWebView{context.coordinator.surface.webView}
    func updateNSView(_ view:WKWebView,context:Context){scene.setRendererScale(renderScale);scene.onSelect=onSelect;scene.setMoving(moving);scene.resize(view.bounds.size)}
    static func dismantleNSView(_ view:WKWebView,coordinator:Coordinator){coordinator.scene.detachFFL(owner:coordinator.id);coordinator.surface.invalidate()}
    @MainActor final class Coordinator {
        let scene:PlazaScene
        let id=UUID()
        let surface=FFLSurface(mode:"plaza")
        init(_ scene:PlazaScene,renderScale:CGFloat){self.scene=scene
            surface.plazaRenderScale=Double(renderScale)
            scene.attachFFL(owner:id,frame:{[weak self] in self?.surface.frame($0)},configure:{[weak self] in self?.configure($0)})
            scene.fflNoteTargets = { [weak self] in self?.surface.setNoteTargets($0) }
            surface.setNoteTargets(scene.noteIndices)
            surface.onNoteAnchors = { [weak scene] in scene?.acceptFFLAnchors($0) }
            surface.onReady={[weak self] in guard let self else{return};self.configure(scene.fflCharacters)}
            surface.onSelect={[weak scene] in scene?.selectFFL($0)}
            surface.onResize={[weak scene] in scene?.resize($0)}
            surface.onFailure={message in FFLResources.shared.message="Local FFL renderer error: \(message)"}
        }
        private var configuring=false
        private var pending:[Avatar]?
        func configure(_ avatars:[Avatar]){surface.identifyFrames(avatars);pending=avatars;guard !configuring else{return};configuring=true
            Task {do{try await surface.waitUntilReady();sendConfiguration()}catch{configuring=false}}
        }
        func sendConfiguration(){guard let avatars=pending else{configuring=false;return};pending=nil
            surface.configure(avatars){[weak self] error in guard let self else{return};if self.pending != nil{self.sendConfiguration()}else{self.configuring=false;if error == nil{self.scene.rendererDidBecomeReady()}}}
        }
    }
}

private final class FFLWebView:WKWebView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    var onResize:((CGSize)->Void)?
    override func layout(){super.layout();onResize?(bounds.size)}
}

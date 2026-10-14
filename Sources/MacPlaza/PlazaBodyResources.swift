import AppKit
import SwiftUI
import CryptoKit
import PlazaCore

/// Original menu assets stay in Application Support and out of portable exports.
/// Import executes only our bundled data reader, never Wii U firmware code.
@MainActor final class PlazaBodyResources:ObservableObject {
    static let shared=PlazaBodyResources()
    @Published private(set) var installed=false
    @Published private(set) var revision=UUID()
    @Published private(set) var importing=false
    @Published private(set) var message="Original plaza bodies and animations are not installed. Using locally authored motion."
    private(set) var data:Data?
    let url:URL
    init(directory:URL?=nil){
        url=(directory ?? PlazaDataLocation.root.appendingPathComponent("Renderer")).appendingPathComponent("plaza-body.json")
        if let bytes=try? Data(contentsOf:url),let count=try? Self.check(bytes){data=bytes;installed=true;message="Original Wii U menu bodies and \(count) animation clips installed locally."}
    }
    var motionTiming:CrowdTiming {
        guard let data,let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let clips=object["animations"] as? [[String:Any]] else{return CrowdTiming()}
        var durations:[String:Double]=[:]
        for clip in clips {if let name=clip["name"] as? String,let frames=clip["frames"] as? Double,frames>0 {durations[name]=frames/30}}
        return CrowdTiming(clips:durations)
    }
    func reloadInstalled() {
        if let bytes = try? Data(contentsOf: url), let count = try? Self.check(bytes) {
            data = bytes; installed = true
            message = "Original Wii U menu bodies and \(count) animation clips installed locally."
        } else { data = nil; installed = false; message = "Using locally authored bodies and motion." }
        revision = UUID(); FFLPortraits.shared.reset()
    }
    var originalCatalog:OriginalLoungeCatalog? {
        guard let data,let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let clips=object["animations"] as? [[String:Any]] else{return nil}
        let headers=clips.compactMap {clip->OriginalLoungeCatalog.Clip? in
            guard let name=clip["name"] as? String,let frames=clip["frames"] as? Double,
                  let loop=clip["loop"] as? Bool else{return nil}
            return .init(name:name,frames:Float(frames),loop:loop)
        }
        guard headers.count==clips.count else{return nil}
        return OriginalLoungeCatalog(clips:headers)
    }
    static func check(_ data:Data)throws->Int{
        guard data.count<=16*1024*1024,let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],object["version"] as? Int==1,
              let models=object["models"] as? [[String:Any]],models.count==2,let clips=object["animations"] as? [[String:Any]],(6...256).contains(clips.count),
              let texture=object["texture"] as? [String:Any],texture["data"] is [Int] else{throw FFLError.message("Invalid local plaza body resource.")}
        return clips.count
    }
    static func checkedMenu(at selected:URL)throws->Data{
        let values=try selected.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard values.isRegularFile==true,let size=values.fileSize,(1024...64*1024*1024).contains(size) else{throw FFLError.message("Choose an uncompressed Men2.pack archive (1 KB–64 MB).")}
        let bytes=try Data(contentsOf:selected,options:.mappedIfSafe)
        guard bytes.prefix(4)==Data("SARC".utf8) else{throw FFLError.message("Choose Men2.pack with a SARC header.")};return bytes
    }
    func importResource(){
        let panel=NSOpenPanel();panel.title="Import original WaraWara Plaza bodies and animations";panel.message="Choose Men2.pack from a local Wii U menu dump. Only body models, the body atlas and animation data are read; firmware code is never run.";panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let selected=panel.url else{return}
        Task{await install(selected)}
    }
    func install(_ selected:URL)async {
        guard !importing else{return};importing=true;defer{importing=false}
        var validator:FFLSurface?;defer{validator?.invalidate()}
        do{
            guard FFLResources.shared.installed else{throw FFLError.message("Import an FFL face resource first.")}
            let archive=try Self.checkedMenu(at:selected)
            message="Reading original body meshes and skeletal animation curves…"
            let surface=FFLSurface(mode:"plaza",useInstalledBody:false);validator=surface
            let converted=try await surface.importMenu(archive),count=try Self.check(converted)
            var a=Avatar(name:"Menu resource test");_ = try await surface.portrait(a,pose:1,width:96,height:144)
            a.features.gender=1;_ = try await surface.portrait(a,pose:3,width:96,height:144)
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try converted.write(to:url,options:.atomic)
            let digest=SHA256.hash(data:archive).map{String(format:"%02x",$0)}.joined()
            try? Data("Imported: \(selected.lastPathComponent)\nSHA-256: \(digest)\nOriginal Men2.pack models and curves; \(count) clips.\n".utf8).write(to:url.deletingLastPathComponent().appendingPathComponent("body-info.txt"),options:.atomic)
            data=converted;installed=true;revision=UUID();FFLPortraits.shared.reset()
            message="Original Wii U menu bodies and \(count) animation clips installed locally."
        }catch{message="Bodies were not installed: \(error.localizedDescription)"}
    }
    func remove(){
        do{if FileManager.default.fileExists(atPath:url.path){try FileManager.default.removeItem(at:url)};data=nil;installed=false;revision=UUID();FFLPortraits.shared.reset();message="Using locally authored bodies and motion."}catch{message=error.localizedDescription}
    }
}

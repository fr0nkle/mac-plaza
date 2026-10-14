import Foundation
import PlazaCore

// The same native crowd, original controllers and codec used by the Mac app.
// Only bounded JSON crosses stdin/stdout; the helper has no network access.
var simulation = CrowdSimulation(population: 0, localCount: 0, seed: 0x57415241)
var characters: [Avatar] = []
var width = 1200.0, height = 720.0
var configured = false
var posts = PlazaPostCadence()
var pendingArrival:UUID?
let compact: [[Double]] = [[0.22,0.18],[0.40,0.105],[0.60,0.105],[0.78,0.18],[0.84,0.55],[0.625,0.67],[0.38,0.65],[0.165,0.55],[0.945,0.33],[0.055,0.33]]
let expanded: [[Double]] = [[0.22,0.18],[0.40,0.105],[0.60,0.105],[0.78,0.18],[0.945,0.33],[0.055,0.33],[0.83,0.68],[0.61,0.72],[0.39,0.72],[0.17,0.68],[0.94,0.52],[0.06,0.52]]
func decode<T: Decodable>(_ value: Any, _ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value)) }
func encode<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
func rendering(_ a: Avatar) throws -> [String: Any] {
    var r = a; r.id=UUID(uuidString:"00000000-0000-4000-8000-000000000001")!; r.name = "Mii"; r.features.creator = ""
    let shift = (a.featureHeight - 0.5) * 0.25
    r.features.eyeY = min(1,max(0,a.features.eyeY + shift)); r.features.browY = min(1,max(0,a.features.browY + shift))
    r.features.noseY = min(1,max(0,a.features.noseY + shift)); r.features.mouthY = min(1,max(0,a.features.mouthY + shift))
    return ["id":a.id.uuidString,"data":try MiiFile.encode(r).base64EncodedString(),"height":a.height,"build":a.build,"outfit":a.outfit,"gender":a.features.gender]
}
func viewport(_ args: [String:Any]) {
    width = min(16000,max(1,args["width"] as? Double ?? width)); height = min(16000,max(1,args["height"] as? Double ?? height))
    let tile = max(80,min(136,width * 0.105,height * 0.19))
    simulation.worldAspect = 16 / sqrt(22 * 22 + 16 * 16) * width / height
    simulation.islandHalfWidth = (tile / 2 + 10) / width; simulation.islandTopClearance = (tile / 2 + 8) / height
    simulation.islandBottomClearance = (tile / 2 + 32 + width * 0.035) / height
}
func perform(_ command: String, _ args: [String:Any]) throws -> Any {
    switch command {
    case "rotateHome":
        let recent=try decode(args["recent"] ?? [],[AppIsland].self),games=try decode(args["games"] ?? [],[AppIsland].self),fallback=try decode(args["fallback"] ?? [],[AppIsland].self)
        guard recent.count<=120,games.count<=120,fallback.count<=120 else{throw PlazaError.invalid("Too many app shortcuts.")}
        var random=SystemRandomNumberGenerator()
        return try encode(HomeScreenRotation.select(recent:recent,friendGames:games,fallback:fallback,previous:args["previous"] as? [String] ?? [],using:&random))
    case "portable":
        let data=try JSONSerialization.data(withJSONObject:args["document"] ?? [:])
        return try encode(DocumentStorage.decode(data).portable())
    case "configure":
        let own = try decode(args["avatars"] ?? [], [Avatar].self)
        guard own.count <= 200 else { throw PlazaError.invalid("Too many characters.") }
        for a in own { _ = try a.validated() }
        let population = min(200,max(20,args["population"] as? Int ?? 160))
        let localCount = min(own.count,max(0,args["localCount"] as? Int ?? own.count))
        var catalog = own
        for i in 0..<16 {
            var a = Avatar(name: "Local visitor", outfit: i % 12)
            a.skin=i%6; a.hair=[33,12,44,0,37,18,55,28,1,93,69,3,30,9,64,58][i]
            a.hairColor=[1,2,0,3,1,6,0,2,4,1,3,0,5,6,1,2][i]; a.eyes=[2,0,8,24,18,35,15,40,6,53,32,27,3,59,41,49][i]
            a.brows=[0,1,2,9,4,0,10,1,6,3,8,11,23,9,14,19][i];a.mouth=[5,0,19,7,14,5,23,8,12,5,3,0,18,34,11,27][i]
            a.face=i%12;a.glasses=i%5==0;a.height=Double(i%7)/7;a.build=Double(i%5)/5;a.features.gender=i%2;a.features.eyeColor=i%6;a.features.browColor=a.hairColor
            catalog.append(a)
        }
        characters = (0..<population).map { i in
            var a = catalog[i<own.count ? i:own.count+(i-own.count)%16]
            if i>=own.count { a.id=UUID(uuidString:String(format:"57415241-0000-4000-8000-%012llx",UInt64(i-own.count)))! };return a
        }
        simulation.worldWidth=48; simulation.minimumSpacing=0.016;simulation.groupsBelowIslands=true;simulation.nominalSpeed=0.011
        var original=false
        if let clips=args["clips"] as? [[String:Any]],!clips.isEmpty {
            let headers=clips.compactMap {c -> OriginalLoungeCatalog.Clip? in
                guard let name=c["name"] as? String,let frames=c["frames"] as? Double,let loop=c["loop"] as? Bool else{return nil}
                return .init(name:name,frames:Float(frames),loop:loop)
            }
            guard headers.count==clips.count,let resource=OriginalLoungeCatalog(clips:headers) else{throw PlazaError.invalid("Invalid original animation catalog.")}
            simulation.enableOriginalControllers(resource);simulation.strideLength=1.456;simulation.scaleSpeedWithStature=true
            simulation.nominalSpeed=1.456*60*0.8461539/40/48;original=true
        } else {simulation.disableOriginalControllers();simulation.scaleSpeedWithStature=false;simulation.strideLength=0.48}
        simulation.reconcileRoster(characters.map(\.id),localCount:localCount)
        simulation.setStatures(characters.map { original ? 0.5+($0.height*127).rounded()*0.77/128:0.72+$0.height*0.40 })
        viewport(args)
        let count=min(12,max(0,args["islandCount"] as? Int ?? 0))
        simulation.islands=Array((count>10 ? expanded:compact).prefix(count)).map{CrowdPoint($0[0],$0[1])}
        if let values=args["gathering"] as? [String:Int] {var assignments:[Int:Int]=[:];for(i,a)in characters.enumerated(){if let island=values[a.id.uuidString.lowercased()]{assignments[i]=island}};simulation.setGatheringIslands(assignments)}
        if !configured {simulation.step(0.001);if args["reduceMotion"] as? Bool != true {simulation.beginEntrance()};configured=true}
        if let id=pendingArrival,let index=characters.firstIndex(where:{$0.id==id}){simulation.beginArrival(index:index);pendingArrival=nil}
        return ["avatars":try characters.map {a -> [String:Any] in var value=try rendering(a);value["avatar"]=try encode(a);return value},"originalControllers":original]
    case "frame":
        let dt=min(0.1,max(0,args["dt"] as? Double ?? 1.0/30));viewport(args);simulation.step(dt);posts.advance(by:dt,held:args["postsHeld"] as? Bool == true || simulation.entranceElapsed != nil)
        let depth=48*height/width/(16/sqrt(22*22+16*16))
        let poses=simulation.walkers.enumerated().map { i,w -> [Double] in
            let drop=i==simulation.arrivalIndex ? PlazaArrival.height(at:simulation.arrivalElapsed ?? 0):0
            let base:[Double]=[(w.position.x-0.5)*48,(w.position.y-0.5)*depth,drop,w.angle,Double(w.state),w.phase,w.motion,w.partner != nil && w.greeting<=0 ? 1:0,w.blink ? 1:0,Double(w.mood),w.animationTime,w.lookYaw,w.turn,Double(w.activity.rawValue),w.activityTime,w.activityDuration,simulation.animationClock]
            return base+(simulation.originalSample(i)?.bridge ?? [])
        }
        return ["arrivalFocus":simulation.arrivalElapsed.map{PlazaArrival.focus(at:$0)} as Any? ?? NSNull(),"islandEntrance":simulation.islands.map{p -> [Double] in let progress=simulation.entranceElapsed.map{PlazaEntrance.iconProgress(at:p,elapsed:$0)} ?? 1;return [PlazaEntrance.iconScale(progress:progress),progress>0 ? 1:0]},"postPresentation":posts.presentation == .journal ? "journal":posts.presentation == .friends ? "friends":"quiet","poses":poses,"identities":characters.map{$0.id.uuidString},"entrance":simulation.entranceElapsed as Any? ?? NSNull(),"arrival":simulation.arrivalElapsed as Any? ?? NSNull()]
    case "music":return ["data":Soundtrack.loop().base64EncodedString()]
    case "renderAvatar":return try rendering(decode(args["avatar"] ?? [:],Avatar.self).validated())
    case "fallback":return CharacterRig.fallback(try decode(args["avatar"] ?? [:],Avatar.self).validated())
    case "decodeMii":guard let bytes=Data(base64Encoded:args["data"] as? String ?? ""),bytes.count==96 else{throw PlazaError.invalid("Choose a 96-byte Mii file.")};return try encode(MiiFile.decode(bytes))
    case "encodeMii":return ["data":try MiiFile.encode(decode(args["avatar"] ?? [:],Avatar.self)).base64EncodedString()]
    case "acknowledge":simulation.acknowledge(args["index"] as? Int ?? -1);return [:]
    case "cheer":let i=args["index"] as? Int ?? -1;if simulation.islands.indices.contains(i){simulation.cheer(near:simulation.islands[i])};return [:]
    case "arrival":let id=UUID(uuidString:args["id"] as? String ?? "");let i=id.flatMap{key in characters.firstIndex(where:{$0.id==key})} ?? (args["index"] as? Int ?? -1);if let id,!characters.contains(where:{$0.id==id}){pendingArrival=id};if characters.indices.contains(i){simulation.beginArrival(index:i)};return [:]
    case "finishEntrance":simulation.finishEntrance();simulation.finishArrival();return [:]
    default:throw PlazaError.invalid("Unknown engine operation.")
    }
}
while let line=readLine() {
    guard line.utf8.count<=4_000_000 else{continue}
    var id=0
    do {
        let input=try JSONSerialization.jsonObject(with:Data(line.utf8)) as? [String:Any] ?? [:];id=input["id"] as? Int ?? 0
        let result=try perform(input["command"] as? String ?? "",input["args"] as? [String:Any] ?? [:])
        let data=try JSONSerialization.data(withJSONObject:["id":id,"ok":true,"value":result],options:[.sortedKeys])
        FileHandle.standardOutput.write(data);FileHandle.standardOutput.write(Data([10]))
    }catch{
        let data=(try? JSONSerialization.data(withJSONObject:["id":id,"ok":false,"error":error.localizedDescription])) ?? Data()
        FileHandle.standardOutput.write(data);FileHandle.standardOutput.write(Data([10]))
    }
}

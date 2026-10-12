import Foundation

/// Fixed node topology and occupancy operations recovered from 02190344,
/// 0218ff0c, 02191684, 02191b78, 02191bc8 and 0219237c...02192580.
/// Host admission chooses a vacant node; the database never changes positions.
public struct OriginalLoungeGroupDatabase: Sendable {
    public struct Axial:Hashable,Sendable {public let q:Int;public let r:Int}
    public struct Node:Sendable {
        public let axial:Axial
        public var position:OriginalLounge.GroundPoint
        public let neighbors:[Int?]
        public fileprivate(set) var actor:Int?
        public fileprivate(set) var order:Int = -1
        public fileprivate(set) var occupiedNeighbors=0
    }
    public private(set) var nodes:[Node]
    public private(set) var occupied:[Int]=[]
    public static func coordinate(ring:Int,position:Int)->Axial {
        precondition((0...11).contains(ring) && (0..<max(1,ring*6)).contains(position))
        guard ring>0 else{return .init(q:0,r:0)}
        let side=position/ring,t=position%ring
        switch side {
        case 0:return .init(q:t-ring,r:ring)
        case 1:return .init(q:t,r:ring-t)
        case 2:return .init(q:ring,r:-t)
        case 3:return .init(q:ring-t,r:-ring)
        case 4:return .init(q:-t,r:t-ring)
        default:return .init(q:-ring,r:t)
        }
    }
    public init(origin:OriginalLounge.GroundPoint = .init(0,0),radius:Float=8,xScale:Float=1,zScale:Float=1) {
        let axial=(0...11).flatMap {ring in (0..<max(1,ring*6)).map {Self.coordinate(ring:ring,position:$0)}}
        let lookup=Dictionary(uniqueKeysWithValues:axial.enumerated().map {($0.element,$0.offset)})
        let offsets=[(-1,0),(0,-1),(1,-1),(1,0),(0,1),(-1,1)]
        nodes=axial.map {a in .init(axial:a,position:.init(0,0),neighbors:offsets.map {lookup[.init(q:a.q+$0.0,r:a.r+$0.1)]})}
        setGeometry(origin:origin,radius:radius,xScale:xScale,zScale:zScale)
    }
    public mutating func setGeometry(origin:OriginalLounge.GroundPoint,radius:Float=8,xScale:Float=1,zScale:Float=1) {
        let x=radius*xScale,z=radius*zScale*Float(1.7320510149002075)
        for i in nodes.indices {
            let a=nodes[i].axial
            nodes[i].position = .init(origin.x.addingProduct(Float(a.q),x).addingProduct(-Float(a.r),x),
                origin.z.addingProduct(Float(a.q),z).addingProduct(Float(a.r),z))
        }
    }
    public func node(for actor:Int)->Int? {occupied.first {nodes[$0].actor==actor}}
    private mutating func countNeighbors(_ node:Int,_ change:Int) {
        for n in nodes[node].neighbors.compactMap({$0}) {nodes[n].occupiedNeighbors+=change}
    }
    @discardableResult public mutating func insert(actor:Int,at node:Int)->Bool {
        guard nodes.indices.contains(node),nodes[node].actor==nil,self.node(for:actor)==nil else{return false}
        nodes[node].actor=actor;nodes[node].order=occupied.count;occupied.append(node);countNeighbors(node,1);return true
    }
    public mutating func remove(actor:Int) {
        guard let n=node(for:actor) else{return}
        countNeighbors(n,-1);occupied.remove(at:nodes[n].order);nodes[n].actor=nil;nodes[n].order = -1
        for (order,node) in occupied.enumerated() {nodes[node].order=order}
    }
    public mutating func remapActors(_ mapping:[Int:Int]) {
        for n in occupied where nodes[n].actor.flatMap({mapping[$0]}) == nil {if let a=nodes[n].actor {remove(actor:a)}}
        for n in occupied {nodes[n].actor=nodes[n].actor.flatMap {mapping[$0]}}
    }
    /// 02192514: occupied nodes exchange actors; their list order/counts stay.
    public mutating func swap(_ a:Int,_ b:Int) {
        precondition(nodes[a].actor != nil && nodes[b].actor != nil)
        let actor=nodes[a].actor;nodes[a].actor=nodes[b].actor;nodes[b].actor=actor
    }
    /// 02192580: move into a vacancy while retaining the occupied-list slot.
    public mutating func move(_ from:Int,to:Int) {
        precondition(nodes[from].actor != nil && nodes[to].actor==nil)
        countNeighbors(from,-1);countNeighbors(to,1)
        let order=nodes[from].order
        nodes[to].actor=nodes[from].actor;nodes[to].order=order;occupied[order]=to
        nodes[from].actor=nil;nodes[from].order = -1
    }
    /// Skip vacant nodes along the same one of six directions, 02191b78.
    public func firstOccupied(from:Int,direction:Int)->Int? {
        guard nodes.indices.contains(from),(0..<6).contains(direction) else{return nil}
        var next=nodes[from].neighbors[direction]
        while let n=next {if nodes[n].actor != nil {return n};next=nodes[n].neighbors[direction]}
        return nil
    }
    public func slots(at node:Int)->[Int?] {nodes[node].neighbors.map {$0.flatMap {nodes[$0].actor}}}
    /// 02191bc8. Preserve the source's Float sum order and strict comparison.
    public static func improvesSwap(nodeA:OriginalLounge.GroundPoint,nodeB:OriginalLounge.GroundPoint,
        actorA:OriginalLounge.GroundPoint,actorB:OriginalLounge.GroundPoint,restrictionsA:UInt32=0,restrictionsB:UInt32=0)->Bool {
        guard (restrictionsA|restrictionsB)&0x20==0 else{return false}
        func squared(_ node:OriginalLounge.GroundPoint,_ actor:OriginalLounge.GroundPoint)->Float {
            let x=node.x-actor.x,z=node.z-actor.z
            return (z*z).addingProduct(x,x)
        }
        // The original uses one fused square per distance, then sums B→A first.
        return squared(nodeA,actorB)+squared(nodeB,actorA)<squared(nodeA,actorA)+squared(nodeB,actorB)
    }
    /// 02191d30: one random cyclic scan per accepted swap, continuing from the
    /// destination with a directional mask. Strictly decreasing assignment cost
    /// makes this finite; the host adds a generous bound for invalid inputs.
    @discardableResult public mutating func optimize(from start:Int,positions:[OriginalLounge.GroundPoint],restrictions:[UInt32],
        special:Set<Int>=[],random:inout OriginalLoungeRandom)->Int {
        var current=start,mask:UInt32=0x3f
        guard nodes.indices.contains(current),nodes[current].actor != nil else{return current}
        for _ in 0..<nodes.count*nodes.count {
            let first=Int(random.below(6));var found:(Int,Int)?
            for offset in 0..<6 {
                let slot=(first+offset)%6
                guard mask&(1<<slot) != 0,let other=firstOccupied(from:current,direction:slot),
                    let a=nodes[current].actor,let b=nodes[other].actor,positions.indices.contains(a),positions.indices.contains(b),
                    restrictions.indices.contains(a),restrictions.indices.contains(b) else{continue}
                if Self.improvesSwap(nodeA:nodes[current].position,nodeB:nodes[other].position,actorA:positions[a],actorB:positions[b],
                    restrictionsA:restrictions[a],restrictionsB:restrictions[b]) {found=(other,slot);break}
            }
            guard let (other,slot)=found else{return current}
            swap(current,other)
            if mask==0x3f {
                // PPC slw with signed (slot-1)%6 drops the previous bit at slot 0.
                let previous=slot==0 ? UInt32(0):UInt32(1<<(slot-1))
                mask=previous|UInt32(1<<slot)|UInt32(1<<((slot+1)%6))
            }
            current=other
            if special.contains(nodes[current].actor!) {return current}
        }
        return current
    }
}

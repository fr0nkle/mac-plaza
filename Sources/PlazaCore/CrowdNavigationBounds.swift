import Foundation

/// Normalized ground coordinates; x/y may extend beyond the app layout.
public struct CrowdNavigationBounds: Equatable, Sendable {
    public let minX:Double, maxX:Double, minY:Double, maxY:Double
    public init(minX:Double=0.05,maxX:Double=0.95,minY:Double=0.20,maxY:Double=0.95) {
        precondition([minX,maxX,minY,maxY].allSatisfy(\.isFinite) && minX<maxX && minY<maxY)
        self.minX=minX;self.maxX=maxX;self.minY=minY;self.maxY=maxY
    }
    public func contains(_ p:CrowdPoint)->Bool {
        (minX...maxX).contains(p.x) && (minY...maxY).contains(p.y)
    }
    public func clamped(_ p:CrowdPoint)->CrowdPoint {
        CrowdPoint(min(maxX,max(minX,p.x)),min(maxY,max(minY,p.y)))
    }
}

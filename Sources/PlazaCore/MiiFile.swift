import Foundation

/// Native FFLStoreData (Wii U / 3DS, 96 bytes). No renderer or network dependency.
/// Console/system identity is intentionally not imported into the local character.
public enum MiiFile {
    public static func crc(_ bytes: some Sequence<UInt8>) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = (crc & 0x8000 != 0) ? (crc &<< 1) ^ 0x1021 : crc &<< 1 }
        }
        return crc
    }
    public static func decode(_ data: Data) throws -> Avatar {
        guard data.count == 96 else { throw PlazaError.invalid("Choose a 96-byte Wii U / 3DS .mii or .ffsd file. Encrypted QR and Switch files are not supported.") }
        let b = Array(data)
        guard [0,3].contains(b[0]), crc(b.prefix(94)) == UInt16(b[94]) << 8 | UInt16(b[95]) else { throw PlazaError.invalid("The Mii version or checksum is invalid.") }
        func bits(_ offset: Int, _ count: Int) -> Int { (0..<count).reduce(0) { $0 | (Int((b[(offset + $1) / 8] >> ((offset + $1) % 8)) & 1) << $1) } }
        func value(_ offset: Int, _ count: Int, _ max: Int) throws -> Double {
            let n = bits(offset, count); guard n <= max else { throw PlazaError.invalid("A Mii feature exceeds its supported range.") }; return Double(n) / Double(max)
        }
        func string(_ offset: Int) -> String { String(decoding: stride(from: offset, to: offset + 20, by: 2).map { UInt16(b[$0]) | UInt16(b[$0+1]) << 8 }.prefix(while: { $0 != 0 }), as: UTF16.self) }
        var a = Avatar(name: string(26)); var f = MiiFeatures()
        f.allowCopying = bits(8,1) == 1; f.gender = bits(192,1); f.birthMonth = bits(193,4); f.birthDay = bits(197,5)
        a.outfit = bits(202,4); f.favorite = bits(206,1) == 1
        a.height = try value(368,8,127); a.build = try value(376,8,127)
        f.sharing = bits(384,1) == 0; a.face = bits(385,4); a.skin = bits(389,3)
        f.wrinkles = bits(392,4); f.makeup = bits(396,4); a.hair = bits(400,8); a.hairColor = bits(408,3); f.flipHair = bits(411,1) == 1
        a.eyes = bits(416,6); f.eyeColor = bits(422,3); f.eyeSize = try value(425,4,7); f.eyeStretch = try value(429,3,6)
        f.eyeRotation = try value(432,5,7); a.eyeSpacing = try value(437,4,12); f.eyeY = try value(441,5,18)
        a.brows = bits(448,5); f.browColor = bits(453,3); f.browSize = try value(456,4,8); f.browStretch = try value(460,3,6)
        f.browRotation = try value(464,4,11); f.browSpacing = try value(469,4,12); f.browY = Double(bits(473,5)-3)/15; guard (0...1).contains(f.browY) else { throw PlazaError.invalid("The Mii eyebrow position is invalid.") }
        a.nose = bits(480,5); f.noseSize = try value(485,4,8); f.noseY = try value(489,5,18)
        a.mouth = bits(496,6); f.mouthColor = bits(502,3); f.mouthSize = try value(505,4,8); f.mouthStretch = try value(509,3,6); f.mouthY = try value(512,5,18); f.mustache = bits(517,3)
        f.beardType = bits(528,3); a.beard = f.beardType != 0; f.facialHairColor = bits(531,3); f.mustacheSize = try value(534,4,8); f.mustacheY = try value(538,5,16)
        f.glassesType = bits(544,4); a.glasses = f.glassesType != 0; f.glassesColor = bits(548,3); f.glassesSize = try value(551,4,7); f.glassesY = try value(555,5,20)
        f.mole = bits(560,1) == 1; f.moleSize = try value(561,4,8); f.moleX = try value(565,5,16); f.moleY = try value(570,5,30); f.creator = string(72)
        a.features = f; return try a.validated()
    }
    public static func encode(_ avatar: Avatar) throws -> Data {
        let a = try avatar.validated(), f = a.features
        guard a.name.utf16.count <= 10, f.creator.utf16.count <= 10 else { throw PlazaError.invalid("The Wii U file format allows 10 UTF-16 units for nickname and creator. Use Character JSON for longer names.") }
        var b = [UInt8](repeating: 0, count: 96); b[0] = 3; b[3] = 0x40
        let identifier = 0x90000000 | (a.id.uuidString.utf8.reduce(UInt32(0)) { $0 &* 31 &+ UInt32($1) } & 0x0fffffff)
        for i in 0..<4 { b[12+i]=UInt8((identifier >> (24-i*8)) & 255) }
        func put(_ offset: Int, _ count: Int, _ value: Int) { for i in 0..<count { let bit = offset+i; b[bit/8] = (b[bit/8] & ~(1 << (bit%8))) | UInt8((value >> i) & 1) << (bit%8) } }
        func normalized(_ offset: Int, _ count: Int, _ value: Double, _ max: Int) { put(offset,count,Int((value*Double(max)).rounded())) }
        func string(_ offset: Int, _ value: String) { for (i, c) in value.utf16.prefix(10).enumerated() { b[offset+i*2] = UInt8(c & 255); b[offset+i*2+1] = UInt8(c >> 8) } }
        put(8,1,f.allowCopying ? 1:0); put(192,1,f.gender); put(193,4,f.birthMonth); put(197,5,f.birthDay); put(202,4,a.outfit); put(206,1,f.favorite ? 1:0); string(26,a.name)
        normalized(368,8,a.height,127); normalized(376,8,a.build,127); put(384,1,f.sharing ? 0:1); put(385,4,a.face); put(389,3,a.skin); put(392,4,f.wrinkles); put(396,4,f.makeup)
        put(400,8,a.hair); put(408,3,a.hairColor); put(411,1,f.flipHair ? 1:0)
        put(416,6,a.eyes); put(422,3,f.eyeColor); normalized(425,4,f.eyeSize,7); normalized(429,3,f.eyeStretch,6); normalized(432,5,f.eyeRotation,7); normalized(437,4,a.eyeSpacing,12); normalized(441,5,f.eyeY,18)
        put(448,5,a.brows); put(453,3,f.browColor); normalized(456,4,f.browSize,8); normalized(460,3,f.browStretch,6); normalized(464,4,f.browRotation,11); normalized(469,4,f.browSpacing,12); put(473,5,3+Int((f.browY*15).rounded()))
        put(480,5,a.nose); normalized(485,4,f.noseSize,8); normalized(489,5,f.noseY,18)
        put(496,6,a.mouth); put(502,3,f.mouthColor); normalized(505,4,f.mouthSize,8); normalized(509,3,f.mouthStretch,6); normalized(512,5,f.mouthY,18); put(517,3,f.mustache)
        put(528,3,a.beard ? max(1,f.beardType):0); put(531,3,f.facialHairColor); normalized(534,4,f.mustacheSize,8); normalized(538,5,f.mustacheY,16)
        put(544,4,a.glasses ? max(1,f.glassesType):0); put(548,3,f.glassesColor); normalized(551,4,f.glassesSize,7); normalized(555,5,f.glassesY,20)
        put(560,1,f.mole ? 1:0); normalized(561,4,f.moleSize,8); normalized(565,5,f.moleX,16); normalized(570,5,f.moleY,30); string(72,f.creator)
        let sum = crc(b.prefix(94)); b[94] = UInt8(sum >> 8); b[95] = UInt8(sum & 255)
        return Data(b)
    }
}

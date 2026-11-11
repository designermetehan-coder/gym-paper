import Foundation

/// Workout sharing: short-key JSON → zlib → base64url (for QR and links).
public enum ProgramShare {
    struct SE: Codable { var n: String; var s: Int; var r: Int; var u: String?; var rs: Int?; var k: Double? }
    struct SB: Codable { var x: [SE]; var t: Int?; var rs: Int?; var g: String? }   // x.count > 1 or t != nil → superset
    struct SP: Codable { var v: Int = 1; var n: String; var b: [SB] }

    /// Program → short text
    public static func encode(name: String, blocks: [Block]) -> String? {
        func se(_ e: Exercise, rest: Bool) -> SE {
            SE(n: e.name, s: e.sets, r: e.reps, u: e.unit == "tekrar" ? nil : e.unit, rs: rest && e.rest != 60 ? e.rest : nil, k: e.kg)
        }
        let b = blocks.compactMap { bl -> SB? in
            if bl.kind == .single, let e = bl.ex { return SB(x: [se(e, rest: true)]) }
            guard !bl.exs.isEmpty else { return nil }
            return SB(x: bl.exs.map { se($0, rest: false) }, t: bl.rounds, rs: bl.rest, g: bl.tag)
        }
        guard let json = try? JSONEncoder().encode(SP(n: name, b: b)),
              let z = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
        return z.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Short text → program (nil if invalid)
    public static func decode(_ s: String) -> (name: String, blocks: [Block])? {
        // a QR code holds ~3 KB; very large input and over-expanding data are rejected
        guard s.count <= 12_000 else { return nil }
        var b64 = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let z = Data(base64Encoded: b64), let json = try? (z as NSData).decompressed(using: .zlib) as Data,
              json.count <= 512_000,
              let sp = try? JSONDecoder().decode(SP.self, from: json) else { return nil }
        func ex(_ e: SE, sets: Int? = nil) -> Exercise {
            Exercise(name: String(e.n.prefix(80)), sets: min(20, max(1, sets ?? e.s)), reps: min(999, max(1, e.r)), unit: ["sn", "dk"].contains(e.u ?? "") ? e.u! : "tekrar",
                     rest: min(900, max(0, e.rs ?? 60)), kg: e.k.flatMap { $0 > 0 ? min(999, $0) : nil })
        }
        let blocks = sp.b.prefix(60).compactMap { b -> Block? in
            if b.x.count == 1 && b.t == nil { return Block(single: ex(b.x[0])) }
            guard !b.x.isEmpty else { return nil }
            let r = min(20, max(1, b.t ?? 3))
            return Block(superset: b.x.prefix(12).map { var e = ex($0, sets: r); e.rest = 0; return e }, rounds: r, rest: min(900, max(0, b.rs ?? 60)), tag: b.g)
        }
        guard !blocks.isEmpty else { return nil }
        return (String(sp.n.prefix(60)), Array(blocks))
    }
}

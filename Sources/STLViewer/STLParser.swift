import Foundation
import simd

/// A single triangle from an STL mesh.
struct STLTriangle {
    var normal: SIMD3<Float>
    var v0: SIMD3<Float>
    var v1: SIMD3<Float>
    var v2: SIMD3<Float>
}

/// The parsed result of an STL file.
struct STLMesh {
    var triangles: [STLTriangle]

    /// Axis-aligned bounding box (min, max) of all vertices.
    var boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard let first = triangles.first?.v0 else {
            return (.zero, .zero)
        }
        var minB = first
        var maxB = first
        for t in triangles {
            for v in [t.v0, t.v1, t.v2] {
                minB = simd_min(minB, v)
                maxB = simd_max(maxB, v)
            }
        }
        return (minB, maxB)
    }
}

enum STLParseError: LocalizedError {
    case emptyFile
    case truncatedBinary
    case invalidASCII
    case noTriangles

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "The file is empty."
        case .truncatedBinary: return "The binary STL file is truncated or corrupt."
        case .invalidASCII: return "The ASCII STL file could not be parsed."
        case .noTriangles: return "No triangles were found in the file."
        }
    }
}

/// Parses STL files in both binary and ASCII formats.
enum STLParser {

    static func parse(url: URL) throws -> STLMesh {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> STLMesh {
        guard !data.isEmpty else { throw STLParseError.emptyFile }

        if isASCII(data) {
            return try parseASCII(data)
        } else {
            return try parseBinary(data)
        }
    }

    /// Heuristic to distinguish ASCII from binary STL.
    ///
    /// ASCII files begin with "solid", but so can some binary files in their
    /// 80-byte header. The reliable check is to compare the declared triangle
    /// count in a binary header against the actual file size.
    private static func isASCII(_ data: Data) -> Bool {
        // Binary files are at least 84 bytes (80 header + 4 count).
        if data.count < 84 {
            return true
        }

        // Read declared triangle count from the binary header.
        let count = data.subdata(in: 80..<84).withUnsafeBytes { raw in
            raw.load(as: UInt32.self)
        }
        let expectedBinarySize = 84 + Int(count) * 50
        if expectedBinarySize == data.count {
            return false
        }

        // Fall back to checking for the "solid" keyword and printable content.
        let prefixLen = min(512, data.count)
        let prefix = data.prefix(prefixLen)
        guard let text = String(data: prefix, encoding: .ascii) else {
            return false
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("solid")
    }

    // MARK: - Binary

    private static func parseBinary(_ data: Data) throws -> STLMesh {
        guard data.count >= 84 else { throw STLParseError.truncatedBinary }

        let count = data.subdata(in: 80..<84).withUnsafeBytes { raw in
            raw.load(as: UInt32.self)
        }
        let triangleCount = Int(count)
        let expectedSize = 84 + triangleCount * 50
        guard data.count >= expectedSize else { throw STLParseError.truncatedBinary }

        var triangles = [STLTriangle]()
        triangles.reserveCapacity(triangleCount)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 84
            for _ in 0..<triangleCount {
                let normal = readVector(raw, at: offset)
                let v0 = readVector(raw, at: offset + 12)
                let v1 = readVector(raw, at: offset + 24)
                let v2 = readVector(raw, at: offset + 36)
                // 2 bytes attribute byte count skipped
                triangles.append(STLTriangle(normal: normal, v0: v0, v1: v1, v2: v2))
                offset += 50
            }
        }

        guard !triangles.isEmpty else { throw STLParseError.noTriangles }
        return STLMesh(triangles: triangles)
    }

    /// Reads three little-endian Float32 values, without assuming alignment.
    private static func readVector(_ raw: UnsafeRawBufferPointer, at offset: Int) -> SIMD3<Float> {
        let x = raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
        let y = raw.loadUnaligned(fromByteOffset: offset + 4, as: Float.self)
        let z = raw.loadUnaligned(fromByteOffset: offset + 8, as: Float.self)
        return SIMD3<Float>(x, y, z)
    }

    // MARK: - ASCII

    private static func parseASCII(_ data: Data) throws -> STLMesh {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) else {
            throw STLParseError.invalidASCII
        }

        var triangles = [STLTriangle]()
        var currentNormal = SIMD3<Float>(0, 0, 0)
        var vertices = [SIMD3<Float>]()

        let scanner = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        for rawLine in scanner {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("facet normal") {
                let comps = line.split(separator: " ").compactMap { Float($0) }
                if comps.count >= 3 {
                    currentNormal = SIMD3<Float>(comps[0], comps[1], comps[2])
                }
                vertices.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("vertex") {
                let comps = line.split(separator: " ").compactMap { Float($0) }
                if comps.count >= 3 {
                    vertices.append(SIMD3<Float>(comps[0], comps[1], comps[2]))
                }
            } else if line.hasPrefix("endfacet") {
                if vertices.count == 3 {
                    triangles.append(STLTriangle(
                        normal: currentNormal,
                        v0: vertices[0],
                        v1: vertices[1],
                        v2: vertices[2]
                    ))
                }
                vertices.removeAll(keepingCapacity: true)
            }
        }

        guard !triangles.isEmpty else { throw STLParseError.noTriangles }
        return STLMesh(triangles: triangles)
    }
}

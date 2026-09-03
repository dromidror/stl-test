import Foundation
import simd

/// A 2D line segment in the XY plane produced by slicing the mesh.
struct CrossSectionSegment {
    var a: SIMD2<Float>
    var b: SIMD2<Float>
}

/// The result of slicing a mesh with a horizontal (Z = constant) plane.
struct CrossSection {
    var segments: [CrossSectionSegment]
    /// The Z height at which the slice was taken.
    var z: Float
    /// 2D bounding box of the resulting segments.
    var bounds: (min: SIMD2<Float>, max: SIMD2<Float>)
}

enum CrossSectionSlicer {

    /// Slices the mesh with the XY plane at depth Z = `z`, returning the line
    /// segments where the surface intersects that plane, projected onto the XY
    /// plane (X horizontal, Y vertical).
    ///
    /// For each triangle we find the edges that straddle the plane and connect
    /// the two intersection points into a single segment. Triangles that lie
    /// entirely above or below the plane contribute nothing.
    static func slice(mesh: STLMesh, atZ z: Float) -> CrossSection {
        var segments = [CrossSectionSegment]()
        segments.reserveCapacity(mesh.triangles.count / 4)

        var minB = SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var maxB = SIMD2<Float>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude)

        for tri in mesh.triangles {
            let verts = [tri.v0, tri.v1, tri.v2]
            var crossings = [SIMD2<Float>]()

            // Check each of the three edges for a crossing of the Z=z plane.
            for i in 0..<3 {
                let p0 = verts[i]
                let p1 = verts[(i + 1) % 3]
                let d0 = p0.z - z
                let d1 = p1.z - z

                // Edge straddles the plane (endpoints on opposite sides).
                if (d0 < 0 && d1 > 0) || (d0 > 0 && d1 < 0) {
                    let t = d0 / (d0 - d1)
                    let x = p0.x + t * (p1.x - p0.x)
                    let y = p0.y + t * (p1.y - p0.y)
                    crossings.append(SIMD2<Float>(x, y))
                } else if d0 == 0 {
                    // Vertex lies exactly on the plane.
                    crossings.append(SIMD2<Float>(p0.x, p0.y))
                }
            }

            // A clean crossing yields exactly two points -> one segment.
            if crossings.count >= 2 {
                let a = crossings[0]
                let b = crossings[1]
                // Skip degenerate zero-length segments.
                if simd_distance(a, b) > 1e-7 {
                    segments.append(CrossSectionSegment(a: a, b: b))
                    minB = simd_min(minB, simd_min(a, b))
                    maxB = simd_max(maxB, simd_max(a, b))
                }
            }
        }

        if segments.isEmpty {
            minB = .zero
            maxB = .zero
        }

        return CrossSection(segments: segments, z: z, bounds: (minB, maxB))
    }
}

extension CrossSection {
    /// Returns the point on the cross-section contour closest to `point`
    /// (all in model XY coordinates), or nil when the section is empty.
    func nearestPoint(to point: SIMD2<Float>) -> SIMD2<Float>? {
        var best: SIMD2<Float>?
        var bestDist = Float.greatestFiniteMagnitude

        for seg in segments {
            let candidate = Self.closestPointOnSegment(point, seg.a, seg.b)
            let d = simd_distance_squared(point, candidate)
            if d < bestDist {
                bestDist = d
                best = candidate
            }
        }
        return best
    }

    /// Closest point on segment [a, b] to point p.
    private static func closestPointOnSegment(
        _ p: SIMD2<Float>,
        _ a: SIMD2<Float>,
        _ b: SIMD2<Float>
    ) -> SIMD2<Float> {
        let ab = b - a
        let lenSq = simd_length_squared(ab)
        if lenSq < 1e-12 {
            return a
        }
        // Projection parameter clamped to the segment.
        let t = simd_clamp(simd_dot(p - a, ab) / lenSq, 0, 1)
        return a + ab * t
    }

    /// Finds the segment whose closest point to `point` is nearest, returning
    /// that segment's index and its (normalized) tangent direction.
    private func nearestSegment(to point: SIMD2<Float>) -> (index: Int, tangent: SIMD2<Float>)? {
        var bestIndex = -1
        var bestDist = Float.greatestFiniteMagnitude
        for (i, seg) in segments.enumerated() {
            let c = Self.closestPointOnSegment(point, seg.a, seg.b)
            let d = simd_distance_squared(point, c)
            if d < bestDist {
                bestDist = d
                bestIndex = i
            }
        }
        guard bestIndex >= 0 else { return nil }
        let seg = segments[bestIndex]
        let dir = seg.b - seg.a
        let len = simd_length(dir)
        guard len > 1e-9 else { return nil }
        return (bestIndex, dir / len)
    }
}

/// The result of measuring the local width of a cross-section at a point.
struct CrossSectionWidth {
    /// The two contour crossing points that bound the width (model XY).
    var p0: SIMD2<Float>
    var p1: SIMD2<Float>
    /// Distance between p0 and p1.
    var width: Float
}

extension CrossSection {
    /// Measures the width of the section through `point`, along the direction
    /// perpendicular to the contour's tangent at that point.
    ///
    /// A line is cast through `point` along the perpendicular and intersected
    /// with the whole contour. The crossings split the line into alternating
    /// interior/exterior spans; only spans that lie *inside* the solid count.
    /// The returned width is the interior span at (or nearest to) the crosshair,
    /// so notches and concave regions outside the material are not measured.
    func width(at point: SIMD2<Float>) -> CrossSectionWidth? {
        guard let ns = nearestSegment(to: point) else { return nil }

        // Perpendicular to the local tangent, unit length.
        let tangent = ns.tangent
        let normal = SIMD2<Float>(-tangent.y, tangent.x)

        // Collect all intersections of the full perpendicular line with the
        // contour, as signed distances `t` along `normal` from `point`.
        var hits = [Float]()
        for seg in segments {
            if let t = rayParameter(origin: point, dir: normal, a: seg.a, b: seg.b) {
                hits.append(t)
            }
        }
        guard hits.count >= 2 else { return nil }
        hits.sort()

        // De-duplicate near-identical crossings (e.g. shared segment endpoints).
        var uniq = [Float]()
        for t in hits {
            if let last = uniq.last, abs(t - last) < 1e-5 { continue }
            uniq.append(t)
        }
        guard uniq.count >= 2 else { return nil }

        // Between each consecutive pair of crossings the line is either inside
        // or outside the solid. Test the midpoint of each span; keep the
        // interior span that contains (or is nearest to) the crosshair at t=0.
        var bestSpan: (lo: Float, hi: Float)?
        var bestKey = Float.greatestFiniteMagnitude

        for i in 0..<(uniq.count - 1) {
            let lo = uniq[i]
            let hi = uniq[i + 1]
            if hi - lo < 1e-6 { continue }
            let midT = (lo + hi) * 0.5
            let midPoint = point + normal * midT
            guard contains(midPoint) else { continue }

            // Prefer the interior span straddling t=0 (the crosshair); otherwise
            // pick the interior span closest to the crosshair.
            let key: Float
            if lo <= 0 && hi >= 0 {
                key = 0
            } else {
                key = min(abs(lo), abs(hi))
            }
            if key < bestKey {
                bestKey = key
                bestSpan = (lo, hi)
            }
        }

        guard let span = bestSpan else { return nil }
        let p0 = point + normal * span.lo
        let p1 = point + normal * span.hi
        return CrossSectionWidth(p0: p0, p1: p1, width: span.hi - span.lo)
    }

    /// Even-odd point-in-polygon test against the (unordered) contour segments.
    /// Casts a ray in +X and counts crossings; odd means inside the solid.
    private func contains(_ p: SIMD2<Float>) -> Bool {
        var crossings = 0
        for seg in segments {
            let a = seg.a
            let b = seg.b
            // Does the horizontal ray at y = p.y cross this segment?
            let straddles = (a.y > p.y) != (b.y > p.y)
            if straddles {
                // X coordinate of the segment at height p.y.
                let t = (p.y - a.y) / (b.y - a.y)
                let xCross = a.x + t * (b.x - a.x)
                if xCross > p.x {
                    crossings += 1
                }
            }
        }
        return crossings % 2 == 1
    }

    /// Intersects the infinite line (origin + dir * t) with segment [a, b].
    /// Returns the parameter `t` (signed distance along `dir` when `dir` is
    /// unit length) if the intersection lies within the segment, else nil.
    private func rayParameter(
        origin: SIMD2<Float>,
        dir: SIMD2<Float>,
        a: SIMD2<Float>,
        b: SIMD2<Float>
    ) -> Float? {
        let e = b - a
        // Solve origin + dir * t = a + e * u  ->  2x2 linear system.
        let denom = dir.x * (-e.y) - dir.y * (-e.x)
        if abs(denom) < 1e-12 {
            return nil // parallel
        }
        let diff = a - origin
        let t = (diff.x * (-e.y) - diff.y * (-e.x)) / denom
        let u = (dir.x * diff.y - dir.y * diff.x) / denom
        // u must land within the segment (with a small tolerance).
        if u < -1e-4 || u > 1 + 1e-4 {
            return nil
        }
        return t
    }
}

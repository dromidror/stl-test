import Foundation
import SceneKit
import simd

/// Builds SceneKit geometry and nodes from a parsed STL mesh.
enum STLGeometryBuilder {

    /// Creates an `SCNGeometry` from the mesh.
    ///
    /// Each triangle contributes three unique vertices so that flat-shaded
    /// facets render crisply. Normals from the STL file are used when valid,
    /// otherwise they are computed from the triangle winding.
    static func makeGeometry(from mesh: STLMesh) -> SCNGeometry {
        var positions = [SCNVector3]()
        var normals = [SCNVector3]()
        var indices = [Int32]()

        positions.reserveCapacity(mesh.triangles.count * 3)
        normals.reserveCapacity(mesh.triangles.count * 3)
        indices.reserveCapacity(mesh.triangles.count * 3)

        var index: Int32 = 0
        for tri in mesh.triangles {
            let n = resolvedNormal(for: tri)
            for v in [tri.v0, tri.v1, tri.v2] {
                positions.append(SCNVector3(v.x, v.y, v.z))
                normals.append(SCNVector3(n.x, n.y, n.z))
                indices.append(index)
                index += 1
            }
        }

        let vertexSource = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(calibratedRed: 0.72, green: 0.74, blue: 0.78, alpha: 1.0)
        material.metalness.contents = 0.15
        material.roughness.contents = 0.45
        material.isDoubleSided = true
        geometry.materials = [material]

        return geometry
    }

    /// Returns a valid normal for the triangle, computing one if the stored
    /// normal is zero or degenerate.
    private static func resolvedNormal(for tri: STLTriangle) -> SIMD3<Float> {
        let stored = tri.normal
        if simd_length(stored) > 0.0001 {
            return simd_normalize(stored)
        }
        let computed = simd_cross(tri.v1 - tri.v0, tri.v2 - tri.v0)
        let len = simd_length(computed)
        return len > 0.0001 ? computed / len : SIMD3<Float>(0, 0, 1)
    }

    /// Builds a node containing the geometry, centered at the origin and scaled
    /// to a consistent size so any model frames nicely on load.
    static func makeNode(from mesh: STLMesh) -> SCNNode {
        let geometry = makeGeometry(from: mesh)
        let node = SCNNode(geometry: geometry)

        let box = mesh.boundingBox
        let center = (box.min + box.max) * 0.5
        let extent = box.max - box.min
        let maxDimension = max(extent.x, max(extent.y, extent.z))

        // Center the geometry on the origin.
        node.position = SCNVector3(0, 0, 0)
        node.pivot = SCNMatrix4MakeTranslation(
            CGFloat(center.x), CGFloat(center.y), CGFloat(center.z)
        )

        // Normalize scale so the largest dimension is ~10 units.
        if maxDimension > 0.0001 {
            let scale = 10.0 / maxDimension
            node.scale = SCNVector3(scale, scale, scale)
        }

        return node
    }
}

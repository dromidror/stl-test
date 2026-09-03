import Foundation
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

/// The uniform type for STL files. STL has no ubiquitous system-registered UTI,
/// so we declare one based on its filename extension.
extension UTType {
    static var stl: UTType {
        UTType(filenameExtension: "stl") ?? .data
    }
}

/// Observable state for the currently loaded STL model.
@MainActor
final class ModelStore: ObservableObject {
    @Published var modelNode: SCNNode?
    @Published var mesh: STLMesh?
    @Published var fileName: String?
    @Published var triangleCount: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Loads and parses an STL file at the given URL on a background queue,
    /// then publishes the resulting node on the main actor.
    func load(url: URL) {
        isLoading = true
        errorMessage = nil

        let needsAccess = url.startAccessingSecurityScopedResource()

        Task.detached(priority: .userInitiated) {
            defer {
                if needsAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let mesh = try STLParser.parse(url: url)
                let node = STLGeometryBuilder.makeNode(from: mesh)
                let count = mesh.triangles.count

                await MainActor.run {
                    self.modelNode = node
                    self.mesh = mesh
                    self.fileName = url.lastPathComponent
                    self.triangleCount = count
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

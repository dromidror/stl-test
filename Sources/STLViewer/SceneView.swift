import SwiftUI
import SceneKit

/// A SwiftUI wrapper around `SCNView` that renders the current STL node with
/// interactive orbit/zoom/pan camera controls.
struct STLSceneView: NSViewRepresentable {
    /// The node to display, or nil when nothing is loaded.
    var modelNode: SCNNode?

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard let scene = view.scene else { return }

        // Remove any previously loaded model.
        scene.rootNode.childNode(withName: "stlModel", recursively: false)?.removeFromParentNode()

        if let modelNode {
            modelNode.name = "stlModel"
            scene.rootNode.addChildNode(modelNode)
        }
    }

    /// Builds a scene with a camera and three-point-style lighting.
    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        // Camera
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 1000
        camera.wantsHDR = true
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 28)
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)

        // Key light
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 900
        keyLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(keyLight)

        // Fill light
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 400
        fillLight.eulerAngles = SCNVector3(Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fillLight)

        // Ambient light
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 250
        scene.rootNode.addChildNode(ambient)

        return scene
    }
}

import SwiftUI
import simd

/// Displays a 2D cross-section of the loaded model. Standard STL orientation is
/// X = width, Y = depth, Z = height. The cut can be Horizontal (XY plane at a
/// constant Z height) or Vertical (XZ plane at a constant Y depth). The chosen
/// plane's two axes map to the 2D view (horizontal u, vertical v), centered on
/// the model center so the slice stays put as the cut position changes.
///
/// Maps between plane (u, v) coordinates and view (screen) coordinates for a given
/// canvas size, placing the model center at the view center. Shared by drawing
/// and hit-testing so a clicked point maps back to the same model coordinates
/// that were drawn.
private struct SectionProjection {
    let center: CGPoint
    let scale: CGFloat
    let modelCenter: SIMD2<Float>

    init(size: CGSize, modelCenter: SIMD2<Float>, halfExtent: Float) {
        self.center = CGPoint(x: size.width / 2, y: size.height / 2)
        let usable = min(size.width, size.height) * 0.9
        self.scale = CGFloat(usable) / CGFloat(max(halfExtent, 1e-4) * 2)
        self.modelCenter = modelCenter
    }

    /// Model XY -> view point (Y flipped so +Y is up).
    func project(_ p: SIMD2<Float>) -> CGPoint {
        let dx = CGFloat(p.x - modelCenter.x) * scale
        let dy = CGFloat(p.y - modelCenter.y) * scale
        return CGPoint(x: center.x + dx, y: center.y - dy)
    }

    /// View point -> model XY (inverse of `project`).
    func unproject(_ pt: CGPoint) -> SIMD2<Float> {
        let mx = Float((pt.x - center.x) / scale) + modelCenter.x
        let my = Float((center.y - pt.y) / scale) + modelCenter.y
        return SIMD2<Float>(mx, my)
    }
}

struct CrossSectionView: View {
    let mesh: STLMesh

    /// Position of the cutting plane along its normal axis.
    @State private var z: Float = 0
    @State private var didInitialize = false

    /// The cut orientation (horizontal = XY plane, vertical = XZ plane).
    @State private var orientation: CutOrientation = .horizontal

    /// The user-placed crosshair position, in the slice plane's (u, v) coords.
    @State private var cursor: SIMD2<Float>?

    /// The local section width at the current cursor, recomputed on demand.
    private var cursorWidth: CrossSectionWidth? {
        guard let cursor else { return nil }
        return CrossSectionSlicer.slice(mesh: mesh, at: z, orientation: orientation)
            .width(at: cursor)
    }

    /// The range of the slice axis, used to bound the slider.
    private var sliceRange: ClosedRange<Float> {
        let box = mesh.boundingBox
        let axis = orientation.sliceAxis
        let lo = box.min[axis]
        let hi = box.max[axis]
        return lo < hi ? lo...hi : lo...(lo + 1)
    }

    /// The center of the model in the current plane's (u, v) coords — the
    /// origin of the 2D view.
    private var planeCenter: SIMD2<Float> {
        let box = mesh.boundingBox
        let (u, v) = orientation.planeAxes
        let center = (box.min + box.max) * 0.5
        return SIMD2<Float>(center[u], center[v])
    }

    /// Half-extent (in the plane's axes) used to compute a fit-to-view scale.
    private var planeHalfExtent: Float {
        let box = mesh.boundingBox
        let (u, v) = orientation.planeAxes
        let eu = (box.max[u] - box.min[u]) * 0.5
        let ev = (box.max[v] - box.min[v]) * 0.5
        return max(eu, ev)
    }

    /// Formats the cursor's full X/Y/Z model position. The two in-plane axes
    /// come from the cursor (u, v); the third is the current slice position.
    private func cursorReadout(_ c: SIMD2<Float>) -> String {
        var coords = [Float](repeating: 0, count: 3)
        let (u, v) = orientation.planeAxes
        coords[u] = c.x
        coords[v] = c.y
        coords[orientation.sliceAxis] = z
        return String(
            format: "Cursor:  X %.3f   Y %.3f   Z %.3f",
            coords[0], coords[1], coords[2]
        )
    }

    /// Reset the cursor and re-center the slider when the orientation changes,
    /// since the 2D coordinate system and slice axis both change meaning.
    private func resetForOrientation() {
        cursor = nil
        let box = mesh.boundingBox
        let axis = orientation.sliceAxis
        z = (box.min[axis] + box.max[axis]) * 0.5
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let section = CrossSectionSlicer.slice(mesh: mesh, at: z, orientation: orientation)
                let projection = SectionProjection(
                    size: geo.size,
                    modelCenter: planeCenter,
                    halfExtent: planeHalfExtent
                )
                let widthMeasure = cursor.flatMap { section.width(at: $0) }
                Canvas { context, size in
                    draw(
                        section: section,
                        projection: projection,
                        widthMeasure: widthMeasure,
                        in: context,
                        size: size
                    )
                }
                .background(Color(nsColor: .textBackgroundColor))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let clicked = projection.unproject(value.location)
                            // Snap to the nearest point on the model's contour.
                            cursor = section.nearestPoint(to: clicked) ?? clicked
                        }
                )
            }

            controls
        }
        .onAppear {
            if !didInitialize {
                // Start at the middle of the slice axis.
                let box = mesh.boundingBox
                let axis = orientation.sliceAxis
                z = (box.min[axis] + box.max[axis]) * 0.5
                didInitialize = true
            }
        }
        .onChange(of: orientation) { _ in
            resetForOrientation()
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Cut")
                    .font(.callout)
                Picker("Cut", selection: $orientation) {
                    ForEach(CutOrientation.allCases) { o in
                        Text(o.rawValue).tag(o)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }

            HStack {
                Text(orientation.sliceAxisLabel)
                    .font(.callout)
                    .frame(width: 70, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(z) },
                        set: { z = Float($0) }
                    ),
                    in: Double(sliceRange.lowerBound)...Double(sliceRange.upperBound)
                )
                Text(String(format: "%.3f", z))
                    .font(.system(.callout, design: .monospaced))
                    .frame(width: 70, alignment: .trailing)
            }

            HStack {
                Image(systemName: "scope")
                    .foregroundStyle(.red)
                if let cursor {
                    Text(cursorReadout(cursor))
                        .font(.system(.callout, design: .monospaced))
                    if let w = cursorWidth, w.width > 1e-6 {
                        Text(String(format: "Width %.3f", w.width))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.yellow.opacity(0.12), in: Capsule())
                    } else {
                        Text("Width n/a")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear") { self.cursor = nil }
                } else {
                    Text("Click in the view to place a crosshair cursor")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(.bar)
    }

    /// Renders the segments into the canvas using the shared projection so the
    /// drawn geometry lines up with hit-testing of clicks.
    private func draw(
        section: CrossSection,
        projection: SectionProjection,
        widthMeasure: CrossSectionWidth?,
        in context: GraphicsContext,
        size: CGSize
    ) {
        let center = projection.center

        // Faint axes marking the center of the view (= model center).
        var axes = Path()
        axes.move(to: CGPoint(x: 0, y: center.y))
        axes.addLine(to: CGPoint(x: size.width, y: center.y))
        axes.move(to: CGPoint(x: center.x, y: 0))
        axes.addLine(to: CGPoint(x: center.x, y: size.height))
        context.stroke(axes, with: .color(.gray.opacity(0.25)), lineWidth: 1)

        if section.segments.isEmpty {
            let text = Text("No intersection at this position")
                .foregroundColor(.secondary)
            context.draw(text, at: center)
        } else {
            var path = Path()
            for seg in section.segments {
                path.move(to: projection.project(seg.a))
                path.addLine(to: projection.project(seg.b))
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        }

        // Draw the width measurement line (perpendicular across the section).
        if let w = widthMeasure, w.width > 1e-6 {
            var line = Path()
            line.move(to: projection.project(w.p0))
            line.addLine(to: projection.project(w.p1))
            context.stroke(
                line,
                with: .color(.yellow),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
            // End ticks at the two tangent points.
            for p in [w.p0, w.p1] {
                let vp = projection.project(p)
                let dot = Path(ellipseIn: CGRect(x: vp.x - 2, y: vp.y - 2, width: 4, height: 4))
                context.fill(dot, with: .color(.yellow))
            }
        }

        // Draw the user-placed crosshair cursor on top.
        if let cursor {
            drawCursor(at: projection.project(cursor), in: context, size: size)
        }
    }

    /// Draws a crosshair marker with a small center dot at the given view point.
    private func drawCursor(at point: CGPoint, in context: GraphicsContext, size: CGSize) {
        let arm: CGFloat = 12
        var cross = Path()
        cross.move(to: CGPoint(x: point.x - arm, y: point.y))
        cross.addLine(to: CGPoint(x: point.x + arm, y: point.y))
        cross.move(to: CGPoint(x: point.x, y: point.y - arm))
        cross.addLine(to: CGPoint(x: point.x, y: point.y + arm))
        context.stroke(cross, with: .color(.red), lineWidth: 1.5)

        let dot = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
        context.fill(dot, with: .color(.red))
    }
}

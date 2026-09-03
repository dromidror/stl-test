import SwiftUI
import simd

/// Displays a 2D cross-section of the loaded model, sliced by the XY plane at
/// an adjustable Z (near/far) depth. X maps to the horizontal axis and Y to the
/// vertical axis. The view is centered on the model's center so the slice stays
/// put as the depth changes.
/// Maps between model XY coordinates and view (screen) coordinates for a given
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

    @State private var z: Float = 0
    @State private var didInitialize = false

    /// The user-placed crosshair position, in model XY coordinates.
    @State private var cursor: SIMD2<Float>?

    /// The local section width at the current cursor, recomputed on demand.
    private var cursorWidth: CrossSectionWidth? {
        guard let cursor else { return nil }
        return CrossSectionSlicer.slice(mesh: mesh, atZ: z).width(at: cursor)
    }

    /// The model's Z range, used to bound the slider.
    private var zRange: ClosedRange<Float> {
        let box = mesh.boundingBox
        let lo = box.min.z
        let hi = box.max.z
        return lo < hi ? lo...hi : lo...(lo + 1)
    }

    /// The XY center of the model — the origin of the 2D view.
    private var modelCenterXY: SIMD2<Float> {
        let box = mesh.boundingBox
        return SIMD2<Float>(
            (box.min.x + box.max.x) * 0.5,
            (box.min.y + box.max.y) * 0.5
        )
    }

    /// Half-extent used to compute a fit-to-view scale.
    private var modelHalfExtentXY: Float {
        let box = mesh.boundingBox
        let ex = (box.max.x - box.min.x) * 0.5
        let ey = (box.max.y - box.min.y) * 0.5
        return max(ex, ey)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let section = CrossSectionSlicer.slice(mesh: mesh, atZ: z)
                let projection = SectionProjection(
                    size: geo.size,
                    modelCenter: modelCenterXY,
                    halfExtent: modelHalfExtentXY
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
                // Start at the mid-height of the model.
                let box = mesh.boundingBox
                z = (box.min.z + box.max.z) * 0.5
                didInitialize = true
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Z depth")
                    .font(.callout)
                Slider(
                    value: Binding(
                        get: { Double(z) },
                        set: { z = Float($0) }
                    ),
                    in: Double(zRange.lowerBound)...Double(zRange.upperBound)
                )
                Text(String(format: "%.3f", z))
                    .font(.system(.callout, design: .monospaced))
                    .frame(width: 70, alignment: .trailing)
            }

            HStack {
                Image(systemName: "scope")
                    .foregroundStyle(.red)
                if let cursor {
                    Text(String(format: "Cursor:  X %.3f   Y %.3f   Z %.3f", cursor.x, cursor.y, z))
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
            let text = Text("No intersection at this depth")
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

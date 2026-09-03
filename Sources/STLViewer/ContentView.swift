import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ModelStore
    @State private var isImporterPresented = false

    var body: some View {
        ZStack {
            if store.modelNode != nil {
                STLSceneView(modelNode: store.modelNode)
                    .ignoresSafeArea()
            } else {
                emptyState
            }

            if store.isLoading {
                ProgressView("Loading model…")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Open STL", systemImage: "folder")
                }
            }
        }
        .navigationTitle(store.fileName ?? "STL Viewer")
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.stl, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    store.load(url: url)
                }
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .overlay(alignment: .bottom) {
            if let name = store.fileName, store.modelNode != nil {
                Text("\(name)  ·  \(store.triangleCount) triangles")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .alert(
            "Could not open file",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)
            Text("No model loaded")
                .font(.title2)
            Text("Open an STL file to view it in 3D.")
                .foregroundStyle(.secondary)
            Button("Open STL File…") {
                isImporterPresented = true
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

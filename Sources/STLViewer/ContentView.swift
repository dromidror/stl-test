import SwiftUI
import UniformTypeIdentifiers

/// The available ways to view the loaded model.
enum ViewMode: String, CaseIterable, Identifiable {
    case model = "3D Model"
    case crossSection = "Cross Section"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .model: return "cube"
        case .crossSection: return "square.dashed"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ModelStore
    @State private var isImporterPresented = false
    @State private var viewMode: ViewMode = .model

    var body: some View {
        ZStack {
            if store.modelNode != nil {
                switch viewMode {
                case .model:
                    STLSceneView(modelNode: store.modelNode)
                        .ignoresSafeArea()
                case .crossSection:
                    if let mesh = store.mesh {
                        CrossSectionView(mesh: mesh)
                    }
                }
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
            if store.modelNode != nil {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
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
        .overlay(alignment: .topLeading) {
            if let name = store.fileName, store.modelNode != nil {
                Text("\(name)  ·  \(store.triangleCount) triangles")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
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

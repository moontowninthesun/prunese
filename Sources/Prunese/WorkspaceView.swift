import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    private enum Panel: String, Identifiable {
        case importRoute, warnings, walkTest
        var id: Self { self }
    }

    @Binding var document: LevelDocument
    @State private var selection: MapSelection? = .route
    @State private var zoom: MapZoom?
    @State private var snap = true
    @State private var panel: Panel?
    @State private var importing = false
    @State private var imports: [RouteDraft] = []
    @State private var selectedImport: Int?
    @State private var errorMessage: String?
    @State private var exportedName: String?

    private var draft: RouteDraft { document.draft }
    private var issues: [RouteWarning] { draft.warnings() }
    private var selectedItem: RouteItem? {
        guard case .item(let id) = selection else { return nil }
        return draft.items.first(where: { $0.id == id })
    }

    var body: some View {
        HSplitView {
            outline
                .frame(minWidth: 174, idealWidth: 213, maxWidth: 300)
            stage
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            inspector
                .frame(minWidth: 238, idealWidth: 274, maxWidth: 370)
        }
        .frame(minWidth: 920, minHeight: 550)
        .toolbar { toolbar }
        .fileImporter(isPresented: $importing, allowedContentTypes: [Self.javascript, .json, .plainText]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                imports = try RouteCodec.drafts(from: Data(contentsOf: url, options: .mappedIfSafe),
                                                table: draft.table, stage: draft.stage)
                selectedImport = imports.indices.first
                panel = .importRoute
            } catch { errorMessage = error.localizedDescription }
        }
        .sheet(item: $panel) { panel in
            switch panel {
            case .importRoute: importSheet
            case .warnings: warningSheet
            case .walkTest: WalkTestView(draft: draft) { self.panel = nil }
            }
        }
        .alert("Prunese", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private static var javascript: UTType { UTType(filenameExtension: "js") ?? .plainText }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                ForEach(RouteLayer.allCases) { layer in
                    Button { add(layer) } label: { Label(layer.itemName, systemImage: layer.symbol) }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add terrain, enemies, props, or pickups")
        }
        ToolbarItemGroup {
            Button { importing = true } label: { Label("Import Route", systemImage: "square.and.arrow.down") }
                .help("Import a JavaScript route table, override, or JSON route")
            Button { exportRoute() } label: { Label("Export Route", systemImage: "square.and.arrow.up") }
                .help("Export the current stage as a JavaScript route override")
            Button { panel = .walkTest } label: { Label("Walk Test", systemImage: "play.fill") }
                .help("Run and jump through the terrain")
        }
    }

    private var outline: some View {
        List(selection: $selection) {
            Section("Level") {
                Label("Route", systemImage: "map").tag(MapSelection.route)
                Label("Boss anchor", systemImage: "flag.checkered").tag(MapSelection.boss)
            }
            ForEach(RouteLayer.allCases) { layer in
                let group = draft.items(on: layer)
                if !group.isEmpty {
                    Section(layer.title) {
                        ForEach(group) { item in
                            HStack(spacing: 7) {
                                Image(systemName: layer.symbol)
                                    .foregroundStyle(Color(nsColor: StagePainter.color(for: layer)))
                                    .frame(width: 15)
                                Text(item.label).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(displayNumber(item.x))
                                    .foregroundStyle(.secondary)
                                    .font(.caption.monospacedDigit())
                            }
                            .tag(MapSelection.item(item.id))
                            .contextMenu {
                                Button("Duplicate") { duplicate(item) }
                                Button("Delete", role: .destructive) { remove(item.id) }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Level layers")
    }

    private var stage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.title.isEmpty ? "Untitled route" : draft.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(draft.table.title)  ·  Stage \(draft.stage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Snap", isOn: $snap)
                    .toggleStyle(.checkbox)
                    .help("Snap drags to 8 units. Hold Option for fine movement.")
                Button("Fit") { zoom = MapZoom(action: .fit) }
                    .help("Fit the entire route")
                ControlGroup {
                    Button { zoom = MapZoom(action: .outwards) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("Zoom out")
                    Button { zoom = MapZoom(action: .inwards) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("Zoom in")
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            Divider()
            StageCanvas(draft: draft, selection: selection, snap: snap, zoom: zoom,
                        select: { selection = $0 }, updateItem: replace, moveBoss: { x in
                            edit { $0.boss = x }
                        }, delete: deleteSelection)
                .accessibilityLabel("Route map")
            Divider()
            HStack(spacing: 12) {
                legend("Terrain", .ground)
                legend("Enemy", .cast)
                legend("Pickup", .pickups)
                Spacer()
                if let exportedName {
                    Text("Exported \(exportedName)").lineLimit(1).foregroundStyle(.secondary)
                }
                Button {
                    panel = .warnings
                } label: {
                    Label(issues.isEmpty ? "Checks passed" : "\(issues.count) \(issues.count == 1 ? "issue" : "issues")",
                          systemImage: issues.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(issues.isEmpty ? Color.secondary : Color.orange)
                }
                .buttonStyle(.borderless)
                .help("Show route checks")
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(height: 32)
        }
    }

    private func legend(_ title: String, _ layer: RouteLayer) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: StagePainter.color(for: layer)))
                .frame(width: 8, height: 8)
            Text(title).foregroundStyle(.secondary)
        }
    }

    private var inspector: some View {
        Form {
            if let item = selectedItem {
                itemInspector(item)
            } else if selection == .boss {
                Section("Boss anchor") {
                    numberField("X", value: routeBinding(\.boss))
                    Text("The game sets the boss’s height and encounter for the stage slot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                routeInspector
            }
        }
        .formStyle(.grouped)
        .accessibilityLabel("Inspector")
    }

    @ViewBuilder
    private var routeInspector: some View {
        Section("Route") {
            TextField("Name", text: routeBinding(\.title))
            Picker("Tour", selection: Binding(get: { draft.table }, set: { table in
                edit {
                    $0.table = table
                    $0.stage = table.stages.first ?? 2
                    if !table.materials.contains($0.material) { $0.material = table.materials[0] }
                }
            })) {
                ForEach(RouteTable.allCases) { table in Text(table.title).tag(table) }
            }
            Picker("Stage slot", selection: routeBinding(\.stage)) {
                ForEach(Array(Set(draft.table.stages).union([draft.stage])).sorted(), id: \.self) { stage in
                    Text("\(stage)").tag(stage)
                }
            }
            numberField("Length", value: routeBinding(\.length))
            Picker("Material", selection: routeBinding(\.material)) {
                ForEach(choices(draft.table.materials, including: draft.material), id: \.self) { name in
                    Text(name.capitalized).tag(name)
                }
            }
        }
        if draft.table == .planets {
            Section("Motion") {
                forMotionField("Gravity", "gravity", defaultValue: 1880)
                forMotionField("Jump speed", "jump", defaultValue: 760)
                forMotionField("Wind", "wind", defaultValue: 0)
                forMotionField("Traction", "traction", defaultValue: 1)
                forMotionField("Boss pull", "pull", defaultValue: 0)
            }
        }
        Section("Briefing") {
            TextField("Player hint", text: routeBinding(\.hint), axis: .vertical)
                .lineLimit(2...4)
            TextField("Design notes", text: routeBinding(\.notes), axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private func forMotionField(_ label: String, _ key: String, defaultValue: Double) -> some View {
        numberField(label, value: Binding(
            get: { draft.fields[key]?.number ?? defaultValue },
            set: { value in edit { $0.fields[key] = .number(value) } }
        ))
    }

    @ViewBuilder
    private func itemInspector(_ item: RouteItem) -> some View {
        Section(item.label) {
            numberField("X", value: itemNumber(item.id, at: item.layer.xIndex, defaultValue: item.x))
            if item.layer.isPlatform || item.layer == .pickups {
                numberField(item.layer.isPlatform ? "Surface Y" : "Y",
                            value: itemNumber(item.id, at: 2, defaultValue: draft.top(for: item)))
            }
            if item.layer.isPlatform {
                numberField("Width", value: itemNumber(item.id, at: 1, defaultValue: item.width))
            }
            if item.layer == .ledges {
                numberField("Vertical travel ±", value: itemNumber(item.id, at: 3, defaultValue: 0))
                Picker("Access", selection: Binding(
                    get: { item.gate ?? "" },
                    set: { gate in
                        editItem(item.id) {
                            if !gate.isEmpty && $0.number(at: 3) == nil { $0.set(.number(0), at: 3) }
                            $0.set(gate.isEmpty ? .null : .string(gate), at: 4)
                        }
                    }
                )) {
                    Text("Always open").tag("")
                    Text("Moon helmet").tag("moon-air")
                    if let gate = item.gate, gate != "moon-air" { Text(gate).tag(gate) }
                }
            }
            if item.layer.isEnemy {
                Picker("Sprite", selection: itemNumber(item.id, at: 1, defaultValue: 10)) {
                    ForEach(0...11, id: \.self) { index in
                        let candidate = RouteItem(layer: item.layer,
                                                  tuple: [.number(0), .number(Double(index)), .string("order")])
                        Text(candidate.label).tag(Double(index))
                    }
                }
                Picker("Attack", selection: itemString(item, at: 2)) {
                    Text("Throw order").tag("order")
                    Text("Knife").tag("knife")
                }
                Toggle("Set patrol height", isOn: Binding(
                    get: { item.y != nil },
                    set: { enabled in editItem(item.id) { $0.y = enabled ? draft.top(for: item) : nil } }
                ))
                if item.y != nil {
                    numberField("Patrol Y", value: itemNumber(item.id, at: 3, defaultValue: draft.top(for: item)))
                }
            }
            if item.layer == .props || item.layer == .pickups {
                let names = item.layer == .props ? draft.table.propKinds : ["plum", "juice", "parachute", "electric", "helmet", "mirror"]
                Picker("Kind", selection: itemString(item, at: 0)) {
                    ForEach(choices(names, including: item.kind), id: \.self) { name in Text(name).tag(name) }
                }
            }
        }
        Section {
            Button("Duplicate") { duplicate(item) }
            Button("Delete", role: .destructive) { remove(item.id) }
        }
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        let finite = Binding(get: { value.wrappedValue }, set: { number in
            if number.isFinite { value.wrappedValue = number }
        })
        return TextField(title, value: finite, format: .number.precision(.fractionLength(0...4)).grouping(.never))
            .multilineTextAlignment(.trailing)
    }

    private func choices(_ values: [String], including current: String) -> [String] {
        values.contains(current) ? values : values + [current]
    }

    private var importSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Route").font(.title2.bold())
            Text("Choose the stage to load into this document.").foregroundStyle(.secondary)
            List(imports.indices, id: \.self, selection: $selectedImport) { index in
                let route = imports[index]
                LabeledContent("\(route.title) · \(route.material.capitalized)",
                               value: "\(route.items.count) objects")
                    .tag(index)
            }
            .frame(minHeight: 130, idealHeight: 270)
            HStack {
                Spacer()
                Button("Cancel") { panel = nil }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    guard let selectedImport else { return }
                    document.draft = imports[selectedImport]
                    selection = .route
                    exportedName = nil
                    panel = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedImport == nil)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private var warningSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Route Checks").font(.title2.bold())
            if issues.isEmpty {
                Label("The route’s fields and coordinates are valid.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                List(issues) { issue in
                    HStack(alignment: .top) {
                        Image(systemName: issue.blocksExport ? "xmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(issue.blocksExport ? Color.red : Color.orange)
                        Text(issue.message)
                        if let id = issue.item {
                            Spacer()
                            Button("Show") {
                                selection = .item(id)
                                panel = nil
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                .frame(minHeight: 130, idealHeight: 280)
            }
            HStack {
                Spacer()
                Button("Done") { panel = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 510)
    }

    private func routeBinding<T>(_ key: WritableKeyPath<RouteDraft, T>) -> Binding<T> {
        Binding(get: { draft[keyPath: key] }, set: { value in edit { $0[keyPath: key] = value } })
    }

    private func itemNumber(_ id: UUID, at index: Int, defaultValue: Double) -> Binding<Double> {
        Binding(get: {
            draft.items.first(where: { $0.id == id })?.number(at: index) ?? defaultValue
        }, set: { value in
            if value.isFinite { editItem(id) { $0.set(.number(value), at: index) } }
        })
    }

    private func itemString(_ item: RouteItem, at index: Int) -> Binding<String> {
        Binding(get: { draft.items.first(where: { $0.id == item.id })?.string(at: index) ?? "" },
                set: { value in editItem(item.id) { $0.set(.string(value), at: index) } })
    }

    private func edit(_ change: (inout RouteDraft) -> Void) {
        var next = draft
        change(&next)
        if next != draft {
            document.draft = next
            exportedName = nil
        }
    }

    private func editItem(_ id: UUID, change: (inout RouteItem) -> Void) {
        edit { draft in
            if let index = draft.items.firstIndex(where: { $0.id == id }) { change(&draft.items[index]) }
        }
    }

    private func replace(_ item: RouteItem) { editItem(item.id) { $0 = item } }

    private func add(_ layer: RouteLayer) {
        let item = draft.newItem(on: layer, at: selectedItem.map { $0.x + max(64, $0.width) } ?? 320)
        edit { $0.items.append(item) }
        selection = .item(item.id)
    }

    private func duplicate(_ original: RouteItem) {
        var copy = original
        copy.id = UUID()
        copy.x = min(max(0, draft.mapWidth - copy.width), copy.x + 40)
        edit { $0.items.append(copy) }
        selection = .item(copy.id)
    }

    private func deleteSelection() {
        if let item = selectedItem { remove(item.id) }
    }

    private func remove(_ id: UUID) {
        edit { $0.items.removeAll { $0.id == id } }
        if selection == .item(id) { selection = .route }
    }

    private func exportRoute() {
        guard !issues.contains(where: \.blocksExport) else { panel = .warnings; return }
        do {
            let bytes = try RouteCodec.javascript(for: draft)
            let panel = NSSavePanel()
            panel.title = "Export Route"
            panel.allowedContentTypes = [Self.javascript]
            panel.nameFieldStringValue = "stage-\(draft.stage)-prunese.js"
            if panel.runModal() == .OK, let url = panel.url {
                try bytes.write(to: url, options: .atomic)
                exportedName = url.lastPathComponent
            }
        } catch { errorMessage = error.localizedDescription }
    }
}

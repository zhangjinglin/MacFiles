import AppKit
import UniformTypeIdentifiers

final class EnterOutlineView: NSOutlineView {
    var onEnter: (() -> Void)?
    var onTab: ((Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = keypad Enter. Toggle the selected directory.
        if event.keyCode == 36 || event.keyCode == 76 {
            onEnter?()
            return
        }
        if event.keyCode == 48 {
            onTab?(event.modifierFlags.contains(.shift))
            return
        }
        super.keyDown(with: event)
    }
}

final class TreeNode {
    let url: URL
    let name: String
    var icon: NSImage
    let volumeKind: Volume.Kind?
    var children: [TreeNode]?
    var isLoading = false

    init(url: URL, name: String, icon: NSImage, volumeKind: Volume.Kind? = nil) {
        self.url = url
        self.name = name
        self.icon = icon
        self.volumeKind = volumeKind
    }
}

final class TreeGroup {
    let kind: Volume.Kind
    var nodes: [TreeNode] = []

    init(kind: Volume.Kind) {
        self.kind = kind
    }
}

@MainActor
final class DirectoryTreeViewController: NSViewController {
    var onSelect: ((URL) -> Void)?
    var onTab: (() -> Void)?

    private let outlineView = EnterOutlineView()
    private var groups: [TreeGroup] = []

    private var volumeIcons: [URL: NSImage] = [:]

    private lazy var folderIcon: NSImage = {
        sizedIcon(NSWorkspace.shared.icon(for: .folder))
    }()

    private lazy var placeholderVolumeIcon: NSImage = {
        sizedIcon(NSWorkspace.shared.icon(for: .volume))
    }()

    private lazy var networkIcon: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        if let image = NSImage(
            systemSymbolName: "externaldrive.connected.to.line.below",
            accessibilityDescription: "网络磁盘"
        )?.withSymbolConfiguration(config) {
            image.isTemplate = true
            return sizedIcon(image)
        }
        return sizedIcon(NSWorkspace.shared.icon(for: .folder))
    }()

    private func sizedIcon(_ image: NSImage) -> NSImage {
        let copy = (image.copy() as? NSImage) ?? image
        copy.size = NSSize(width: 16, height: 16)
        copy.isTemplate = image.isTemplate
        return copy
    }

    /// Volume icons come from the file system, so fetch them off the main
    /// thread. A disconnected network volume can stall the query; the tree
    /// keeps showing the generic volume icon until the real one arrives.
    private func fetchVolumeIcon(for url: URL) {
        Task.detached(priority: .utility) {
            let image = NSWorkspace.shared.icon(forFile: url.path)
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.volumeIcons[url] == nil,
                      let icon = NSImage(data: data) else { return }
                icon.size = NSSize(width: 16, height: 16)
                self.volumeIcons[url] = icon
                if let node = self.groups.flatMap(\.nodes).first(where: { $0.url == url }) {
                    node.icon = icon
                    self.outlineView.reloadItem(node)
                }
            }
        }
    }

    override func loadView() {
        let column = NSTableColumn(identifier: .init("name"))
        column.title = "名称"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 14
        outlineView.rowHeight = 22
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClickRow)
        outlineView.onEnter = { [weak self] in
            self?.toggleSelected()
        }
        outlineView.onTab = { [weak self] _ in
            self?.onTab?()
        }

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)
        view = scrollView

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(volumesDidChange), name: NSWorkspace.didMountNotification, object: nil)
        center.addObserver(self, selector: #selector(volumesDidChange), name: NSWorkspace.didUnmountNotification, object: nil)

        loadVolumes(selectFirst: true)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func volumesDidChange() {
        loadVolumes(selectFirst: false)
    }

    private func loadVolumes(selectFirst: Bool) {
        let previous = selectedNode()?.url
        Task {
            let volumes = await FileSystemManager.loadVolumes()
            apply(volumes: volumes, preferredSelection: previous, selectFirst: selectFirst)
        }
    }

    private func apply(volumes: [Volume], preferredSelection: URL?, selectFirst: Bool) {
        let existingGroups = Dictionary(uniqueKeysWithValues: groups.map { ($0.kind, $0) })
        let existingNodes = Dictionary(uniqueKeysWithValues: groups.flatMap(\.nodes).map { ($0.url, $0) })

        groups = Volume.Kind.allCases.compactMap { kind in
            let volumesOfKind = volumes.filter { $0.kind == kind }
            guard !volumesOfKind.isEmpty else { return nil }
            let group = existingGroups[kind] ?? TreeGroup(kind: kind)
            group.nodes = volumesOfKind.map { volume in
                existingNodes[volume.url] ?? {
                    let icon: NSImage
                    if let cached = volumeIcons[volume.url] {
                        icon = cached
                    } else if kind == .network {
                        icon = networkIcon
                    } else {
                        icon = placeholderVolumeIcon
                        fetchVolumeIcon(for: volume.url)
                    }
                    return TreeNode(url: volume.url, name: volume.name, icon: icon, volumeKind: kind)
                }()
            }
            return group
        }

        outlineView.reloadData()
        groups.forEach { outlineView.expandItem($0) }

        let target = preferredSelection ?? (selectFirst ? groups.first?.nodes.first?.url : nil)
        var selectedURL: URL?
        if let target,
           let node = groups.flatMap(\.nodes).first(where: { $0.url == target }) {
            let row = outlineView.row(forItem: node)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                selectedURL = node.url
            }
        }

        if let selectedURL {
            onSelect?(selectedURL)
        } else if let first = groups.first?.nodes.first {
            onSelect?(first.url)
        }
    }

    private func selectedNode() -> TreeNode? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? TreeNode
    }

    @objc private func doubleClickRow() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? TreeNode else { return }
        toggle(node)
    }

    private func toggleSelected() {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? TreeNode else { return }
        toggle(node)
    }

    func focus() {
        view.window?.makeFirstResponder(outlineView)
    }

    private func toggle(_ node: TreeNode) {
        if outlineView.isItemExpanded(node) {
            outlineView.collapseItem(node)
        } else {
            loadChildrenIfNeeded(for: node)
            outlineView.expandItem(node)
        }
    }

    private func loadChildrenIfNeeded(for node: TreeNode) {
        guard node.children == nil, !node.isLoading else { return }
        node.isLoading = true
        let url = node.url
        Task {
            let directories = await FileSystemManager.subdirectories(of: url)
            node.isLoading = false
            node.children = directories.map {
                TreeNode(url: $0, name: $0.lastPathComponent, icon: folderIcon)
            }
            outlineView.reloadItem(node, reloadChildren: true)
        }
    }
}

extension DirectoryTreeViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch item {
        case nil:
            return groups.count
        case let group as TreeGroup:
            return group.nodes.count
        case let node as TreeNode:
            return node.children?.count ?? 0
        default:
            return 0
        }
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch item {
        case nil:
            return groups[index]
        case let group as TreeGroup:
            return group.nodes[index]
        case let node as TreeNode:
            return node.children![index]
        default:
            return groups[index]
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        switch item {
        case let group as TreeGroup:
            return !group.nodes.isEmpty
        case let node as TreeNode:
            if let children = node.children {
                return !children.isEmpty
            }
            return true
        default:
            return false
        }
    }
}

extension DirectoryTreeViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is TreeGroup
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        !(item is TreeGroup)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let group = item as? TreeGroup {
            let cell = reusableCell(identifier: "GroupCell")
            cell.imageView?.image = nil
            cell.textField?.stringValue = group.kind.label
            cell.textField?.font = .systemFont(ofSize: 11, weight: .semibold)
            cell.textField?.textColor = .secondaryLabelColor
            return cell
        }

        guard let node = item as? TreeNode else { return nil }
        let cell = reusableCell(identifier: "NodeCell")
        cell.textField?.stringValue = node.name
        cell.textField?.font = .systemFont(ofSize: 13)
        cell.textField?.textColor = .labelColor
        cell.imageView?.image = node.icon
        cell.imageView?.contentTintColor = node.volumeKind == .network ? .controlAccentColor : nil
        return cell
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
        loadChildrenIfNeeded(for: node)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? TreeNode else { return }
        onSelect?(node.url)
    }

    private func reusableCell(identifier: String) -> NSTableCellView {
        let id = NSUserInterfaceItemIdentifier(identifier)
        if let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            return cell
        }

        let cell = NSTableCellView()
        cell.identifier = id

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        cell.imageView = imageView

        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingMiddle
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

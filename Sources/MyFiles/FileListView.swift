import AppKit
import QuickLookUI
import QuickLookThumbnailing
import UniformTypeIdentifiers

final class EnterTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onSpace: (() -> Void)?
    var onTab: ((Bool) -> Void)?
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = keypad Enter. Always open, never rename.
        if event.keyCode == 36 || event.keyCode == 76 {
            onEnter?()
            return
        }
        // 49 = Space. Toggles the Quick Look preview.
        if event.keyCode == 49 {
            onSpace?()
            return
        }
        if event.keyCode == 48 {
            onTab?(event.modifierFlags.contains(.shift))
            return
        }
        // 51 = Delete (Backspace). Command+Delete removes the selection.
        if event.keyCode == 51, event.modifierFlags.contains(.command) {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }

    /// Right-clicking a row selects it first so the context menu acts on it.
    override func menu(for event: NSEvent) -> NSMenu? {
        let clicked = row(at: convert(event.locationInWindow, from: nil))
        guard clicked >= 0 else { return nil }
        selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        return menu
    }
}

final class FileIconCollectionView: NSCollectionView {
    var onEnter: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onSpace: (() -> Void)?
    var onTab: ((Bool) -> Void)?
    var onDelete: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onEnter?()
            return
        }
        if event.keyCode == 49 {
            onSpace?()
            return
        }
        if event.keyCode == 48 {
            onTab?(event.modifierFlags.contains(.shift))
            return
        }
        if event.keyCode == 51, event.modifierFlags.contains(.command) {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard indexPathForItem(at: point) != nil else { return }
        onDoubleClick?()
    }

    /// Right-clicking an item selects it first so the context menu acts on it.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: point) else { return nil }
        selectItems(at: [indexPath], scrollPosition: [])
        return menu
    }
}

final class FileIconItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileIconItem")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private(set) var representedURL: URL?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        view = container

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 2
        nameLabel.cell?.wraps = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(nameLabel)
        let iconWidth = iconView.widthAnchor.constraint(equalToConstant: 48)
        let iconHeight = iconView.heightAnchor.constraint(equalToConstant: 48)
        iconWidthConstraint = iconWidth
        iconHeightConstraint = iconHeight
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconWidth,
            iconHeight,
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
        ])
    }

    func configure(name: String, icon: NSImage, url: URL) {
        nameLabel.stringValue = name
        iconView.image = icon
        representedURL = url
    }

    func setIconSize(_ size: CGFloat) {
        iconWidthConstraint?.constant = size
        iconHeightConstraint?.constant = size
    }

    func setThumbnail(_ image: NSImage) {
        iconView.image = image
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor
                : NSColor.clear.cgColor
        }
    }
}

/// Generates and caches Quick Look thumbnails off the main thread. The
/// semaphore caps concurrent requests so scrolling a folder full of videos
/// cannot saturate Quick Look.
private final class ThumbnailLoader: @unchecked Sendable {
    private let cache = NSCache<NSURL, NSImage>()
    private let queue = DispatchQueue(label: "local.myfiles.thumbnails", qos: .utility)
    private let semaphore = DispatchSemaphore(value: 4)

    init() {
        cache.countLimit = 500
    }

    func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func load(_ url: URL, scale: CGFloat, completion: @escaping (NSImage) -> Void) {
        if let image = cache.object(forKey: url as NSURL) {
            completion(image)
            return
        }

        // Quick Look calls its completion on a background queue, and the
        // callback is delivered back to the main thread by the caller. The
        // box opts out of Sendable checking for the NSImage payload.
        let box = UncheckedBox(value: completion)
        queue.async { [self] in
            semaphore.wait()
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 128, height: 128),
                scale: scale,
                representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [self] representation, _ in
                semaphore.signal()
                guard let image = representation?.nsImage else { return }
                cache.setObject(image, forKey: url as NSURL)
                box.value(image)
            }
        }
    }
}

private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

@MainActor
final class FileListViewController: NSViewController {
    enum DisplayMode {
        case list
        case icons
    }

    var onTab: (() -> Void)?

    private let tableView = EnterTableView()
    private let collectionView = FileIconCollectionView()
    private let tableScrollView = NSScrollView()
    private let iconScrollView = NSScrollView()
    private let openWithMenu = NSMenu()
    private let thumbnails = ThumbnailLoader()
    private let statusBar = NSView()
    private let iconSizeSlider = NSSlider()
    private let errorLabel = NSTextField(labelWithString: "")
    private var items: [FileItem] = []
    private var directory: URL?
    private var loadToken = 0
    private var displayMode: DisplayMode = .list
    private var iconSize: CGFloat = 48

    override func loadView() {
        configureTable()
        configureIcons()
        configureStatusBar()

        let menu = NSMenu()
        let openWithItem = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
        openWithMenu.delegate = self
        openWithItem.submenu = openWithMenu
        menu.addItem(openWithItem)
        let deleteItem = NSMenuItem(title: "删除", action: #selector(deleteSelection), keyEquivalent: "\u{8}")
        deleteItem.keyEquivalentModifierMask = .command
        deleteItem.target = self
        menu.addItem(deleteItem)
        tableView.menu = menu
        collectionView.menu = menu

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.alignment = .center
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false
        iconScrollView.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tableScrollView)
        container.addSubview(iconScrollView)
        container.addSubview(statusBar)
        container.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            tableScrollView.topAnchor.constraint(equalTo: container.topAnchor),
            tableScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tableScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tableScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            iconScrollView.topAnchor.constraint(equalTo: container.topAnchor),
            iconScrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            iconScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 34),
            errorLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            errorLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40),
        ])
        view = container
    }

    private func configureTable() {
        let column = NSTableColumn(identifier: .init("name"))
        column.title = "名称"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.onEnter = { [weak self] in
            self?.openSelection()
        }
        tableView.onTab = { [weak self] _ in
            self?.onTab?()
        }
        tableView.onDelete = { [weak self] in
            self?.deleteSelection()
        }
        tableView.onSpace = { [weak self] in
            self?.toggleQuickLook()
        }

        tableScrollView.documentView = tableView
        tableScrollView.hasVerticalScroller = true
        tableScrollView.autohidesScrollers = true
    }

    private func configureIcons() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = itemSize(for: iconSize)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.isSelectable = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(FileIconItem.self, forItemWithIdentifier: FileIconItem.identifier)
        collectionView.onEnter = { [weak self] in
            self?.openSelection()
        }
        collectionView.onDoubleClick = { [weak self] in
            self?.openSelection()
        }
        collectionView.onTab = { [weak self] _ in
            self?.onTab?()
        }
        collectionView.onDelete = { [weak self] in
            self?.deleteSelection()
        }
        collectionView.onSpace = { [weak self] in
            self?.toggleQuickLook()
        }
        collectionView.autoresizingMask = [.width]
        collectionView.frame = NSRect(x: 0, y: 0, width: 400, height: 400)

        iconScrollView.documentView = collectionView
        iconScrollView.hasVerticalScroller = true
        iconScrollView.autohidesScrollers = true
        iconScrollView.isHidden = true
    }

    private func configureStatusBar() {
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        statusBar.isHidden = true

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(separator)

        let sizeLabel = NSTextField(labelWithString: "图标大小")
        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(sizeLabel)

        iconSizeSlider.minValue = 32
        iconSizeSlider.maxValue = 128
        iconSizeSlider.doubleValue = Double(iconSize)
        iconSizeSlider.controlSize = .small
        iconSizeSlider.isContinuous = true
        iconSizeSlider.target = self
        iconSizeSlider.action = #selector(iconSizeChanged(_:))
        iconSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(iconSizeSlider)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: statusBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),
            iconSizeSlider.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            iconSizeSlider.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            iconSizeSlider.widthAnchor.constraint(equalToConstant: 140),
            sizeLabel.trailingAnchor.constraint(equalTo: iconSizeSlider.leadingAnchor, constant: -8),
            sizeLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
        ])
    }

    private func itemSize(for iconSize: CGFloat) -> NSSize {
        NSSize(width: iconSize + 56, height: iconSize + 48)
    }

    @objc private func iconSizeChanged(_ sender: NSSlider) {
        iconSize = CGFloat(sender.doubleValue)
        for case let cell as FileIconItem in collectionView.visibleItems() {
            cell.setIconSize(iconSize)
        }
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        layout.itemSize = itemSize(for: iconSize)
        layout.invalidateLayout()
    }

    func show(directory url: URL) {
        guard directory != url else { return }
        directory = url
        loadToken += 1
        items = []
        tableView.reloadData()
        collectionView.reloadData()
        tableView.deselectAll(nil)
        collectionView.deselectAll(nil)
        errorLabel.isHidden = true

        let token = loadToken
        Task {
            let result = await FileSystemManager.items(in: url)
            guard token == loadToken else { return }
            items = result.items
            tableView.reloadData()
            collectionView.reloadData()
            let firstResponder = view.window?.firstResponder
            if firstResponder === tableView || firstResponder === collectionView {
                selectFirstRowIfNeeded()
            }
            if let message = result.errorMessage {
                errorLabel.stringValue = "无法读取目录：\(message)"
                errorLabel.isHidden = false
            }
        }
    }

    func focus() {
        view.window?.makeFirstResponder(displayMode == .list ? tableView : collectionView)
        selectFirstRowIfNeeded()
    }

    func setDisplayMode(_ mode: DisplayMode) {
        guard mode != displayMode else { return }
        let index = selectedIndex
        displayMode = mode
        tableScrollView.isHidden = mode != .list
        iconScrollView.isHidden = mode != .icons
        statusBar.isHidden = mode != .icons
        if mode == .icons {
            collectionView.frame.size.width = iconScrollView.contentSize.width
        }
        if let index {
            select(index)
        }
        view.window?.makeFirstResponder(mode == .list ? tableView : collectionView)
    }

    /// Keyboarding into an empty selection shows no highlight, so pick the
    /// first row. An existing selection is kept when focus returns.
    private func selectFirstRowIfNeeded() {
        guard selectedIndex == nil, !items.isEmpty else { return }
        select(0)
    }

    private func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        switch displayMode {
        case .list:
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        case .icons:
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.selectItems(at: Set([indexPath]), scrollPosition: [])
            collectionView.scrollToItems(at: Set([indexPath]), scrollPosition: .nearestVerticalEdge)
        }
    }

    private var selectedIndex: Int? {
        switch displayMode {
        case .list:
            let row = tableView.selectedRow
            return items.indices.contains(row) ? row : nil
        case .icons:
            guard let indexPath = collectionView.selectionIndexPaths.first,
                  items.indices.contains(indexPath.item) else { return nil }
            return indexPath.item
        }
    }

    private var selectedItem: FileItem? {
        guard let index = selectedIndex else { return nil }
        return items[index]
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        focus()
    }

    @objc private func handleDoubleClick() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        open(items[row])
    }

    private func openSelection() {
        guard let item = selectedItem else { return }
        open(item)
    }

    private func open(_ item: FileItem) {
        if item.isDirectory {
            show(directory: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    // MARK: - Quick Look

    private func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        guard selectedItem != nil else { return }
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Open With

    /// Opens the selected item with an explicitly chosen application.
    private func openSelection(withApplicationAt applicationURL: URL) {
        guard let item = selectedItem else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([item.url], withApplicationAt: applicationURL, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.presentOpenError(error, fileName: item.name)
            }
        }
    }

    @objc private func openWith(_ sender: NSMenuItem) {
        guard let applicationURL = sender.representedObject as? URL else { return }
        openSelection(withApplicationAt: applicationURL)
    }

    private func applicationIcon(for application: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: application.path)
        let resized = (icon.copy() as? NSImage) ?? icon
        resized.size = NSSize(width: 16, height: 16)
        return resized
    }

    @objc private func openWithOtherApplication() {
        guard let item = selectedItem else { return }

        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择用于打开“\(item.name)”的应用"
        panel.prompt = "打开"

        let choose: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let applicationURL = panel.url else { return }
            self?.openSelection(withApplicationAt: applicationURL)
        }
        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: choose)
        } else {
            choose(panel.runModal())
        }
    }

    private func presentOpenError(_ error: Error, fileName: String) {
        let alert = NSAlert()
        alert.messageText = "无法打开“\(fileName)”"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        if let window = view.window {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }

    // MARK: - Deletion

    private func isNetworkItem(_ item: FileItem) -> Bool {
        (try? item.url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false
    }

    @objc private func deleteSelection() {
        guard let item = selectedItem, let directory else { return }
        let isNetwork = isNetworkItem(item)

        let alert = NSAlert()
        alert.messageText = "确定要删除“\(item.name)”吗？"
        alert.informativeText = isNetwork
            ? "该项目位于网络磁盘，删除后无法恢复，不会进入废纸篓。"
            : "该项目将被移到废纸篓。"
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: isNetwork ? "永久删除" : "删除")
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "取消")

        let confirmed: (Bool) -> Void = { [weak self] ok in
            guard ok else { return }
            self?.delete(item, in: directory, isNetwork: isNetwork)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window) { confirmed($0 == .alertFirstButtonReturn) }
        } else {
            confirmed(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    private func delete(_ item: FileItem, in directory: URL, isNetwork: Bool) {
        let token = loadToken
        Task {
            let message: String?
            do {
                try await FileSystemManager.delete(item.url, isNetwork: isNetwork)
                message = nil
            } catch {
                message = error.localizedDescription
            }
            guard token == loadToken, self.directory == directory else { return }
            guard let message else {
                remove(item)
                return
            }
            let alert = NSAlert()
            alert.messageText = "无法删除“\(item.name)”"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            if let window = view.window {
                alert.beginSheetModal(for: window) { _ in }
            } else {
                alert.runModal()
            }
        }
    }

    private func remove(_ item: FileItem) {
        guard let row = items.firstIndex(where: { $0.url == item.url }) else { return }
        items.remove(at: row)
        tableView.reloadData()
        collectionView.reloadData()
        guard !items.isEmpty else { return }
        select(min(row, items.count - 1))
    }
}

extension FileListViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
}

extension FileListViewController: @preconcurrency QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        selectedItem == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        selectedItem?.url as NSURL?
    }
}

extension FileListViewController: NSCollectionViewDataSource {    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: FileIconItem.identifier, for: indexPath)
        guard let iconItem = cell as? FileIconItem, items.indices.contains(indexPath.item) else { return cell }
        let item = items[indexPath.item]
        iconItem.configure(name: item.name, icon: icon(for: item, size: iconSize), url: item.url)
        iconItem.setIconSize(iconSize)
        loadThumbnail(for: item, in: iconItem)
        return iconItem
    }

    private func loadThumbnail(for item: FileItem, in cell: FileIconItem) {
        guard supportsThumbnail(item) else { return }
        let url = item.url

        if let cached = thumbnails.cachedImage(for: url) {
            cell.setThumbnail(cached)
            return
        }

        let scale = view.window?.backingScaleFactor ?? 2
        thumbnails.load(url, scale: scale) { image in
            DispatchQueue.main.async {
                // The cell may have been reused for another file by the time
                // the thumbnail finishes, so only apply it when it still
                // represents the same URL.
                guard cell.representedURL == url else { return }
                cell.setThumbnail(image)
            }
        }
    }

    /// Only types Quick Look can preview quickly get a content thumbnail.
    /// Everything else keeps its file-type icon.
    private func supportsThumbnail(_ item: FileItem) -> Bool {
        guard !item.isDirectory else { return false }
        let type = UTType(filenameExtension: item.url.pathExtension) ?? .data
        return type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .pdf)
    }
}

extension FileListViewController: NSMenuDelegate {
    /// The submenu is rebuilt on every open so it reflects the selected item
    /// and the applications currently registered for its type.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === openWithMenu else { return }
        menu.removeAllItems()

        guard let item = selectedItem else { return }

        let applications = NSWorkspace.shared.urlsForApplications(toOpen: item.url)
        for application in applications {
            let title = FileManager.default.displayName(atPath: application.path)
            let menuItem = NSMenuItem(title: title, action: #selector(openWith(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = application
            menuItem.image = applicationIcon(for: application)
            menu.addItem(menuItem)
        }
        if !applications.isEmpty {
            menu.addItem(.separator())
        }

        let otherItem = NSMenuItem(title: "其他…", action: #selector(openWithOtherApplication), keyEquivalent: "")
        otherItem.target = self
        menu.addItem(otherItem)
    }
}

extension FileListViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(deleteSelection) else { return true }
        guard let item = selectedItem else { return false }
        menuItem.title = isNetworkItem(item) ? "永久删除" : "删除"
        return true
    }
}

extension FileListViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let id = NSUserInterfaceItemIdentifier("FileCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
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
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        cell.textField?.stringValue = item.name
        cell.imageView?.image = icon(for: item, size: 16)
        return cell
    }

    /// Uses type-based icons instead of per-file icons so a slow network
    /// volume cannot block the main thread while a row is being displayed.
    private func icon(for item: FileItem, size: CGFloat) -> NSImage {
        let systemIcon: NSImage
        if item.isDirectory {
            systemIcon = NSWorkspace.shared.icon(for: .folder)
        } else {
            let type = UTType(filenameExtension: item.url.pathExtension) ?? .data
            systemIcon = NSWorkspace.shared.icon(for: type)
        }
        let icon = (systemIcon.copy() as? NSImage) ?? systemIcon
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}

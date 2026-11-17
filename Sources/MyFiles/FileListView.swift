import AppKit
import UniformTypeIdentifiers

final class EnterTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onTab: ((Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = keypad Enter. Always open, never rename.
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

@MainActor
final class FileListViewController: NSViewController {
    var onTab: (() -> Void)?

    private let tableView = EnterTableView()
    private let errorLabel = NSTextField(labelWithString: "")
    private var items: [FileItem] = []
    private var directory: URL?
    private var loadToken = 0

    override func loadView() {
        let column = NSTableColumn(identifier: .init("name"))
        column.title = "名称"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.backgroundColor = .windowBackgroundColor
        tableView.onEnter = { [weak self] in
            self?.openSelection()
        }
        tableView.onTab = { [weak self] _ in
            self?.onTab?()
        }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.alignment = .center
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            errorLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            errorLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40),
        ])
        view = container
    }

    func show(directory url: URL) {
        guard directory != url else { return }
        directory = url
        loadToken += 1
        items = []
        tableView.reloadData()
        tableView.deselectAll(nil)
        errorLabel.isHidden = true

        let token = loadToken
        Task {
            let result = await FileSystemManager.items(in: url)
            guard token == loadToken else { return }
            items = result.items
            tableView.reloadData()
            if let message = result.errorMessage {
                errorLabel.stringValue = "无法读取目录：\(message)"
                errorLabel.isHidden = false
            }
        }
    }

    func focus() {
        view.window?.makeFirstResponder(tableView)
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
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        open(items[row])
    }

    private func open(_ item: FileItem) {
        if item.isDirectory {
            show(directory: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
}

extension FileListViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
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
        cell.imageView?.image = icon(for: item)
        return cell
    }

    /// Uses type-based icons instead of per-file icons so a slow network
    /// volume cannot block the main thread while a row is being displayed.
    private func icon(for item: FileItem) -> NSImage {
        let systemIcon: NSImage
        if item.isDirectory {
            systemIcon = NSWorkspace.shared.icon(for: .folder)
        } else {
            let type = UTType(filenameExtension: item.url.pathExtension) ?? .data
            systemIcon = NSWorkspace.shared.icon(for: type)
        }
        let icon = (systemIcon.copy() as? NSImage) ?? systemIcon
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

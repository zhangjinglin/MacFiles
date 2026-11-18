import AppKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        SplitViewController()
            .ignoresSafeArea()
    }
}

/// Hosts an NSSplitViewController so the splitter is draggable and the panes
/// are backed by AppKit views with reliable keyboard handling.
private struct SplitViewController: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> NSSplitViewController {
        BrowserSplitViewController()
    }

    func updateNSViewController(_ nsViewController: NSSplitViewController, context: Context) {}
}

private final class BrowserSplitViewController: NSSplitViewController, NSToolbarDelegate {
    private let tree = DirectoryTreeViewController()
    private let list = FileListViewController()
    private let displayModeIdentifier = NSToolbarItem.Identifier("DisplayMode")
    private var didInstallToolbar = false

    private lazy var displayModeControl: NSSegmentedControl = {
        let images = [
            NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "列表") ?? NSImage(),
            NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "图标") ?? NSImage(),
        ]
        let control = NSSegmentedControl(images: images, trackingMode: .selectOne, target: self, action: #selector(displayModeChanged(_:)))
        control.selectedSegment = 0
        control.setToolTip("列表", forSegment: 0)
        control.setToolTip("图标", forSegment: 1)
        return control
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        tree.onSelect = { [weak self] url in
            self?.list.show(directory: url)
        }
        tree.onTab = { [weak self] in
            self?.list.focus()
        }
        list.onTab = { [weak self] in
            self?.tree.focus()
        }

        let leftItem = NSSplitViewItem(viewController: tree)
        leftItem.minimumThickness = 180
        leftItem.canCollapse = false

        let rightItem = NSSplitViewItem(viewController: list)
        rightItem.minimumThickness = 300

        addSplitViewItem(leftItem)
        addSplitViewItem(rightItem)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installToolbarIfNeeded()
    }

    private func installToolbarIfNeeded() {
        guard !didInstallToolbar, let window = view.window else { return }
        didInstallToolbar = true

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    @objc private func displayModeChanged(_ sender: NSSegmentedControl) {
        list.setDisplayMode(sender.selectedSegment == 0 ? .list : .icons)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, displayModeIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .space, displayModeIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == displayModeIdentifier else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = displayModeControl
        item.label = "显示方式"
        item.paletteLabel = "显示方式"
        item.toolTip = "在列表和图标之间切换"
        return item
    }
}

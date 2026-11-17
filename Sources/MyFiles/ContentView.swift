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
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin

        let tree = DirectoryTreeViewController()
        let list = FileListViewController()
        tree.onSelect = { [weak list] url in
            list?.show(directory: url)
        }
        tree.onTab = { [weak list] in
            list?.focus()
        }
        list.onTab = { [weak tree] in
            tree?.focus()
        }

        let leftItem = NSSplitViewItem(viewController: tree)
        leftItem.minimumThickness = 180
        leftItem.canCollapse = false

        let rightItem = NSSplitViewItem(viewController: list)
        rightItem.minimumThickness = 300

        split.addSplitViewItem(leftItem)
        split.addSplitViewItem(rightItem)
        return split
    }

    func updateNSViewController(_ nsViewController: NSSplitViewController, context: Context) {}
}

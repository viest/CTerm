import AppKit

protocol SplitContainerDelegate: AnyObject {
    func splitContainerDidChangeFocus(_ paneId: String)
    func splitContainerDidChangeRatio(splitId: String, ratio: CGFloat)
}

/// Renders a SplitNode tree into nested NSSplitViews.
/// For leaf nodes: embeds the GhosttyTerminalView with autoresizingMask.
/// For split nodes: creates an NSSplitView with two child SplitContainerViews.
///
/// IMPORTANT: NSSplitView manages its children's frames directly.
/// Children of NSSplitView must NOT use auto-layout (translatesAutoresizingMaskIntoConstraints must remain true).
class SplitContainerView: NSView {
    weak var delegate: SplitContainerDelegate?
    private(set) var node: SplitNode
    private var focusedPaneId: String?

    private var splitView: NSSplitView?
    private var firstChild: SplitContainerView?
    private var secondChild: SplitContainerView?

    private var leafView: GhosttyTerminalView?
    private var leafConstraints: [NSLayoutConstraint] = []
    private var splitNodeId: String?

    private static let minPaneSize: CGFloat = 80
    private static let leafInset: CGFloat = 8

    init(node: SplitNode, focusedPaneId: String? = nil) {
        self.node = node
        self.focusedPaneId = focusedPaneId
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = GhosttyTerminalView.defaultBackgroundColor.cgColor
        buildView()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildView() {
        switch node {
        case .leaf(let id, let termView):
            buildLeaf(id: id, view: termView)
        case .split(let id, let direction, let first, let second, let ratio):
            buildSplit(id: id, direction: direction, first: first, second: second, ratio: ratio)
        }
    }

    private func buildLeaf(id: String, view: GhosttyTerminalView) {
        leafView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        leafConstraints = [
            view.topAnchor.constraint(equalTo: topAnchor, constant: Self.leafInset),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leafInset),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.leafInset),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.leafInset),
        ]
        NSLayoutConstraint.activate(leafConstraints)
    }

    private func buildSplit(id: String, direction: SplitDirection, first: SplitNode, second: SplitNode, ratio: CGFloat) {
        splitNodeId = id

        let sv = NSSplitView(frame: bounds)
        sv.isVertical = (direction == .horizontal) // isVertical=true → side-by-side
        sv.dividerStyle = .thin
        sv.delegate = self
        sv.autoresizingMask = [.width, .height]
        addSubview(sv)
        splitView = sv

        // NSSplitView children: use autoresizingMask, NOT auto-layout
        let firstContainer = SplitContainerView(node: first, focusedPaneId: focusedPaneId)
        firstContainer.delegate = delegate
        sv.addSubview(firstContainer)
        firstChild = firstContainer

        let secondContainer = SplitContainerView(node: second, focusedPaneId: focusedPaneId)
        secondContainer.delegate = delegate
        sv.addSubview(secondContainer)
        secondChild = secondContainer

        // Apply ratio after layout pass
        DispatchQueue.main.async { [weak self] in
            self?.applyRatio(ratio)
        }
    }

    // MARK: - Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        splitView?.frame = bounds
    }

    // MARK: - Ratio

    private func applyRatio(_ ratio: CGFloat) {
        guard let sv = splitView else { return }
        let totalSize = sv.isVertical ? sv.bounds.width : sv.bounds.height
        guard totalSize > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.applyRatio(ratio)
            }
            return
        }
        let position = (totalSize - sv.dividerThickness) * ratio
        sv.setPosition(position, ofDividerAt: 0)
    }

    // MARK: - Focus

    func updateFocus(_ paneId: String?) {
        focusedPaneId = paneId
        if case .split = node {
            firstChild?.updateFocus(paneId)
            secondChild?.updateFocus(paneId)
        }
    }

    // MARK: - Mouse (focus tracking)

    override func mouseDown(with event: NSEvent) {
        if case .leaf(let id, let view) = node {
            delegate?.splitContainerDidChangeFocus(id)
            view.window?.makeFirstResponder(view)
        }
        super.mouseDown(with: event)
    }

    // MARK: - Rebuild

    func rebuild(with newNode: SplitNode, focusedPaneId: String?) {
        // Remove all children
        for sub in subviews { sub.removeFromSuperview() }
        splitView = nil
        firstChild = nil
        secondChild = nil
        leafView = nil
        leafConstraints = []

        self.node = newNode
        self.focusedPaneId = focusedPaneId
        buildView()
    }

    func setDelegateRecursive(_ delegate: SplitContainerDelegate?) {
        self.delegate = delegate
        firstChild?.setDelegateRecursive(delegate)
        secondChild?.setDelegateRecursive(delegate)
    }

    func applyTerminalThemeBackground(_ settings: AppSettings) {
        layer?.backgroundColor = GhosttyTerminalView.backgroundColor(for: settings).cgColor
        firstChild?.applyTerminalThemeBackground(settings)
        secondChild?.applyTerminalThemeBackground(settings)
    }
}

// MARK: - NSSplitViewDelegate

extension SplitContainerView: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return Self.minPaneSize
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let totalSize = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        return totalSize - Self.minPaneSize
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let sv = splitView, let nodeId = splitNodeId else { return }
        guard sv.subviews.count == 2 else { return }
        let totalSize = sv.isVertical ? sv.bounds.width : sv.bounds.height
        guard totalSize > 0 else { return }
        let firstSize = sv.isVertical ? sv.subviews[0].frame.width : sv.subviews[0].frame.height
        delegate?.splitContainerDidChangeRatio(splitId: nodeId, ratio: firstSize / totalSize)
    }
}

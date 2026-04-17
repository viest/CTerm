import AppKit

enum SplitDirection {
    case horizontal  // side-by-side (left | right)
    case vertical    // top / bottom
}

indirect enum SplitNode {
    case leaf(id: String, view: GhosttyTerminalView)
    case split(id: String, direction: SplitDirection, first: SplitNode, second: SplitNode, ratio: CGFloat)

    var id: String {
        switch self {
        case .leaf(let id, _): return id
        case .split(let id, _, _, _, _): return id
        }
    }

    // MARK: - Query

    func findLeaf(_ leafId: String) -> GhosttyTerminalView? {
        switch self {
        case .leaf(let id, let view):
            return id == leafId ? view : nil
        case .split(_, _, let first, let second, _):
            return first.findLeaf(leafId) ?? second.findLeaf(leafId)
        }
    }

    func allLeaves() -> [(id: String, view: GhosttyTerminalView)] {
        switch self {
        case .leaf(let id, let view):
            return [(id, view)]
        case .split(_, _, let first, let second, _):
            return first.allLeaves() + second.allLeaves()
        }
    }

    var leafCount: Int {
        switch self {
        case .leaf: return 1
        case .split(_, _, let first, let second, _):
            return first.leafCount + second.leafCount
        }
    }

    // MARK: - Focus Navigation

    func nextLeaf(after leafId: String) -> String? {
        let leaves = allLeaves()
        guard let idx = leaves.firstIndex(where: { $0.id == leafId }) else { return nil }
        let next = (idx + 1) % leaves.count
        return leaves[next].id
    }

    func previousLeaf(before leafId: String) -> String? {
        let leaves = allLeaves()
        guard let idx = leaves.firstIndex(where: { $0.id == leafId }) else { return nil }
        let prev = (idx - 1 + leaves.count) % leaves.count
        return leaves[prev].id
    }

    // MARK: - Mutation (returns new tree)

    func splitLeaf(_ leafId: String, direction: SplitDirection, newId: String, newView: GhosttyTerminalView) -> SplitNode {
        switch self {
        case .leaf(let id, let view):
            if id == leafId {
                return .split(
                    id: UUID().uuidString,
                    direction: direction,
                    first: .leaf(id: id, view: view),
                    second: .leaf(id: newId, view: newView),
                    ratio: 0.5
                )
            }
            return self

        case .split(let id, let dir, let first, let second, let ratio):
            return .split(
                id: id,
                direction: dir,
                first: first.splitLeaf(leafId, direction: direction, newId: newId, newView: newView),
                second: second.splitLeaf(leafId, direction: direction, newId: newId, newView: newView),
                ratio: ratio
            )
        }
    }

    /// Remove a leaf. Returns the remaining tree, or nil if this was the last leaf.
    func removeLeaf(_ leafId: String) -> SplitNode? {
        switch self {
        case .leaf(let id, _):
            return id == leafId ? nil : self

        case .split(let id, let dir, let first, let second, let ratio):
            let newFirst = first.removeLeaf(leafId)
            let newSecond = second.removeLeaf(leafId)

            // If one child was removed, collapse to the other
            if newFirst == nil { return newSecond }
            if newSecond == nil { return newFirst }

            return .split(id: id, direction: dir, first: newFirst!, second: newSecond!, ratio: ratio)
        }
    }

    func equalized() -> SplitNode {
        switch self {
        case .leaf: return self
        case .split(let id, let dir, let first, let second, _):
            return .split(id: id, direction: dir, first: first.equalized(), second: second.equalized(), ratio: 0.5)
        }
    }

    /// Update the ratio for a specific split node
    func updatingRatio(splitId: String, ratio: CGFloat) -> SplitNode {
        switch self {
        case .leaf: return self
        case .split(let id, let dir, let first, let second, let r):
            let newRatio = id == splitId ? ratio : r
            return .split(
                id: id,
                direction: dir,
                first: first.updatingRatio(splitId: splitId, ratio: ratio),
                second: second.updatingRatio(splitId: splitId, ratio: ratio),
                ratio: newRatio
            )
        }
    }
}

// MARK: - Serialization for session persistence

class SplitTreeSnapshot: Codable {
    let type: String  // "leaf" or "split"
    let id: String
    let direction: String?
    let ratio: CGFloat?
    let paneId: String?
    let first: SplitTreeSnapshot?
    let second: SplitTreeSnapshot?

    init(type: String, id: String, direction: String?, ratio: CGFloat?, paneId: String?,
         first: SplitTreeSnapshot?, second: SplitTreeSnapshot?) {
        self.type = type
        self.id = id
        self.direction = direction
        self.ratio = ratio
        self.paneId = paneId
        self.first = first
        self.second = second
    }

    static func from(_ node: SplitNode) -> SplitTreeSnapshot {
        switch node {
        case .leaf(let id, _):
            return SplitTreeSnapshot(type: "leaf", id: id, direction: nil, ratio: nil, paneId: id, first: nil, second: nil)
        case .split(let id, let dir, let first, let second, let ratio):
            return SplitTreeSnapshot(
                type: "split", id: id,
                direction: dir == .horizontal ? "horizontal" : "vertical",
                ratio: ratio, paneId: nil,
                first: SplitTreeSnapshot.from(first), second: SplitTreeSnapshot.from(second)
            )
        }
    }
}

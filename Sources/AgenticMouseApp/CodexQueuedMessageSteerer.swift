import AppKit
import ApplicationServices
import os

enum CodexQueuedMessageAction: Equatable, Sendable {
    case steer
    case edit

    var exactAccessibilityLabels: Set<String> {
        switch self {
        case .steer:
            return ["steer", "submit without interrupting the model"]
        case .edit:
            return ["edit message"]
        }
    }

    var notFoundDescription: String {
        switch self {
        case .steer: return "No queued Codex message with a Steer action was found"
        case .edit: return "No queued Codex message with an Edit action was found"
        }
    }
}

/// Locates the exact controls exposed by Codex on a queued-message row.
///
/// Production Steer uses Codex's built-in Command-Return shortcut. This
/// Accessibility route remains for Edit Queued Message, whose actions menu
/// still needs the exact Steer/Delete/Actions row cluster as its anchor.
@MainActor
final class CodexQueuedMessageSteerer {
    struct SteerCandidate: Equatable {
        let index: Int
        let frame: CGRect
        let hasExactLabel: Bool
        let isEnabled: Bool
        let supportsPress: Bool
        let isInsideFocusedWindow: Bool
        let isStrictQueuedRowMatch: Bool
    }

    enum SteerCandidateSelection: Equatable {
        case strict(Int)
        case fallback(Int)
    }

    struct MenuCandidate: Equatable {
        let index: Int
        let frame: CGRect
    }

    struct BoundedTraversalResult<Node> {
        let nodes: [Node]
        let completed: Bool
    }

    private struct AXElementIdentity: Hashable {
        let element: AXUIElement

        static func == (lhs: AXElementIdentity, rhs: AXElementIdentity) -> Bool {
            CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(CFHash(element))
        }
    }

    private struct AXElementSnapshot {
        let element: AXUIElement
        let role: String?
        let labels: Set<String>
        let frame: CGRect?
        let isEnabled: Bool
        let supportsPress: Bool
    }

    private static let logger = Logger(
        subsystem: "com.ethan.agentic-mouse",
        category: "codex-queued-message"
    )

    typealias ActionError = ApplicationShortcutDispatcher.DispatchError
    typealias TargetProcessResolver = @MainActor () -> pid_t?
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool
    typealias QueuedButtonPresser = @MainActor (_ pid: pid_t, _ action: CodexQueuedMessageAction) -> Bool
    typealias UptimeProvider = @MainActor () -> TimeInterval

    static let editJourneyTimeout: TimeInterval = 1.8
    static let editAnchorTimeout: TimeInterval = 0.8

    private let targetProcessResolver: TargetProcessResolver
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider
    private let pressQueuedButtonOverride: QueuedButtonPresser?
    private let uptime: UptimeProvider
    private var editJourneyGeneration = 0
    private var isEditJourneyInFlight = false

    init(
        targetProcessResolver: @escaping TargetProcessResolver,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true },
        pressQueuedButton: QueuedButtonPresser? = nil,
        uptime: @escaping UptimeProvider = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.targetProcessResolver = targetProcessResolver
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
        self.pressQueuedButtonOverride = pressQueuedButton
        self.uptime = uptime
    }

    func perform(_ action: CodexQueuedMessageAction = .steer) -> Result<Void, ActionError> {
        guard inputAllowed() else {
            return .failure(ActionError(
                description: "Mouse commands are disabled while macOS is locked"
            ))
        }
        guard accessibilityTrusted() else {
            return .failure(ActionError(
                description: "Accessibility permission is required for Codex shortcuts"
            ))
        }
        guard let pid = targetProcessResolver() else {
            return .failure(ActionError(description: "Codex is not running"))
        }
        if action == .edit, isEditJourneyInFlight {
            return .failure(ActionError(
                description: "Edit Queued Message is already in progress"
            ))
        }

        editJourneyGeneration &+= 1
        let journeyGeneration = editJourneyGeneration
        let deadline = action == .edit
            ? uptime() + Self.editJourneyTimeout
            : .greatestFiniteMagnitude
        let anchorDeadline = action == .edit
            ? min(deadline, uptime() + Self.editAnchorTimeout)
            : deadline
        if action == .edit { isEditJourneyInFlight = true }
        defer {
            if action == .edit { isEditJourneyInFlight = false }
        }
        let shouldContinue: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            return journeyGeneration == self.editJourneyGeneration
                && self.inputAllowed()
                && self.accessibilityTrusted()
                && self.uptime() < deadline
        }
        let anchorShouldContinue: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            return journeyGeneration == self.editJourneyGeneration
                && self.inputAllowed()
                && self.accessibilityTrusted()
                && self.uptime() < anchorDeadline
        }
        let pressed = pressQueuedButtonOverride?(pid, action)
            ?? Self.pressFirstQueuedButton(
                pid: pid,
                action: action,
                shouldContinue: shouldContinue,
                anchorShouldContinue: anchorShouldContinue
            )
        guard pressed, shouldContinue() else {
            return .failure(ActionError(description: action.notFoundDescription))
        }
        return .success(())
    }

    func cancelPendingAction() {
        editJourneyGeneration &+= 1
    }

    static func isQueuedSteerButton(
        role: String?,
        title: String?,
        description: String?,
        help: String?
    ) -> Bool {
        isQueuedActionButton(
            .steer,
            role: role,
            title: title,
            description: description,
            help: help
        )
    }

    static func isQueuedActionButton(
        _ action: CodexQueuedMessageAction,
        role: String?,
        title: String?,
        description: String?,
        help: String?
    ) -> Bool {
        guard role == kAXButtonRole as String else { return false }
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedDescription = description?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedHelp = help?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Keep matching exact so a generic control whose help merely mentions
        // an action cannot be pressed accidentally.
        let exactLabels = [
            normalizedTitle,
            normalizedDescription,
            normalizedHelp,
        ].compactMap { $0 }
        return !action.exactAccessibilityLabels.isDisjoint(with: exactLabels)
    }

    private static func pressFirstQueuedButton(
        pid: pid_t,
        action: CodexQueuedMessageAction,
        shouldContinue: @MainActor () -> Bool,
        anchorShouldContinue: @MainActor () -> Bool
    ) -> Bool {
        guard shouldContinue() else { return false }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.08)
        switch action {
        case .steer:
            let elements = allElements(in: application)
            guard let focusedWindow = focusedWindow(of: application),
                  let focusedWindowFrame = frame(of: focusedWindow) else {
                logger.notice("Steer AX search stopped: focused window unavailable")
                return false
            }
            let candidates: [SteerCandidate] = elements.enumerated().compactMap { index, element in
                let hasExactLabel = isQueuedActionButton(
                    .steer,
                    role: stringAttribute(kAXRoleAttribute, of: element),
                    title: stringAttribute(kAXTitleAttribute, of: element),
                    description: stringAttribute(kAXDescriptionAttribute, of: element),
                    help: stringAttribute(kAXHelpAttribute, of: element)
                )
                guard hasExactLabel, let candidateFrame = frame(of: element) else { return nil }
                return SteerCandidate(
                    index: index,
                    frame: candidateFrame,
                    hasExactLabel: true,
                    isEnabled: isEnabled(element),
                    supportsPress: supportsPress(element),
                    isInsideFocusedWindow: sameAccessibilityElement(
                        windowElement(of: element),
                        focusedWindow
                    ) && focusedWindowFrame.contains(candidateFrame),
                    isStrictQueuedRowMatch: isInsideQueuedMessageRow(element, among: elements)
                )
            }
            guard let selection = selectSteerCandidate(candidates) else {
                logger.notice(
                    "Steer AX search found \(candidates.count, privacy: .public) exact candidates but no unambiguous visible target"
                )
                return false
            }
            let selectedIndex: Int
            let selectionReason: String
            switch selection {
            case .strict(let index):
                selectedIndex = index
                selectionReason = "strict-row"
            case .fallback(let index):
                selectedIndex = index
                selectionReason = "visual-top"
            }
            guard let selected = candidates.first(where: { $0.index == selectedIndex }) else {
                return false
            }
            logger.info(
                "Steer AX candidates=\(candidates.count, privacy: .public) role=AXButton label=exact selection=\(selectionReason, privacy: .public) frame=(\(selected.frame.minX, privacy: .public),\(selected.frame.minY, privacy: .public),\(selected.frame.width, privacy: .public),\(selected.frame.height, privacy: .public))"
            )
            guard shouldContinue() else { return false }
            let button = elements[selectedIndex]
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success

        case .edit:
            // Codex keeps Edit inside the queued row's actions popover. It is
            // absent from the Accessibility tree until that exact row menu is
            // opened. Snapshot the focused window once; repeatedly re-reading
            // every attribute from Chromium's flattened tree made this path
            // perform hundreds of thousands of synchronous AX calls.
            guard let focusedWindow = focusedWindow(of: application) else {
                logger.notice("Edit AX search stopped: focused window unavailable")
                return false
            }
            let traversal = boundedBreadthFirstTraversalResult(
                roots: [focusedWindow],
                limit: 6_000,
                identity: { AXElementIdentity(element: $0) },
                children: childElements,
                shouldContinue: anchorShouldContinue
            )
            guard traversal.completed else {
                logger.notice("Edit AX initial row search exceeded its anchor budget or safety cap")
                return false
            }
            let focusedElements = traversal.nodes
            var snapshots: [AXElementSnapshot] = []
            snapshots.reserveCapacity(12)
            for element in focusedElements {
                guard anchorShouldContinue() else {
                    logger.notice("Edit AX initial snapshot exceeded its journey budget")
                    return false
                }
                if let snapshot = queuedRowSnapshot(element) {
                    snapshots.append(snapshot)
                }
            }
            let baselineIdentities = Set(focusedElements.map {
                AXElementIdentity(element: $0)
            })
            let menuCandidates = queuedActionsMenuCandidates(in: snapshots)
            guard let menuButton = visuallyHighestUnambiguousMenuCandidate(menuCandidates) else {
                logger.notice(
                    "Edit AX search found \(menuCandidates.count, privacy: .public) strict queued-row action menus but no unambiguous target"
                )
                return false
            }
            logger.info(
                "Edit AX opening exact queued-row actions menu candidates=\(menuCandidates.count, privacy: .public)"
            )
            guard shouldContinue(),
                  AXUIElementPerformAction(
                menuButton,
                kAXPressAction as CFString
            ) == .success else {
                logger.error("Edit AX failed to press the exact queued-row actions menu")
                return false
            }

            // Search every top-level window with its own cap so a small popup
            // is never starved behind the focused conversation's large tree.
            var observedExactEditItem = false
            for attempt in 0..<20 {
                guard shouldContinue() else {
                    logger.notice("Edit AX journey cancelled before popup search completed")
                    return false
                }
                let roots = windows(of: application).sorted(by: smallerWindowFirst)
                var allMatches: [AXUIElement] = []
                for root in roots {
                    guard shouldContinue() else {
                        logger.notice("Edit AX popup search exceeded its journey budget")
                        return false
                    }
                    let limit = sameAccessibilityElement(root, focusedWindow) ? 6_000 : 1_500
                    allMatches.append(contentsOf: queuedEditMenuItems(
                        in: root,
                        limit: limit,
                        shouldContinue: shouldContinue
                    ))
                }
                let matches = deduplicatedElements(allMatches)
                let newMatches = matches.filter {
                    !baselineIdentities.contains(AXElementIdentity(element: $0))
                }
                let candidates = newMatches.isEmpty ? matches : newMatches
                observedExactEditItem = observedExactEditItem || !matches.isEmpty
                logger.debug(
                    "Edit AX popup attempt=\(attempt, privacy: .public) windows=\(roots.count, privacy: .public) exactItems=\(matches.count, privacy: .public) newItems=\(newMatches.count, privacy: .public)"
                )
                if candidates.count == 1,
                   shouldContinue(),
                   AXUIElementPerformAction(
                    candidates[0],
                    kAXPressAction as CFString
                   ) == .success {
                    logger.info("Edit AX pressed the exact Edit message item")
                    return true
                }
                if candidates.count > 1 {
                    logger.error("Edit AX rejected ambiguous exact Edit message items")
                    break
                }
                if attempt < 19 {
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                    guard shouldContinue() else {
                        logger.notice("Edit AX journey cancelled during popup wait")
                        return false
                    }
                }
            }

            // Close only a menu whose exact item was actually observed. A
            // second blind press can open the menu when the first AXPress was
            // accepted but ignored by Chromium.
            if observedExactEditItem, shouldContinue() {
                _ = AXUIElementPerformAction(menuButton, kAXPressAction as CFString)
            }
            logger.notice("Edit AX menu opened but no exact pressable Edit message item appeared")
            return false
        }
    }

    private static func queuedRowSnapshot(_ element: AXUIElement) -> AXElementSnapshot? {
        let role = stringAttribute(kAXRoleAttribute, of: element)
        guard role == kAXButtonRole as String else { return nil }
        let labels = normalizedLabels(of: element)
        guard isPotentialQueuedRowControl(role: role, labels: labels) else { return nil }
        return AXElementSnapshot(
            element: element,
            role: role,
            labels: labels,
            frame: frame(of: element),
            isEnabled: isEnabled(element),
            supportsPress: supportsPress(element)
        )
    }

    static func isPotentialQueuedRowControl(role: String?, labels: Set<String>) -> Bool {
        guard role == kAXButtonRole as String else { return false }
        let exactLabels = CodexQueuedMessageAction.steer.exactAccessibilityLabels.union([
            "delete queued message",
            "queued message actions",
        ])
        return !labels.isDisjoint(with: exactLabels)
    }

    private static func queuedActionsMenuCandidates(
        in snapshots: [AXElementSnapshot]
    ) -> [AXUIElement] {
        let steer = snapshots.filter {
            $0.role == kAXButtonRole as String
                && !$0.labels.isDisjoint(with: CodexQueuedMessageAction.steer.exactAccessibilityLabels)
                && $0.isEnabled && $0.supportsPress
        }
        let delete = snapshots.filter {
            $0.role == kAXButtonRole as String
                && $0.labels.contains("delete queued message")
                && $0.isEnabled && $0.supportsPress
        }
        return snapshots.compactMap { actions in
            guard actions.role == kAXButtonRole as String,
                  actions.labels.contains("queued message actions"),
                  actions.isEnabled,
                  actions.supportsPress,
                  let actionsFrame = actions.frame else { return nil }
            let formsRow = steer.contains { steerButton in
                guard let steerFrame = steerButton.frame else { return false }
                return delete.contains { deleteButton in
                    guard let deleteFrame = deleteButton.frame else { return false }
                    return formsQueuedMessageRow(
                        actionFrame: steerFrame,
                        deleteFrame: deleteFrame,
                        actionMenuFrame: actionsFrame
                    )
                }
            }
            return formsRow ? actions.element : nil
        }
    }

    private static func visuallyHighestUnambiguousMenuCandidate(
        _ candidates: [AXUIElement]
    ) -> AXUIElement? {
        let framed = candidates.enumerated().compactMap { index, element in
            frame(of: element).map { MenuCandidate(index: index, frame: $0) }
        }
        guard let selected = selectVisuallyHighestMenuCandidate(framed) else { return nil }
        return candidates[selected]
    }

    static func selectVisuallyHighestMenuCandidate(_ candidates: [MenuCandidate]) -> Int? {
        let sorted = candidates.sorted {
            $0.frame.minY == $1.frame.minY
                ? $0.frame.minX < $1.frame.minX
                : $0.frame.minY < $1.frame.minY
        }
        guard let first = sorted.first,
              sorted.count == 1 || abs(first.frame.minY - sorted[1].frame.minY) > 4 else {
            return nil
        }
        return first.index
    }

    private static func windows(of application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func smallerWindowFirst(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        let lhsArea = frame(of: lhs).map { $0.width * $0.height } ?? .greatestFiniteMagnitude
        let rhsArea = frame(of: rhs).map { $0.width * $0.height } ?? .greatestFiniteMagnitude
        return lhsArea < rhsArea
    }

    private static func queuedEditMenuItems(
        in root: AXUIElement,
        limit: Int,
        shouldContinue: @MainActor () -> Bool
    ) -> [AXUIElement] {
        let elements = boundedBreadthFirstTraversal(
            roots: [root],
            limit: limit,
            identity: { AXElementIdentity(element: $0) },
            children: childElements,
            shouldContinue: shouldContinue
        )
        let rootFrame = frame(of: root)
        return elements.filter { element in
            guard shouldContinue() else { return false }
            guard isQueuedEditMenuItem(element),
                  isEnabled(element),
                  supportsPress(element),
                  let itemFrame = frame(of: element),
                  isValidCandidateFrame(itemFrame) else { return false }
            return rootFrame.map { $0.contains(itemFrame) } ?? true
        }
    }

    private static func deduplicatedElements(_ elements: [AXUIElement]) -> [AXUIElement] {
        var seen: Set<AXElementIdentity> = []
        return elements.filter {
            seen.insert(AXElementIdentity(element: $0)).inserted
        }
    }

    private static func normalizedLabels(of element: AXUIElement) -> Set<String> {
        [
            stringAttribute(kAXTitleAttribute, of: element),
            stringAttribute(kAXDescriptionAttribute, of: element),
            stringAttribute(kAXHelpAttribute, of: element),
        ].compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.reduce(into: Set<String>()) { $0.insert($1) }
    }

    /// Chromium flattens the queued row's wrapper groups out of macOS's AX tree,
    /// so the row cannot be identified through a small common ancestor. Codex
    /// does expose its three controls in a stable left-to-right visual cluster:
    /// Steer, Delete queued message, and Queued message actions. Require all
    /// three exact labels, one visible row, one window, and the expected order.
    /// This keeps a generic Steer control elsewhere in Codex fail closed.
    private static func isInsideQueuedMessageRow(
        _ element: AXUIElement,
        among elements: [AXUIElement]
    ) -> Bool {
        guard let window = windowElement(of: element) else { return false }
        let steerButtons = elements.filter {
            isQueuedActionButton(
                .steer,
                role: stringAttribute(kAXRoleAttribute, of: $0),
                title: stringAttribute(kAXTitleAttribute, of: $0),
                description: stringAttribute(kAXDescriptionAttribute, of: $0),
                help: stringAttribute(kAXHelpAttribute, of: $0)
            ) && isEnabled($0)
                && supportsPress($0)
                && sameAccessibilityElement(windowElement(of: $0), window)
        }
        let deleteButtons = elements.filter {
            isExactButton($0, labels: ["delete queued message"])
                && isEnabled($0)
                && supportsPress($0)
                && sameAccessibilityElement(windowElement(of: $0), window)
        }
        let actionMenuButtons = elements.filter {
            isExactButton($0, labels: ["queued message actions"])
                && isEnabled($0)
                && supportsPress($0)
                && sameAccessibilityElement(windowElement(of: $0), window)
        }

        return steerButtons.contains { steerButton in
            guard let actionFrame = frame(of: steerButton) else { return false }
            return deleteButtons.contains { deleteButton in
                guard let deleteFrame = frame(of: deleteButton) else { return false }
                return actionMenuButtons.contains { actionMenuButton in
                    guard sameAccessibilityElement(element, steerButton)
                            || sameAccessibilityElement(element, actionMenuButton),
                          let actionMenuFrame = frame(of: actionMenuButton) else { return false }
                    return formsQueuedMessageRow(
                        actionFrame: actionFrame,
                        deleteFrame: deleteFrame,
                        actionMenuFrame: actionMenuFrame
                    )
                }
            }
        }
    }

    static func formsQueuedMessageRow(
        actionFrame: CGRect,
        deleteFrame: CGRect,
        actionMenuFrame: CGRect
    ) -> Bool {
        let frames = [actionFrame, deleteFrame, actionMenuFrame]
        guard frames.allSatisfy(isValidCandidateFrame) else { return false }
        let midYs = frames.map(\.midY)
        guard let minimumMidY = midYs.min(), let maximumMidY = midYs.max(),
              maximumMidY - minimumMidY <= 8 else { return false }
        guard actionFrame.midX < deleteFrame.midX,
              deleteFrame.midX < actionMenuFrame.midX else { return false }
        let minimumX = frames.map(\.minX).min() ?? 0
        let maximumX = frames.map(\.maxX).max() ?? .greatestFiniteMagnitude
        return maximumX - minimumX <= 512
    }

    private static func firstElement(
        in application: AXUIElement,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        allElements(in: application).first(where: predicate)
    }

    private static func allElements(in application: AXUIElement) -> [AXUIElement] {
        let roots = focusedWindow(of: application).map { [$0, application] } ?? [application]
        return boundedBreadthFirstTraversal(
            roots: roots,
            limit: 10_000,
            identity: { AXElementIdentity(element: $0) },
            children: childElements
        )
    }

    /// Traverse a bounded graph once per logical element. Chromium can expose
    /// the same AX node through several wrapper paths; counting those aliases
    /// repeatedly can exhaust the safety cap before a queued row is reached.
    static func boundedBreadthFirstTraversal<Node, Identity: Hashable>(
        roots: [Node],
        limit: Int,
        identity: (Node) -> Identity,
        children: (Node) -> [Node],
        shouldContinue: () -> Bool = { true }
    ) -> [Node] {
        boundedBreadthFirstTraversalResult(
            roots: roots,
            limit: limit,
            identity: identity,
            children: children,
            shouldContinue: shouldContinue
        ).nodes
    }

    /// Returns whether the graph was exhausted, in addition to the visited
    /// nodes. Callers that make absence claims must reject capped or cancelled
    /// traversals instead of treating a partial Accessibility tree as complete.
    static func boundedBreadthFirstTraversalResult<Node, Identity: Hashable>(
        roots: [Node],
        limit: Int,
        identity: (Node) -> Identity,
        children: (Node) -> [Node],
        shouldContinue: () -> Bool = { true }
    ) -> BoundedTraversalResult<Node> {
        guard limit > 0, shouldContinue() else {
            return BoundedTraversalResult(nodes: [], completed: false)
        }
        var pending: [Node] = []
        var seen: Set<Identity> = []
        var truncated = false
        func enqueue(_ node: Node) {
            guard shouldContinue() else {
                truncated = true
                return
            }
            guard seen.insert(identity(node)).inserted else { return }
            guard pending.count < limit else {
                truncated = true
                return
            }
            pending.append(node)
        }
        roots.forEach(enqueue)

        var cursor = 0
        while cursor < pending.count {
            guard shouldContinue() else {
                truncated = true
                break
            }
            let element = pending[cursor]
            cursor += 1
            children(element).forEach(enqueue)
        }
        return BoundedTraversalResult(
            nodes: Array(pending.prefix(cursor)),
            completed: !truncated && cursor == pending.count
        )
    }

    static func selectSteerCandidate(
        _ candidates: [SteerCandidate]
    ) -> SteerCandidateSelection? {
        let valid = candidates.filter {
            $0.hasExactLabel
                && $0.isEnabled
                && $0.supportsPress
                && $0.isInsideFocusedWindow
                && isValidCandidateFrame($0.frame)
        }
        let strict = valid.filter(\.isStrictQueuedRowMatch)
        if let index = visuallyHighestUnambiguousCandidate(in: strict)?.index {
            return .strict(index)
        }
        guard strict.isEmpty,
              let index = visuallyHighestUnambiguousCandidate(in: valid)?.index else {
            return nil
        }
        return .fallback(index)
    }

    private static func visuallyHighestUnambiguousCandidate(
        in candidates: [SteerCandidate]
    ) -> SteerCandidate? {
        guard !candidates.isEmpty else { return nil }
        let sorted = candidates.sorted {
            if $0.frame.minY == $1.frame.minY {
                return $0.frame.minX < $1.frame.minX
            }
            return $0.frame.minY < $1.frame.minY
        }
        guard sorted.count == 1
                || abs(sorted[0].frame.minY - sorted[1].frame.minY) > 4 else {
            return nil
        }
        return sorted[0]
    }

    static func isValidCandidateFrame(_ frame: CGRect) -> Bool {
        frame.minX.isFinite
            && frame.minY.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width >= 8
            && frame.height >= 8
    }

    private static func isExactButton(
        _ element: AXUIElement,
        labels: Set<String>
    ) -> Bool {
        let role = stringAttribute(kAXRoleAttribute, of: element)
        guard role == kAXButtonRole as String else { return false }
        return hasExactLabel(element, labels: labels)
    }

    private static func isQueuedEditMenuItem(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute, of: element)
        guard role == kAXMenuItemRole as String || role == kAXButtonRole as String else {
            return false
        }
        return hasExactLabel(element, labels: CodexQueuedMessageAction.edit.exactAccessibilityLabels)
    }

    private static func hasExactLabel(
        _ element: AXUIElement,
        labels: Set<String>
    ) -> Bool {
        let values = [
            stringAttribute(kAXTitleAttribute, of: element),
            stringAttribute(kAXDescriptionAttribute, of: element),
            stringAttribute(kAXHelpAttribute, of: element),
        ].compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return !labels.isDisjoint(with: values)
    }

    private static func focusedWindow(of application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &value
        ) == .success else { return nil }
        return (value as! AXUIElement?)
    }

    private static func stringAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let rawPosition = positionValue,
        let rawSize = sizeValue,
        CFGetTypeID(rawPosition) == AXValueGetTypeID(),
        CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }

        let positionAXValue = unsafeBitCast(rawPosition, to: AXValue.self)
        let sizeAXValue = unsafeBitCast(rawSize, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func windowElement(of element: AXUIElement) -> AXUIElement? {
        var candidate: AXUIElement? = element
        for _ in 0..<32 {
            guard let current = candidate else { return nil }
            if stringAttribute(kAXRoleAttribute, of: current) == kAXWindowRole as String {
                return current
            }
            candidate = parentElement(of: current)
        }
        return nil
    }

    private static func sameAccessibilityElement(
        _ lhs: AXUIElement?,
        _ rhs: AXUIElement
    ) -> Bool {
        guard let lhs else { return false }
        return CFEqual(lhs, rhs)
    }

    private static func sameAccessibilityElement(
        _ lhs: AXUIElement,
        _ rhs: AXUIElement
    ) -> Bool {
        CFEqual(lhs, rhs)
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &value
        ) == .success else { return false }
        return value as? Bool == true
    }

    private static func childElements(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func parentElement(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &value
        ) == .success else { return nil }
        return (value as! AXUIElement?)
    }

    private static func supportsPress(_ element: AXUIElement) -> Bool {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success,
              let actions = value as? [String] else { return false }
        return actions.contains(kAXPressAction as String)
    }
}

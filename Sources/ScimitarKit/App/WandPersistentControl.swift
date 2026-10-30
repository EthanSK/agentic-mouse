import Foundation
import CoreFoundation

/// A parked outline and a separate native press/release lifecycle. The wand
/// never fabricates Corsair input: it uses the same coordinator under its own source.
public struct WandPersistentCommand: Equatable {
    /// `activate` is a HUD button tap on the outlined card. `choose` is the
    /// release of a HUD button hold on it: the same action, except a wheel card
    /// enters dotted mode and home Switch App is armed for the next hold.
    /// `toggleReview` is the receiver's short HUD button double click while a review
    /// mode is selected: it flips Review changes ⇄ Stage files and nothing else.
    public enum Phase: String { case open, appSpecific, hover, navigate, qualify, motion, park, press, release, activate, choose, dismiss, exitReview, toggleReview }
    public let phase: Phase
    public let id: String
    public let sequence: Int
    public let offset: WandAngularOffset
    /// Cumulative normal HIGH mouse output for this held gesture. Only Switch App uses it.
    public let mouseX: Double?
    public static let maximumMouseX: Double = 7_200_000
    public init(_ phase: Phase, id: String, sequence: Int = 0, x: Double = 0, y: Double = 0, mouseX: Double? = nil) {
        self.phase = phase; self.id = id; self.sequence = sequence
        self.offset = .init(x:x,y:y)
        self.mouseX = mouseX
    }
    public static func decodeIfPresent(_ data: Data) throws -> Self? {
        guard let value = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              value["command"] as? String == "agentic_mouse_wand_control" else { return nil }
        guard data.count <= 512, Set(value.keys).isSubset(of:["command","version","phase","id","seq","x","y","mouseX"]),
              let v = value["version"] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(), v.doubleValue == 1,
              let phase = Phase(rawValue:value["phase"] as? String ?? ""),
              let id = value["id"] as? String, WandSelectionCommand.isValidGestureIdentifier(id),
              let seq = value["seq"] as? NSNumber, CFGetTypeID(seq) != CFBooleanGetTypeID(),
              seq.doubleValue >= 0, seq.doubleValue <= Double(Int32.max), seq.doubleValue.rounded() == seq.doubleValue
        else { throw WandSelectionCommandError.invalidField("persistent control") }
        func number(_ key: String) throws -> Double {
            guard let raw = value[key] else { return 0 }
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                  abs(n.doubleValue) <= 7200 else { throw WandSelectionCommandError.invalidField(key) }
            return n.doubleValue
        }
        var mouseX: Double?
        if let raw=value["mouseX"] {
            guard phase == .motion, let n=raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue.isFinite, abs(n.doubleValue) <= maximumMouseX
            else { throw WandSelectionCommandError.invalidField("mouseX") }
            mouseX=n.doubleValue
        }
        return try .init(phase,id:id,sequence:seq.intValue,x:number("x"),y:number("y"),mouseX:mouseX)
    }
}

/// The wand's three buttons (Ethan, 2026-10-30): the HUD button (previously
/// "Middle"), the mouse button (previously "Bottom") and the speech button
/// (previously "Top"); double-clicking the speech button was "double Top".
/// The receiver's wire phases below keep their names.
///
/// Ethan's wand HUD ("hotbar"; he calls its cards widgets, wedges or menu
/// triggers), final 2026-10-29 rules:
///
/// * Holding the HUD button shows the HUD and moves the outline; releasing uses the
///   outlined card. A one-press card acts once on release (also after a hold
///   from closed, steered to it) and the HUD stays open on it (2026-10-30;
///   home Screenshot alone parks it for the crosshair). A card that opens a page
///   (submenu, app page, Back) enters it once and stays open in wedge
///   selection: unheld motion moves the outline and never operates a card.
/// * Adjustable cards (Zoom, Volume, Spaces, Mission Control, ...) are held
///   only. Ethan: "if it's something that requires like swipes of the wand,
///   then let's make it so it only is registering my action while I'm
///   holding the HUD button down. And then when I release it, it stops."
///   Holding the HUD button on one adjusts it at once along its own axis; a click or
///   a still held release selects it (dots). While dotted and the HUD button is up,
///   wand motion does nothing, so the wand can be reset; the next hold
///   adjusts it again with a listening glow; a tap leaves dotted mode. The
///   card's press is only sent with the first actual step and is released
///   with the HUD button, so a hold without movement never fires its click action.
///   Values (Zoom, Volume, Brightness, Speed, Effort) step continuously;
///   one-action controls (Mission Control, Spaces, Pin) act once per quick
///   swipe and re-arm after the wand settles, only while held.
/// * Switch App is Ethan's exception. A tap switches once. The hold that
///   opens the HUD from closed only aims. In an already open home HUD, a
///   fresh hold on Switch App (also after aiming away and back, or Back)
///   chooses apps: Command goes down with its first step or once the hold
///   qualifies, left/right steps directly, release switches and closes.
/// * The outer layer (`WandOuterLayer`) holds ordinary one-press quick
///   actions one reach further out on their parent's wedge.
/// * Time alone never acts, and lost or late datagrams never act on a new
///   page: terminals carry their own identity, a new unheld stream or press
///   finishes a held gesture whose park was lost, and a held press with no
///   telemetry for a second is released.
/// * Ordinary actions no longer hide the HUD, so the journey bookmark
///   (`WandJourneyBookmark`) is only taken when Screenshot parks it, which
///   happens on home. Double-click dismissal, lock and teardown forget it.
///
/// | HUD state                 | HUD button up (unheld)     | HUD button held                      |
/// |---------------------------|----------------------------|--------------------------------------|
/// | wedge selection, ordinary | moves the outline          | aims; release uses the card          |
/// | wedge selection, wheel    | moves the outline          | adjusts it; release stops            |
/// | dotted (selected) wheel   | nothing (reset the wand)   | adjusts it with a listening glow     |
/// | open home, on Switch App  | moves the outline          | chooses apps; release switches       |
public final class WandPersistentController {
    public static let followUpLinger: TimeInterval = 2
    /// Unit conversion, not a second sensitivity curve: at the reference HIGH
    /// gain, the existing seven-degree detent spans 604.8 mouse counts. The
    /// receiver owns Ethan's live mouse gain/response and excludes the mouse button's LOW lane.
    private static let switchAppReferenceGain: Double = 86.4
    public var onAdjustStep: ((WheelChordDirection)->Bool)?
    /// Lets a held one-action wheel control act again after a fresh swipe.
    public var onAdjustRearm: (()->Void)?
    public var onSwitchAppStep: ((WheelChordDirection)->Bool)?
    public var onContext: ((Bool)->Void)?
    private let target: WandModeControlling
    private let scheduler: TickScheduler
    private let clock: MonotonicClock
    private let allowed: ()->Bool
    private struct Hold {
        let id:String
        var sequence:Int
        var last:WandAngularOffset = .zero
        var received:TimeInterval
        var navigation:WandRadialNavigator?
        var passiveNavigation=false
        let cell:PhysicalCell
        let pageGeneration:UInt64
        /// A held adjustment (wheel card) or the held Switch App chooser.
        var adjusting=false
        /// The wheel control being adjusted; nil for the Switch App chooser.
        var control:WheelChordControl?
        /// The card's press (or Command) has been sent; released with the HUD button.
        var pressed=false
        /// Started on a dotted card: release keeps it dotted.
        var fromDotted=false
        /// The receiver's mouse-button-held `press`/`release` lane: pressed at once,
        /// ended by `release`, never followed by activate/choose.
        var legacy=false
        var tracker = WandAdjustDetentTracker()
        /// One-action controls (Mission Control, Spaces, Pin): swipe, settle, swipe.
        var swipe = WandSwipeDetector()
        var sentSteps=0
        var netSteps=0
        var lastStepWasUp:Bool?
        enum SwitchMetric { case angle, mouse }
        var switchMetric:SwitchMetric?
        var lastMouseX:Double?
        var held:Bool { !passiveNavigation }
    }
    /// The selected (dotted) card. Nothing is pressed while it waits.
    private struct ArmedCard: Equatable {
        let cell:PhysicalCell
        // nil is home Switch App armed for its next real hold.
        let control:WheelChordControl?
        let pageGeneration:UInt64
    }
    /// A held gesture that ended without any step: its activate (tap) or
    /// choose (held release) decides what the card does.
    private struct PendingTerminal {
        let card:ArmedCard
        let fromDotted:Bool
    }
    private var hold:Hold?
    private var armed:ArmedCard?
    private var pending:PendingTerminal?
    /// A held gesture that already operated its card: its activate/choose is done.
    private var consumeNextTerminal=false
    /// The next press is the one that opened the HUD from closed: it aims.
    private var openingPress=false
    /// The current or last gesture opened the HUD from closed. A quick tap
    /// like that on home Switch App is the fast app switch, so it still
    /// hides the HUD it only flashed; nothing was chosen from an open HUD.
    private var gestureOpenedHUD=false
    /// The opening press reopened a remembered submenu: its tap only showed
    /// it, so a double click from closed still dismisses without acting.
    private var tapOnlyReopened=false
    private var concealedUntil:TimeInterval?
    /// The submenu an ordinary action hid; the next open returns there.
    /// Double-click dismissal, lock and teardown forget it.
    private var journeyBookmark:WandJourneyBookmark?
    private var lastFinished:String?
    /// The last applied review toggle; a duplicate datagram never flips back.
    private var recentReviewToggles:[String]=[]
    private var selected:PhysicalCell = .switchApp
    private var ownsHUD=false
    // Screenshot aiming outlives the hidden HUD; keep its receiver lease fresh.
    private var screenshotInteractionActive=false
    /// The Keys page generation on which a repeatable key kept the HUD open.
    private var repeatKeysGeneration:UInt64?
    /// Ethan's "Double-click to exit" reminder: only while an open Keys page is
    /// repeating keys. Any page change, close or reopen ends it.
    public var repeatKeysHintVisible:Bool {
        guard isOpen, let generation=repeatKeysGeneration else { return false }
        return target.page == .keys && !target.isWandHome && target.pageGeneration == generation
    }
    public private(set) var pinnedReviewCell: PhysicalCell?
    public var selectedReviewMode: String? { target.wandReviewAvailable ? pinnedReviewCell?.wandReviewMode : nil }
    public func clearReviewSelection() { pinnedReviewCell=nil;target.setWandReviewSelection(nil);if !isOpen && concealedUntil == nil {scheduler.stop()};onContext?(isOpen) }
    public var isOpen:Bool { ownsHUD && target.isActive }
    /// The selected (dotted) card, or armed Switch App.
    public var armedCell:PhysicalCell? { isOpen ? armed?.cell : nil }
    /// True while a completed action's HUD is hidden and its mode lingers.
    public var isConcealed:Bool { concealedUntil != nil }
    public var reviewMode: String? {
        guard isOpen, target.isWandHome, let current = hold, current.navigation == nil, !current.adjusting,
              target.wandRadialLayout.contains(current.cell) else { return nil }
        return current.cell.wandReviewMode
    }
    public var focusedCell:PhysicalCell? { isOpen ? target.pointerFocus?.cell ?? selected : nil }
    /// True only while a real HUD button hold is choosing apps on home Switch App.
    /// Derived, never stored, so aiming, armed-but-unheld Switch App, wheel
    /// cards, child pages (cell 11 is Zoom there), dismiss, lock, page change
    /// and stale telemetry all read false.
    public var switchAppAdjusting:Bool {
        guard isOpen, allowed(), target.isWandHome, let current=hold,
              current.adjusting, current.control == nil, current.navigation == nil,
              current.cell == .switchApp, target.pageGeneration == current.pageGeneration,
              clock.now-current.received <= 1 else { return false }
        return true
    }
    public init(target:WandModeControlling,scheduler:TickScheduler,clock:MonotonicClock,
                allowed:@escaping ()->Bool = {true}) {
        self.target=target;self.scheduler=scheduler;self.clock=clock;self.allowed=allowed
    }
    private func clearGesture() {
        hold=nil;armed=nil;pending=nil;consumeNextTerminal=false;openingPress=false;gestureOpenedHUD=false;tapOnlyReopened=false
    }
    public func reset(reason:ModePickerExitReason = .shuttingDown) {
        pinnedReviewCell=nil;target.setWandReviewSelection(nil)
        clearGesture();concealedUntil=nil;ownsHUD=false;screenshotInteractionActive=false;repeatKeysGeneration=nil;journeyBookmark=nil;scheduler.stop()
        if target.isActive {target.exit(reason:reason)}
        onContext?(false)
    }
    public func handle(_ command:WandPersistentCommand) {
        guard allowed() else {reset(reason:.systemSleep);return}
        if ownsHUD && !target.isActive {ownsHUD=false;clearGesture();if pinnedReviewCell == nil && !screenshotInteractionActive {scheduler.stop()}}
        defer {onContext?(isOpen)}
        // Ethan's double click while in review mode: switch to the other mode.
        if command.phase == .toggleReview {
            toggleReview(id:command.id)
            return
        }
        if concealedUntil != nil {
            switch command.phase {
            case .open, .appSpecific, .exitReview: finishConcealment()
            case .navigate, .press:
                // The receiver had not yet seen the close: this hold opens a
                // fresh HUD rather than steering the hidden one.
                finishConcealment();openHome();openingPress=true
            case .dismiss:
                // Ethan's double click dismisses properly: the next open starts at home.
                journeyBookmark=nil
                return
            case .hover, .qualify, .motion, .park, .release, .activate, .choose, .toggleReview:
                // Already hidden. Stale input from the finished hold never acts.
                return
            }
        }
        // The HUD button exits the independent review lane without opening another HUD.
        if command.phase == .exitReview {
            clearReviewSelection();releaseHeldPress();clearGesture();ownsHUD=false;repeatKeysGeneration=nil
            if target.isActive {target.exit(reason:.userRequested)}
            scheduler.stop();onContext?(false);return
        }
        if command.phase == .dismiss {
            releaseHeldPress();clearGesture();ownsHUD=false;repeatKeysGeneration=nil;journeyBookmark=nil
            if target.isActive {target.exit(reason:.userRequested)}
            if pinnedReviewCell == nil && !screenshotInteractionActive {scheduler.stop()} else {startWatchdog()}
            return
        }
        // Only the very next navigate belongs to the press that opened the
        // HUD; anything else first means that press is already over.
        if [.hover,.activate,.choose,.press].contains(command.phase) {openingPress=false}
        if command.phase == .activate || command.phase == .choose {
            guard isOpen, command.id != lastFinished else {return}
            lastFinished=command.id
            // A held gesture whose park datagram was lost ends here first.
            if let current=hold, current.held {hold=nil;endHold(current);guard isOpen else {return}}
            if consumeNextTerminal {consumeNextTerminal=false;pending=nil;return}
            if let ended=pending {pending=nil;finishPending(ended,tap:command.phase == .activate);return}
            let cell=target.pointerFocus?.cell ?? selected
            if target.isWandHome,cell.wandReviewMode != nil,target.wandReviewAvailable {
                pinnedReviewCell = pinnedReviewCell == cell ? nil : cell
                target.setWandReviewSelection(pinnedReviewCell)
                // Ethan calls these eyes mode and whole-file bang mode.
                hold=nil;armed=nil;ownsHUD=false
                if target.isActive {target.exit(reason:.userRequested)}
                startWatchdog();return
            }
            if tapOnlyReopened {
                tapOnlyReopened=false
                if command.phase == .activate {return}
            }
            if command.phase == .choose {choose(cell)} else {activate(cell)}
            return
        }
        if command.phase == .appSpecific {
            clearGesture()
            if target.isActive {target.exit(reason:.userRequested)}
            target.handle(.init(action:.openAppSpecific,source:.wand,physicalCell:.frontmostAppModeSelector,phase:.press),inputTime:clock.now)
            ownsHUD=target.isActive
            selected=WandSelectionController.startCell(for:target.page)
            if ownsHUD {target.setPointerFocus(.init(cell:selected));startWatchdog()}
            return
        }
        if command.phase == .open {
            if !target.isActive {openHome();openingPress=true}
            ownsHUD=target.isActive
            if ownsHUD {startWatchdog()}
            return
        }
        // A physical press is the hold that shows the HUD, even if the
        // receiver still believed an earlier session was open.
        if !isOpen, command.phase == .navigate, command.id != lastFinished, hold?.id != command.id {openHome();openingPress=true}
        guard isOpen else {return}
        switch command.phase {
        case .hover:
            // Unheld wand motion. In wedge selection it aims (never operating
            // a card); on a dotted card it does nothing, so the wand resets.
            guard command.id != lastFinished else { return }
            if let current=hold, current.id == command.id { return }
            // `hover` only streams while the HUD button is up: a held gesture still
            // open here lost its park. Finish it as its park would have.
            if let current=hold, current.held {
                hold=nil;lastFinished=current.id
                endHold(current)
                guard isOpen else { break }
            }
            if let card=liveArmedCard(), card.control != nil {hold=nil;showDotted(card);break}
            selected=target.pointerFocus?.cell ?? selected
            hold=Hold(id:command.id,sequence:command.sequence,last:command.offset,received:clock.now,
                      navigation:WandRadialNavigator(layout:target.wandRadialLayout,start:selected),
                      passiveNavigation:true,cell:selected,pageGeneration:target.pageGeneration)
        case .navigate, .press:
            guard command.id != lastFinished else {return}
            if hold?.id == command.id {return}
            // An earlier gesture whose terminal never arrived does nothing more.
            pending=nil;consumeNextTerminal=false
            let opening=openingPress;openingPress=false
            gestureOpenedHUD=opening
            if !opening {tapOnlyReopened=false}
            // A physical hold supersedes an unheld stream without operating it.
            if hold?.passiveNavigation == true { hold=nil }
            // A new physical press proves the old release was lost. A lost
            // aim holds nothing; a lost adjustment is let go first.
            if let stale=hold {
                hold=nil
                if stale.pressed {releasePress(stale)}
            }
            selected=target.pointerFocus?.cell ?? selected
            if command.phase == .press, target.isWandHome, selectedReviewMode != nil, let pinned=pinnedReviewCell {selected=pinned}
            guard command.phase == .navigate else {
                armed=nil
                // Operating the outlined card like a held mouse button: a
                // wheel card adjusts and Switch App chooses with motion.
                if target.isWandHome, selected == .switchApp {
                    var current=Hold(id:command.id,sequence:command.sequence,received:clock.now,
                                     navigation:nil,cell:.switchApp,pageGeneration:target.pageGeneration)
                    current.adjusting=true;current.legacy=true
                    pressSwitchApp(&current);hold=current;showAdjustment(current)
                    break
                }
                if selected.wandReviewMode == nil, let control=target.wandAdjustableControl(for:selected) {
                    var current=Hold(id:command.id,sequence:command.sequence,received:clock.now,
                                     navigation:nil,cell:selected,pageGeneration:target.pageGeneration)
                    current.adjusting=true;current.control=control;current.legacy=true
                    if pressCard(&current,control) {hold=current;showAdjustment(current)}
                    break
                }
                hold=Hold(id:command.id,sequence:command.sequence,received:clock.now,
                          navigation:nil,cell:selected,pageGeneration:target.pageGeneration)
                if selected.wandReviewMode == nil {
                    target.handle(.init(action:.select,source:.wand,physicalCell:selected,phase:.press),inputTime:clock.now)
                    keepOutline(after:selected,generation:target.pageGeneration)
                }
                break
            }
            // Holding a dotted card listens and adjusts it.
            if let card=liveArmedCard(), let control=card.control {
                beginAdjust(command,cell:card.cell,control:control,fromDotted:true)
                break
            }
            // Ethan: on an already open home HUD, a fresh hold on Switch App
            // chooses apps, also after aiming away and back or Back. The hold
            // that opened the HUD from closed only aims.
            if !opening, target.isWandHome, selected == .switchApp {
                armed=nil
                var current=Hold(id:command.id,sequence:command.sequence,received:clock.now,
                                 navigation:nil,cell:.switchApp,pageGeneration:target.pageGeneration)
                current.adjusting=true;hold=current;showAdjustment(current)
                break
            }
            armed=nil
            // A held HUD button on an adjustable wheel card in wedge selection adjusts it.
            if !opening, let control=target.wandAdjustableControl(for:selected) {
                beginAdjust(command,cell:selected,control:control,fromDotted:false)
                break
            }
            hold=Hold(id:command.id,sequence:command.sequence,received:clock.now,
                      navigation:WandRadialNavigator(layout:target.wandRadialLayout,start:selected),
                      cell:selected,pageGeneration:target.pageGeneration)
        case .qualify:
            guard var current=hold, current.held, current.id == command.id, command.sequence > current.sequence else { return }
            current.sequence=command.sequence;current.received=clock.now
            // A held Switch App chooser opens the system switcher once the
            // hold qualifies; an aiming hold just keeps its heartbeat.
            if current.adjusting, current.control == nil, !current.pressed, target.isWandHome,
               target.pageGeneration == current.pageGeneration {
                pressSwitchApp(&current)
                showAdjustment(current)
            }
            hold=current
        case .motion:
            guard var current=hold,current.id == command.id,command.sequence > current.sequence else {return}
            if current.cell.wandReviewMode != nil && !target.wandRadialLayout.contains(current.cell) {
                hold=nil;target.setPointerFocus(.init(cell:target.wandRadialLayout.center ?? .switchApp));return
            }
            let dx=command.offset.x-current.last.x,dy=command.offset.y-current.last.y
            current.sequence=command.sequence;current.last=command.offset;current.received=clock.now
            if var nav=current.navigation {
                // The wheel can change under a live hold (VS Code review cards
                // appear or disappear). Re-seat on the same card, never jump.
                let layout=target.wandRadialLayout
                if nav.layout != layout, let reseated=WandRadialNavigator(
                    layout:layout,start:layout.contains(selected) ? selected : layout.center ?? .switchApp) {
                    nav=reseated
                }
                nav.apply(deltaX:dx,deltaY:dy);current.navigation=nav;selected=nav.focusedCell
                target.setPointerFocus(armedPresentation(nav.pointerFocus))
            } else if current.adjusting, current.control == nil {
                guard target.pageGeneration == current.pageGeneration, target.isWandHome else {break}
                // The system switcher is horizontal: moving right selects the next app.
                let delta=switchAppDelta(command,angleDelta:dx,hold:&current)
                var steps=current.tracker.apply(deltaY:-delta)
                if !current.pressed, let first=steps.first {
                    // Command-Tab itself highlights the next app (a rightward
                    // step, `.physicalUp` here). Moving left first steps back
                    // past the current app to the last one.
                    pressSwitchApp(&current)
                    steps.removeFirst()
                    if first == .physicalDown {steps.insert(contentsOf:[.physicalDown,.physicalDown],at:0)}
                }
                for step in steps where current.pressed && onSwitchAppStep?(step.wheelDirection) == true {
                    current.sentSteps += 1;current.netSteps += step == .physicalUp ? 1 : -1
                    current.lastStepWasUp=step == .physicalUp
                }
                if target.isActive {showAdjustment(current)}
            } else if current.adjusting, let control=current.control {
                guard adjustable(current,control) else {break}
                // The control's own axis: left/right for Spaces, scrolling,
                // tabs and history; up/down for values.
                let travel=control.wandTravel(dx:dx,dy:dy)
                var directions:[(positive:Bool,rearm:Bool)]=[]
                if control.isWandSwipeAction {
                    if let positive=current.swipe.sample(travel:travel,now:clock.now) {directions=[(positive,true)]}
                } else {
                    directions=current.tracker.apply(deltaY:travel).map {($0 == .physicalDown,false)}
                }
                for step in directions {
                    if !current.pressed {
                        guard pressCard(&current,control) else {break}
                    }
                    if step.rearm {onAdjustRearm?()}
                    if onAdjustStep?(control.wandDirection(positive:step.positive)) == true {
                        current.sentSteps += 1;current.netSteps += step.positive ? -1 : 1
                        current.lastStepWasUp = !step.positive
                    }
                }
                if target.isActive, current.adjusting {showAdjustment(current)}
            }
            hold=current
        case .park, .release:
            guard let current=hold,current.id == command.id,command.sequence > current.sequence else {return}
            hold=nil;lastFinished=current.id
            endHold(current)
        case .open, .appSpecific, .activate, .choose, .dismiss, .exitReview, .toggleReview:break
        }
        if !target.isActive {ownsHUD=false;clearGesture();if pinnedReviewCell == nil && concealedUntil == nil && !screenshotInteractionActive {scheduler.stop()}}
    }

    // MARK: Held gestures

    /// The HUD button went down on an adjustable card: listen. Nothing is pressed
    /// until the first actual step.
    private func beginAdjust(_ command:WandPersistentCommand,cell:PhysicalCell,control:WheelChordControl,fromDotted:Bool) {
        var current=Hold(id:command.id,sequence:command.sequence,received:clock.now,
                         navigation:nil,cell:cell,pageGeneration:target.pageGeneration)
        current.adjusting=true;current.control=control;current.fromDotted=fromDotted
        armed=fromDotted ? ArmedCard(cell:cell,control:control,pageGeneration:target.pageGeneration) : nil
        hold=current
        showAdjustment(current)
    }

    private func adjustable(_ current:Hold,_ control:WheelChordControl)->Bool {
        guard target.isActive, target.pageGeneration == current.pageGeneration else {return false}
        return current.pressed ? target.activeWheelControl == control : target.wandAdjustableControl(for:current.cell) == control
    }

    /// The card's own press, sent with its first step.
    private func pressCard(_ current:inout Hold,_ control:WheelChordControl)->Bool {
        target.handle(.init(action:.select,source:.wand,physicalCell:current.cell,phase:.press),inputTime:clock.now)
        guard target.isActive, target.pageGeneration == current.pageGeneration, target.activeWheelControl == control else {
            // It was not that wheel after all: undo the press and stop listening.
            if target.isActive, target.pageGeneration == current.pageGeneration {
                target.handle(.init(action:.select,source:.wand,physicalCell:current.cell,phase:.release),inputTime:clock.now)
            }
            current.adjusting=false
            return false
        }
        current.pressed=true
        return true
    }

    private func pressSwitchApp(_ current:inout Hold) {
        target.handle(.init(action:.select,source:.wand,physicalCell:.switchApp,phase:.press),inputTime:clock.now)
        current.pressed=true
    }

    private func releasePress(_ current:Hold) {
        guard current.pressed, target.isActive, target.pageGeneration == current.pageGeneration else {return}
        target.handle(.init(action:.select,source:.wand,physicalCell:current.cell,phase:.release),inputTime:clock.now)
    }

    /// Any press a held gesture still owns is let go before teardown.
    private func releaseHeldPress() {
        if let current=hold, current.pressed {releasePress(current)}
    }

    /// A gesture's stream ended (its park, or proof that it was lost).
    private func endHold(_ current:Hold) {
        if current.passiveNavigation {
            keepOutline(after:selected,generation:current.pageGeneration)
            return
        }
        if current.legacy, current.adjusting || current.control != nil {
            // A mouse-button-held operation ends with its own release; the HUD stays.
            releasePress(current)
            keepOutline(after:current.cell,generation:current.pageGeneration)
            return
        }
        if current.adjusting, current.control == nil {
            // Switch App: a chooser that pressed Command switches and closes.
            if current.pressed {
                releasePress(current)
                consumeNextTerminal=true
                // Unchanged by the 2026-10-30 stay-open rule: the held chooser's
                // release switches and closes.
                if target.isActive, target.pageGeneration == current.pageGeneration {conceal()}
                consumeNextTerminal=true
            } else {
                pending=PendingTerminal(card:ArmedCard(cell:.switchApp,control:nil,pageGeneration:current.pageGeneration),fromDotted:false)
                keepOutline(after:.switchApp,generation:current.pageGeneration)
            }
            return
        }
        if current.adjusting, let control=current.control {
            releasePress(current)
            let card=ArmedCard(cell:current.cell,control:control,pageGeneration:current.pageGeneration)
            if current.sentSteps > 0 {
                // Release stops; the gesture's own click or held release is done.
                consumeNextTerminal=true
                if current.fromDotted, target.pageGeneration == card.pageGeneration {armed=card;showDotted(card)}
                else {armed=nil;keepOutline(after:current.cell,generation:current.pageGeneration)}
            } else {
                pending=PendingTerminal(card:card,fromDotted:current.fromDotted)
                if current.fromDotted {armed=card;showDotted(card)}
                else {keepOutline(after:current.cell,generation:current.pageGeneration)}
            }
            return
        }
        // Only the legacy `press` path holds an ordinary card's press here; a
        // wheel hold that turned out not to be a wheel already let go.
        if current.navigation == nil, current.control == nil, current.cell.wandReviewMode == nil,
           target.pageGeneration == current.pageGeneration, target.isActive {
            target.handle(.init(action:.select,source:.wand,physicalCell:current.cell,phase:.release),inputTime:clock.now)
        }
        if let focused=current.navigation?.focusedCell {selected=focused}
        keepOutline(after:current.navigation?.focusedCell ?? current.cell,generation:current.pageGeneration)
    }

    /// A held gesture that never stepped: a tap or a still held release.
    private func finishPending(_ ended:PendingTerminal,tap:Bool) {
        guard target.isActive, target.pageGeneration == ended.card.pageGeneration else {return}
        guard let control=ended.card.control else {
            // Switch App: a tap switches once; a still held release arms it.
            if tap {activate(.switchApp)} else {choose(.switchApp)}
            return
        }
        guard target.wandAdjustableControl(for:ended.card.cell) == control else {return}
        if ended.fromDotted {
            // A tap on a dotted card leaves dotted mode; a held release keeps it.
            if tap {armed=nil;keepOutline(after:ended.card.cell,generation:ended.card.pageGeneration)}
            else {armed=ended.card;showDotted(ended.card)}
            return
        }
        if tap {activate(ended.card.cell)} else {choose(ended.card.cell)}
    }

    // MARK: Review lane

    /// Flips the pinned review card through the same selection path the home
    /// cards use. Requires a live selection with VS Code frontmost. It sends
    /// no wheel, commit or staging command; the receiver's context change
    /// owns ending any pending review session.
    private func toggleReview(id:String) {
        guard !recentReviewToggles.contains(id), target.wandReviewAvailable,
              let pinned=pinnedReviewCell, pinned.wandReviewMode != nil else { return }
        recentReviewToggles.append(id)
        if recentReviewToggles.count > 64 { recentReviewToggles.removeFirst() }
        pinnedReviewCell = pinned == .wandReviewChanges ? .wandReviewFiles : .wandReviewChanges
        target.setWandReviewSelection(pinnedReviewCell)
        startWatchdog()
    }

    // MARK: Using the outlined card

    /// A click: the card's ordinary press and release. An adjustable card
    /// without its own click action is selected (dots) instead; Switch App
    /// switches once.
    private func activate(_ cell:PhysicalCell) {
        armed=nil;pending=nil
        let generation=target.pageGeneration
        if !(target.isWandHome && cell == .switchApp), let control=target.wandAdjustableControl(for:cell), !control.hasWandClickAction {
            select(ArmedCard(cell:cell,control:control,pageGeneration:generation))
            return
        }
        target.handle(.init(action:.select,source:.wand,physicalCell:cell,phase:.press),inputTime:clock.now)
        if target.isActive, target.pageGeneration == generation {
            target.handle(.init(action:.select,source:.wand,physicalCell:cell,phase:.release),inputTime:clock.now)
        }
        finishAction(cell,generation:generation)
    }

    /// A held release: the same one-press action, except an adjustable card
    /// is selected (dots) and home Switch App is armed.
    private func choose(_ cell:PhysicalCell) {
        let generation=target.pageGeneration
        armed=nil;pending=nil
        if target.isWandHome, cell == .switchApp {
            armed=ArmedCard(cell:cell,control:nil,pageGeneration:generation)
            hold=nil
            // Marching dashes: armed for the next real hold. Nothing is held.
            target.setPointerFocus(.init(cell:cell,isArmed:true))
            return
        }
        if let control=target.wandAdjustableControl(for:cell) {
            select(ArmedCard(cell:cell,control:control,pageGeneration:generation))
            return
        }
        target.handle(.init(action:.select,source:.wand,physicalCell:cell,phase:.press),inputTime:clock.now)
        guard target.isActive else {return}
        if target.pageGeneration == generation {
            target.handle(.init(action:.select,source:.wand,physicalCell:cell,phase:.release),inputTime:clock.now)
        }
        finishAction(cell,generation:generation)
    }

    /// Select an adjustable card: dots, nothing pressed, waiting for a hold.
    private func select(_ card:ArmedCard) {
        armed=card;hold=nil
        showDotted(card)
    }

    /// Ethan (2026-10-30): "Single clicking any HUD item, I don't want it to
    /// ever dismiss the HUD ... so then I can just select as many times as I
    /// want." A completed action, whether a tap or a hold-steer-release,
    /// keeps the HUD open on the same card; a page change stays open on its
    /// new page. Only a double click (or Close, lock, teardown) closes it.
    /// A quick tap from closed on home Switch App stays the fast app switch
    /// and parks the HUD. (Home Screenshot used to park it too; it left the
    /// wand home on 2026-10-30, and the mouse button triple-click owns screenshots.)
    private func finishAction(_ cell:PhysicalCell,generation:UInt64) {
        guard target.isActive else {return}
        if target.pageGeneration != generation {
            keepOutline(after:cell,generation:generation)
            return
        }
        if target.isWandHome, cell == .switchApp, gestureOpenedHUD {
            conceal()
            return
        }
        // Arrows, Space and Backspace repeat: the Keys exit hint shows; any
        // other action ends it.
        repeatKeysGeneration = target.page == .keys && !target.isWandHome
            && KeysModeAction.action(for:cell,source:.wand)?.keepsWandHUDOpen == true ? generation : nil
        keepOutline(after:cell,generation:generation)
    }

    private func liveArmedCard() -> ArmedCard? {
        guard let card=armed else {return nil}
        // A page change or frontmost-app retarget clears the selection.
        guard target.pageGeneration == card.pageGeneration,
              card.control == nil ? target.isWandHome && card.cell == .switchApp
                                  : target.wandAdjustableControl(for:card.cell) == card.control else {
            armed=nil
            return nil
        }
        return card
    }

    /// Reuse the existing detent hysteresis, feedback and six-step packet cap.
    /// The first HIGH sample and every metric transition only rebase; a stale
    /// cumulative value must never jump across apps when RAW resumes or stops.
    private func switchAppDelta(_ command:WandPersistentCommand,angleDelta:Double,hold:inout Hold)->Double {
        if let mouseX=command.mouseX {
            defer {hold.switchMetric = .mouse;hold.lastMouseX=mouseX}
            guard hold.switchMetric == .mouse, let previous=hold.lastMouseX else {
                hold.tracker=WandAdjustDetentTracker()
                return 0
            }
            return (mouseX-previous)/Self.switchAppReferenceGain
        }
        defer {hold.switchMetric = .angle;hold.lastMouseX=nil}
        if hold.switchMetric == .mouse {
            hold.tracker=WandAdjustDetentTracker()
            return 0
        }
        return angleDelta
    }

    /// Dots on a selected card, HUD button up: nothing listens.
    private func showDotted(_ card:ArmedCard) {
        guard target.isActive else {return}
        selected=card.cell
        let horizontal=card.control.map{$0.wandAxis == .horizontal} ?? true
        target.setPointerFocus(.init(cell:card.cell,adjustment:.init(isHorizontal:horizontal,isHeld:false)))
    }

    /// A held adjustment: listening glow, arrows and ratchet progress.
    private func showAdjustment(_ current:Hold) {
        let horizontal=current.control.map{$0.wandAxis == .horizontal} ?? true
        var pull=current.control?.isWandSwipeAction == true ? current.swipe.progress : current.tracker.progress
        var lastUp=current.lastStepWasUp
        if current.control == nil {
            // Switch App's tracker runs inverted (right = next app); show the
            // arrows on the side the wand actually moves.
            pull = -pull;lastUp=lastUp.map{!$0}
        }
        target.setPointerFocus(.init(cell:current.cell,adjustment:.init(pull:pull,
            netSteps:current.netSteps,sentSteps:current.sentSteps,lastStepWasUp:lastUp,isHorizontal:horizontal,isHeld:true)))
    }

    private func openHome() {
        selected = .switchApp
        armed=nil;pending=nil;consumeNextTerminal=false
        repeatKeysGeneration=nil
        target.enterWandHome(source:.wand,pointerFocus:.init(cell:selected))
        // Ethan: "when I reopen the HUD, it should still be in that submenu.
        // If I double click the HUD button, then that dismisses it properly".
        if let mark=journeyBookmark {
            journeyBookmark=nil
            if target.isActive, target.restoreWandJourney(mark) {
                selected=target.pointerFocus?.cell ?? WandSelectionController.startCell(for:target.page)
                tapOnlyReopened=true
            }
        }
        ownsHUD=target.isActive
        if ownsHUD {startWatchdog()}
    }

    /// Hide the HUD for a completed action; keep the mode for its follow-up.
    private func conceal() {
        journeyBookmark=target.isWandHome ? nil : target.wandJourneyBookmark()
        clearGesture();ownsHUD=false;repeatKeysGeneration=nil
        target.concealWandHUD()
        concealedUntil=clock.now+Self.followUpLinger
        startWatchdog()
    }

    private func finishConcealment() {
        concealedUntil=nil
        if target.isActive {target.exit(reason:.userRequested)}
    }

    private func keepOutline(after cell:PhysicalCell,generation:UInt64) {
        guard target.isActive else {return}
        selected = target.pageGeneration == generation ? cell
            : target.pointerFocus?.cell ?? (target.isWandHome ? .switchApp : WandSelectionController.startCell(for:target.page))
        target.setPointerFocus(armedPresentation(.init(cell:selected)))
    }

    /// Home Switch App armed by a held release keeps its marching outline
    /// whenever the outline rests on it; elsewhere aiming looks ordinary.
    private func armedPresentation(_ focus:ModeHUDPointerFocus) -> ModeHUDPointerFocus {
        guard focus.adjustment == nil, focus.cell == .switchApp, let card=armed, card.control == nil,
              target.isWandHome, target.pageGeneration == card.pageGeneration else { return focus }
        return .init(cell:focus.cell,isArmed:true,pullX:focus.pullX,pullY:focus.pullY)
    }
    public func refreshContext(screenshotActive:Bool = false) {
        screenshotInteractionActive=screenshotActive
        if screenshotActive { startWatchdog() }
        else if !isOpen && concealedUntil == nil && pinnedReviewCell == nil { scheduler.stop() }
        onContext?(isOpen)
    }
    private func startWatchdog() {
        guard !scheduler.isRunning else {return}
        scheduler.start(interval:0.25) {[weak self] in self?.tick()}
    }
    private func tick() {
        guard allowed() else {reset(reason:.systemSleep);return}
        if let until=concealedUntil {
            guard clock.now >= until else {
                if screenshotInteractionActive { onContext?(isOpen) }
                return
            }
            finishConcealment()
        }
        guard isOpen else {ownsHUD=false;clearGesture();if pinnedReviewCell == nil && !screenshotInteractionActive {scheduler.stop()};onContext?(false);return}
        // A healthy hold has no duration limit. Only missing telemetry expires it.
        if let current=hold, current.held, clock.now-current.received > 1 {
            reset(reason:.deviceLost);return
        }
        onContext?(true)
    }
}

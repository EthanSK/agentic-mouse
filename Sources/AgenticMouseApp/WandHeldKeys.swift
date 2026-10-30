import CoreGraphics
import ScimitarKit

/// Owns only the native held keys requested by a wand card. The enclosing
/// coordinator releases them on exit, disconnect, lock and sleep.
final class WandHeldKeys {
    typealias Event = SyntheticKeyboardChordPoster.Event
    private let post: ([Event]) -> Bool
    private var held: PhysicalCell?
    private var releaseEvents: [Event] = []

    /// The receiver's Switch App loop may run only after our native key owner
    /// accepted Command-down, never merely because the HUD intended to adjust.
    var isSwitchAppHeld: Bool { held == .switchApp }

    init(post: @escaping ([Event]) -> Bool = { SyntheticKeyboardChordPoster.shared.post($0) }) {
        self.post = post
    }

    @discardableResult
    func handle(page: ModePickerPage, home: Bool, cell: PhysicalCell, phase: ModePickerCommand.Phase) -> Bool {
        let down: [Event]
        let up: [Event]
        switch (home, page, cell.rawValue) {
        case (true, _, 11):
            // Tab is a stroke; Command remains down so the switcher stays up.
            down = [.modifier(keyCode:55,flags:.maskCommand,at:0),
                    .key(keyCode:48,flags:.maskCommand,isDown:true,at:0.006),
                    .key(keyCode:48,flags:.maskCommand,isDown:false,at:0.026)]
            up = [.modifier(keyCode:55,flags:[],at:0)]
        case (false, .keys, 2):
            down = [.modifier(keyCode:56,flags:.maskShift,at:0)]
            up = [.modifier(keyCode:56,flags:[],at:0)]
        default:return false
        }
        if phase == .release {
            if held == cell { release() }
        } else if held != cell {
            release()
            if post(down) { held=cell;releaseEvents=up }
        }
        return true
    }

    @discardableResult
    func switchAppStep(_ direction:WheelChordDirection) -> Bool {
        guard held == .switchApp else {return false}
        let reverse = direction == .up
        let flags:CGEventFlags = reverse ? [.maskCommand,.maskShift] : .maskCommand
        var events:[Event] = []
        if reverse {events.append(.modifier(keyCode:56,flags:flags,at:0))}
        events.append(.key(keyCode:48,flags:flags,isDown:true,at:0.006))
        events.append(.key(keyCode:48,flags:flags,isDown:false,at:0.026))
        if reverse {events.append(.modifier(keyCode:56,flags:.maskCommand,at:0.032))}
        return post(events)
    }

    func release() {
        guard held != nil else {return}
        _ = post(releaseEvents)
        held=nil;releaseEvents=[]
    }
}

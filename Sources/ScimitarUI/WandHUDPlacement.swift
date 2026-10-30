import AppKit

/// Ethan's "Magic Wand HUD": bottom-centre, sharing the review reminder's
/// clearance above Agent Flow. This reads window geometry, never recording input.
enum WandHUDPlacement {
    /// Ethan's "glitches up and then comes back down": recorder host windows
    /// can appear/change during startup. Capture clearance once for each visible
    /// HUD session so an unrelated panel never moves the target under the wand.
    /// Reopening (or a display reconfiguration) creates a fresh anchor.
    struct Anchor {
        private let recorderFrames: [NSRect]

        init(readRecorderFrames: () -> [NSRect] = WandHUDPlacement.recorderFrames) {
            recorderFrames = readRecorderFrames()
        }

        func frame(size: NSSize, on screen: NSScreen, margin: CGFloat = 12) -> NSRect {
            frame(size: size, visible: screen.visibleFrame, margin: margin)
        }

        func frame(size: NSSize, visible: NSRect, margin: CGFloat = 12) -> NSRect {
            WandHUDPlacement.frame(size: size, visible: visible,
                                   recorderFrames: recorderFrames, margin: margin)
        }
    }

    static func frame(size:NSSize,on screen:NSScreen,margin:CGFloat=12)->NSRect {
        frame(size:size,visible:screen.visibleFrame,recorderFrames:recorderFrames(),margin:margin)
    }

    static func frame(size:NSSize,visible:NSRect,recorderFrames:[NSRect],margin:CGFloat=12)->NSRect {
        let gap=max(12,margin)
        let x=max(visible.minX,min(visible.maxX-size.width,visible.midX-size.width/2))
        // Only recorder panels below this HUD's column affect this display.
        // The ordinary Agent Flow Dashboard must never lift the wand menu.
        let ceiling=recorderFrames.filter {
            $0.intersects(visible) && $0.maxX>x && $0.minX<x+size.width &&
            $0.minY<visible.minY+360
        }.map(\.maxY).max()
        let y=max(visible.minY,min(visible.maxY-size.height,
            ceiling.map { $0+gap } ?? (visible.minY+gap)))
        return NSRect(origin:NSPoint(x:x,y:y),size:size)
    }

    static func recorderFrames()->[NSRect] {
        let pids=Set(NSWorkspace.shared.runningApplications.filter {
            $0.executableURL?.lastPathComponent == "AgentFlow"
        }.map(\.processIdentifier))
        guard !pids.isEmpty else {return []}
        let top=NSScreen.screens.first?.frame.maxY ?? 0
        let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        return windows.compactMap { info in
            guard let owner=info[kCGWindowOwnerPID as String] as? Int32,pids.contains(owner),
                let layer=info[kCGWindowLayer as String] as? Int,layer>0,
                let alpha=info[kCGWindowAlpha as String] as? Double,alpha>0,
                let data=info[kCGWindowBounds as String] as? NSDictionary,
                let cg=CGRect(dictionaryRepresentation:data),
                cg.width>=160,cg.width<1400,cg.height>=35,cg.height<700 else {return nil}
            // WindowServer is top-left; AppKit is bottom-left on the primary screen.
            return NSRect(x:cg.minX,y:top-cg.maxY,width:cg.width,height:cg.height)
        }
    }
}

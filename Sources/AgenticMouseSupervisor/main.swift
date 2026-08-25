import AppKit
import Foundation
import os

private let log = Logger(
    subsystem: "com.ethan.agentic-mouse.runtime-supervisor",
    category: "startup"
)

guard let executableURL = Bundle.main.executableURL,
      let applicationURL = OuterApplicationLocator.locate(
          from: executableURL,
          expectedBundleIdentifier: AgenticMouseRuntimeSupervisor.applicationBundleIdentifier
      )
else {
    log.fault("could not locate the containing AgenticMouse.app")
    exit(EX_CONFIG)
}

let supervisor = AgenticMouseRuntimeSupervisor(applicationURL: applicationURL)
NSApplication.shared.setActivationPolicy(.accessory)
supervisor.start()
NSApplication.shared.run()

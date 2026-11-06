import AppKit
import Foundation
import ScimitarKit
import SwiftUI
@testable import ScimitarUI
import XCTest

/// Exercise the actual SwiftUI animation modifier while movement continues.
/// Static morph frames cannot catch a later input replacing its transaction.
@MainActor
final class WandNavigationMotionTests: VisibleHUDTestCase {
    func testLivePullUpdatesDoNotShortenTheSelectionSpring() async throws {
        // This is a real WindowServer check, not the headless geometry suite.
        // Never put a test window on an unrelated external work display.
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == "Built-in Retina Display" }) else {
            throw XCTSkip("Live animation check requires the built-in test display")
        }
        let baseline = MotionInput(), moving = MotionInput(), trace = MotionTrace()
        let panel = HUDPanel(contentRect: NSRect(x: screen.visibleFrame.midX - 120,
                                                 y: screen.visibleFrame.minY + 30, width: 240, height: 60))
        panel.contentView = NSHostingView(rootView: VStack {
            MotionProbe(input: baseline, name: "baseline", trace: trace)
            MotionProbe(input: moving, name: "moving", trace: trace)
        }.frame(width: 240, height: 60))
        panel.orderFrontRegardless()
        defer { panel.close() }
        try await Task.sleep(nanoseconds: 150_000_000)
        trace.start()
        baseline.cell = .keysModeEntry
        baseline.pull = 0
        moving.cell = .keysModeEntry
        moving.pull = 0
        for index in 1...12 {
            try await Task.sleep(nanoseconds: 16_000_000)
            moving.pull = index.isMultiple(of: 2) ? 0 : 0.08
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        let rows = trace.read()
        let reference = rows.filter { $0.name == "baseline" }
        let streamed = rows.filter { $0.name == "moving" }
        XCTAssertGreaterThan(reference.count, 5)
        XCTAssertGreaterThan(streamed.count, 5)
        let referenceArrival = try XCTUnwrap(reference.first { $0.progress >= 0.9 })
        let streamedArrival = try XCTUnwrap(streamed.first { $0.progress >= 0.9 })
        XCTAssertGreaterThan(streamedArrival.time, referenceArrival.time * 0.7,
                             "live movement must not replace the card spring with a 30 ms arrival")
        XCTAssertLessThan(abs(streamedArrival.time - referenceArrival.time), 0.06)
        if let folder = ProcessInfo.processInfo.environment["WAND_RADIAL_VISUAL_OUTPUT"] {
            try JSONEncoder().encode(rows).write(to: URL(fileURLWithPath: folder).appendingPathComponent("live-navigation-motion.json"))
        }
    }
}

@MainActor
private final class MotionInput: ObservableObject {
    @Published var cell = PhysicalCell.switchApp
    @Published var pull = 0.9
}

private final class MotionTrace: @unchecked Sendable {
    struct Sample: Codable { let name: String; let time: Double; let progress: Double }
    private let lock = NSLock()
    private var epoch: TimeInterval?
    private var samples: [Sample] = []
    func start() { lock.lock(); defer { lock.unlock() }; samples = []; epoch = ProcessInfo.processInfo.systemUptime }
    func record(name: String, progress: Double) {
        lock.lock(); defer { lock.unlock() }
        guard let epoch else { return }
        samples.append(.init(name: name, time: ProcessInfo.processInfo.systemUptime - epoch, progress: progress))
    }
    func read() -> [Sample] { lock.lock(); defer { lock.unlock() }; return samples }
}

private struct MotionProbe: View {
    @ObservedObject var input: MotionInput
    let name: String
    let trace: MotionTrace
    var body: some View {
        MotionShape(progress: input.cell == .switchApp ? 0 : 1, pull: input.pull, name: name, trace: trace)
            .fill(Color.white)
            .wandNavigationMotion(focus: .init(cell: input.cell, pullX: input.pull), reduceMotion: false)
    }
}

private struct MotionShape: Shape {
    var progress: Double
    var pull: Double
    let name: String
    let trace: MotionTrace
    var animatableData: AnimatablePair<Double, Double> {
        get { .init(progress, pull) }
        set { progress = newValue.first; pull = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        trace.record(name: name, progress: progress)
        return Path(ellipseIn: CGRect(x: progress * 210, y: 8 + pull * 3, width: 12, height: 12))
    }
}

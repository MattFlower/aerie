import AerieNative
import AppKit

/// A bounded, coalesced request after presentation teardown, never part of the sampling loop.
final class IdleMemoryReclaimer {
  private let clock: () -> Double
  private let hasPresentation: () -> Bool
  private let schedule: (Double, @escaping () -> Void) -> Void
  private let release: (@escaping (UInt64, Double) -> Void) -> Void
  private var generation = 0
  private var lastRelease: Double?
  var onComplete: ((UInt64, Double) -> Void)?
  init(
    clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
    hasPresentation: @escaping () -> Bool = {
      NSApp.windows.contains { $0.level != .statusBar && ($0.isVisible || $0.isMiniaturized) }
    },
    schedule: @escaping (Double, @escaping () -> Void) -> Void = { delay, work in
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    },
    release: @escaping (@escaping (UInt64, Double) -> Void) -> Void = { complete in
      DispatchQueue.global(qos: .utility).async {
        let start = ProcessInfo.processInfo.systemUptime
        let bytes = aerie_release_unused_memory(16 * 1_048_576)
        let duration = ProcessInfo.processInfo.systemUptime - start
        DispatchQueue.main.async { complete(bytes, duration) }
      }
    }
  ) {
    self.clock = clock; self.hasPresentation = hasPresentation; self.schedule = schedule
    self.release = release
  }
  func presentationOpened() { generation += 1 }
  func presentationClosed() {
    generation += 1
    let expected = generation
    // Let AppKit finish close notifications/autorelease pools, with at most one request per 20s.
    let delay = max(1, lastRelease.map { 20 - (clock() - $0) } ?? 1)
    schedule(delay) { [weak self] in
      guard let self, self.generation == expected, !self.hasPresentation() else { return }
      self.lastRelease = self.clock()
      self.release { [weak self] bytes, duration in self?.onComplete?(bytes, duration) }
    }
  }
}

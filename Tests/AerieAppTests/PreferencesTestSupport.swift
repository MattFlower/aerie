import AppKit
import XCTest
@testable import AerieApp

@MainActor func preferenceViews(_ view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap { preferenceViews($0) }
}
@MainActor func preferenceTabs(_ controller: PreferencesController) throws -> NSTabView {
  let root = try XCTUnwrap(controller.window?.contentView)
  return try XCTUnwrap(preferenceViews(root).compactMap { $0 as? NSTabView }.first)
}
@MainActor func preferenceControls(_ controller: PreferencesController) throws -> [NSView] {
  let root = try XCTUnwrap(controller.window?.contentView)
  let tabs = try preferenceTabs(controller)
  return preferenceViews(root)
    + tabs.tabViewItems.compactMap(\.view).flatMap { preferenceViews($0) }
}

import AerieCore
import CoreLocation
import Foundation

protocol WiFiPermissionRequest: AnyObject {
  func request(_ completion: @escaping (WiFiAuthorization) -> Void)
  func close()
}
private final class NativeWiFiPermission: NSObject, WiFiPermissionRequest, CLLocationManagerDelegate
{
  private var manager: CLLocationManager?
  private var completion: ((WiFiAuthorization) -> Void)?
  func request(_ completion: @escaping (WiFiAuthorization) -> Void) {
    precondition(Thread.isMainThread)
    self.completion = completion
    let manager = CLLocationManager(); self.manager = manager; manager.delegate = self
    manager.requestWhenInUseAuthorization()
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard self.manager === manager else { return }
    let status = WiFiAccess.nativeAuthorization(manager.authorizationStatus)
    if status != .notDetermined { completion?(status) }
  }
  func close() { manager?.delegate = nil; manager = nil; completion = nil }
}

enum WiFiPermissionError: Error { case requiresForeground, alreadyRequesting }

/// Created only for a direct Settings action. A completed/cancelled attempt owns no manager.
final class WiFiAccess {
  private let status: () -> WiFiAuthorization
  private let factory: () -> WiFiPermissionRequest
  private var requestStore: WiFiPermissionRequest?
  private var generation = 0
  var requesting: Bool { requestStore != nil }
  init(
    status: @escaping () -> WiFiAuthorization = { WiFiAccess.nativeAuthorization() },
    factory: @escaping () -> WiFiPermissionRequest = { NativeWiFiPermission() }
  ) { self.status = status; self.factory = factory }
  static func nativeAuthorization(_ status: CLAuthorizationStatus? = nil) -> WiFiAuthorization {
    guard CLLocationManager.locationServicesEnabled() else { return .servicesDisabled }
    // This static read creates no manager and requests no coordinates or permission.
    switch status ?? CLLocationManager.authorizationStatus() {
    case .notDetermined: return .notDetermined
    case .denied: return .denied
    case .restricted: return .restricted
    case .authorizedAlways, .authorizedWhenInUse: return .authorized
    @unknown default: return .unknown
    }
  }
  func request(
    foreground: Bool, completion: @escaping (Result<WiFiAuthorization, WiFiPermissionError>) -> Void
  ) {
    precondition(Thread.isMainThread)
    guard !requesting else { completion(.failure(.alreadyRequesting)); return }
    guard foreground else { completion(.failure(.requiresForeground)); return }
    let current = status()
    guard current == .notDetermined else { completion(.success(current)); return }
    generation += 1; let token = generation
    let store = factory(); requestStore = store
    store.request { [weak self] delivered in
      precondition(Thread.isMainThread)
      guard let self, self.generation == token, self.requestStore != nil,
        delivered != .notDetermined
      else { return }
      let current = self.status()
      self.requestStore?.close(); self.requestStore = nil
      completion(.success(current))
    }
  }
  func cancel() {
    precondition(Thread.isMainThread)
    generation += 1; requestStore?.close(); requestStore = nil
  }
  deinit { requestStore?.close() }
}

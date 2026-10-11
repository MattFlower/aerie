import CoreLocation
import Foundation

struct LocationChoice: Equatable {
  let name: String
  let latitude, longitude: Double
  let zone: String
  var valid: Bool {
    !name.isEmpty && name.utf8.count <= 256
      && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      && latitude.isFinite && longitude.isFinite
      && (-90...90).contains(latitude) && (-180...180).contains(longitude)
      && TimeZone(identifier: zone) != nil
  }
}
enum LocationLookupError: Error {
  case foregroundRequired, servicesDisabled, permissionDenied, unavailable, timeout, invalidQuery
  var message: String {
    switch self {
    case .foregroundRequired: return "Keep Settings active while choosing the Mac's location."
    case .servicesDisabled:
      return "Location Services is off. You can search for a city or ZIP instead."
    case .permissionDenied:
      return
        "Location access is unavailable. Choose a city or ZIP, or review Aerie's access in macOS Settings."
    case .unavailable: return "No location was found. Check the city or ZIP and try again."
    case .timeout: return "The location request timed out. Try again or search for a city or ZIP."
    case .invalidQuery: return "Enter a city or ZIP/postal code, up to 120 characters."
    }
  }
}
protocol LocationLookupProvider: AnyObject {
  func macLocation(
    foreground: Bool, completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void)
  func search(
    _ query: String, completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void)
  func cancel()
}

/// Created only by an explicit Settings action. No background location subscription.
final class NativeLocationLookup: NSObject, LocationLookupProvider, CLLocationManagerDelegate {
  private var manager: CLLocationManager?
  private var geocoder: CLGeocoder?
  private var completion: ((Result<[LocationChoice], LocationLookupError>) -> Void)?
  private var deadline: DispatchWorkItem?
  private var generation = 0
  private var locationRequested = false
  func macLocation(
    foreground: Bool, completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void
  ) {
    cancel()
    guard foreground else { completion(.failure(.foregroundRequired)); return }
    guard CLLocationManager.locationServicesEnabled() else {
      completion(.failure(.servicesDisabled)); return
    }
    self.completion = completion
    let manager = CLLocationManager(); self.manager = manager; manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    armDeadline()
    switch manager.authorizationStatus {
    case .notDetermined: manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse: requestPoint(manager)
    default: finish(.failure(.permissionDenied))
    }
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard manager === self.manager else { return }
    switch manager.authorizationStatus {
    case .notDetermined: break
    case .authorizedAlways, .authorizedWhenInUse: requestPoint(manager)
    default: finish(.failure(.permissionDenied))
    }
  }
  private func requestPoint(_ manager: CLLocationManager) {
    guard !locationRequested else { return }; locationRequested = true; manager.requestLocation()
  }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard manager === self.manager else { return }
    guard let location = locations.last,
      location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) <= 600
    else { finish(.failure(.unavailable)); return }
    let point = LocationChoice(
      name: "My Mac's location", latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude, zone: TimeZone.autoupdatingCurrent.identifier)
    finish(point.valid ? .success([point]) : .failure(.unavailable))
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard manager === self.manager else { return }; finish(.failure(.unavailable))
  }
  func search(
    _ query: String, completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void
  ) {
    cancel()
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 120,
      !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      completion(.failure(.invalidQuery)); return
    }
    self.completion = completion; let token = generation
    let geocoder = CLGeocoder(); self.geocoder = geocoder; armDeadline()
    geocoder.geocodeAddressString(text) { [weak self] placemarks, error in
      DispatchQueue.main.async {
        guard let self, token == self.generation else { return }
        let choices = (placemarks ?? []).prefix(10).compactMap { placemark -> LocationChoice? in
          guard let location = placemark.location else { return nil }
          let name = [
            placemark.locality ?? placemark.name, placemark.administrativeArea, placemark.country,
          ]
          .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
          let choice = LocationChoice(
            name: String((name.isEmpty ? text : name).prefix(64)),
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            zone: placemark.timeZone?.identifier ?? TimeZone.autoupdatingCurrent.identifier)
          return choice.valid ? choice : nil
        }
        self.finish(error == nil && !choices.isEmpty ? .success(choices) : .failure(.unavailable))
      }
    }
  }
  private func armDeadline() {
    let token = generation
    let work = DispatchWorkItem { [weak self] in
      guard let self, token == self.generation else { return }; self.finish(.failure(.timeout))
    }
    deadline = work; DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
  }
  private func finish(_ result: Result<[LocationChoice], LocationLookupError>) {
    let callback = completion; cancel(); callback?(result)
  }
  func cancel() {
    generation += 1; locationRequested = false; completion = nil; deadline?.cancel(); deadline = nil
    manager?.stopUpdatingLocation(); manager?.delegate = nil; manager = nil
    geocoder?.cancelGeocode(); geocoder = nil
  }
  deinit { deadline?.cancel(); manager?.stopUpdatingLocation(); geocoder?.cancelGeocode() }
}

/// Guards late provider callbacks independently of the framework's cancellation behavior.
final class LocationLookupSession {
  private let factory: () -> LocationLookupProvider
  private var provider: LocationLookupProvider?
  private var generation = 0
  init(factory: @escaping () -> LocationLookupProvider = { NativeLocationLookup() }) {
    self.factory = factory
  }
  func macLocation(
    foreground: Bool, completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void
  ) {
    start(completion) { $0.macLocation(foreground: foreground, completion: $1) }
  }
  func search(
    _ query: String, completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void
  ) {
    start(completion) { $0.search(query, completion: $1) }
  }
  private func start(
    _ completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void,
    operation: (
      LocationLookupProvider, @escaping (Result<[LocationChoice], LocationLookupError>) -> Void
    ) -> Void
  ) {
    cancel(); let token = generation; let request = factory(); provider = request
    operation(request) { [weak self] result in
      guard let self, token == self.generation else { return }
      self.provider = nil; self.generation += 1; completion(result)
    }
  }
  func cancel() { generation += 1; provider?.cancel(); provider = nil }
  deinit { provider?.cancel() }
}

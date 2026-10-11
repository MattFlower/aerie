import AerieCore
import CoreWLAN
import Foundation

protocol WiFiSource: AnyObject {
  func read(authorization: WiFiAuthorization) -> WiFiReading?
  func close()
}

private final class NativeWiFiSource: WiFiSource {
  private var client: CWWiFiClient? = CWWiFiClient()
  func read(authorization: WiFiAuthorization) -> WiFiReading? {
    autoreleasepool {
      guard let interface = client?.interface() else { return nil }
      let powered = interface.powerOn()
      guard powered else {
        return WiFiReading(
          interface: interface.interfaceName, powered: false, authorization: authorization)
      }
      let mode: WiFiMode
      switch interface.interfaceMode() {
      case .station: mode = .station
      case .IBSS: mode = .peer
      case .hostAP: mode = .accessPoint
      case .none: mode = .none
      default: mode = .unknown
      }
      let channel = interface.wlanChannel()
      let band: String?
      switch channel?.channelBand {
      case .band2GHz: band = "2.4 GHz"
      case .band5GHz: band = "5 GHz"
      case .band6GHz: band = "6 GHz"
      default: band = nil
      }
      let width: String?
      switch channel?.channelWidth {
      case .width20MHz: width = "20 MHz"
      case .width40MHz: width = "40 MHz"
      case .width80MHz: width = "80 MHz"
      case .width160MHz: width = "160 MHz"
      default: width = nil
      }
      // Do not even call the identity getters without existing authorization.
      let allowed = authorization == .authorized
      return WiFiReading(
        interface: interface.interfaceName, powered: true, mode: mode,
        signal: interface.rssiValue(), noise: interface.noiseMeasurement(),
        rate: interface.transmitRate(), channel: channel.map { $0.channelNumber },
        band: band, width: width, ssid: allowed ? interface.ssid() : nil,
        bssid: allowed ? interface.bssid() : nil,
        country: allowed ? interface.countryCode() : nil, authorization: authorization)
    }
  }
  func close() { client = nil }
}

/// Owned exclusively by the sampling worker. No timer, scan, radio write or background identity.
final class WiFiReader {
  private let factory: () -> WiFiSource
  private var source: WiFiSource?
  private var visible = false
  private var lastTime: Double?
  private var lastPath: UInt64?
  private var lastAccess: WiFiAuthorization?
  private(set) var reading: WiFiReading?
  init(factory: @escaping () -> WiFiSource = { NativeWiFiSource() }) { self.factory = factory }
  func configure(visible: Bool) {
    self.visible = visible
    if !visible {
      reading = nil; source?.close(); source = nil
      lastTime = nil; lastPath = nil; lastAccess = nil
    }
  }
  func current(time: Double, path: UInt64, authorization: WiFiAuthorization) -> WiFiReading? {
    guard visible else { return nil }
    guard time.isFinite else { reading = nil; lastTime = nil; return nil }
    if lastTime == nil || time < lastTime! || time - lastTime! >= 30 || lastPath != path
      || lastAccess != authorization
    {
      if source == nil { source = factory() }
      reading = source?.read(authorization: authorization)
      lastTime = time; lastPath = path; lastAccess = authorization
    }
    reading?.recheckAuthorization(authorization)
    return reading
  }
  deinit { source?.close() }
}

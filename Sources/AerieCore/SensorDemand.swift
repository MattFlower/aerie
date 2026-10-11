import Foundation

public enum SensorSamplingMode: String, Codable { case all, whenNeeded }
public enum SensorDemand {
  /// All temperature keys feed maximum-temperature history and threshold rules every tick.
  /// Other families have no background history/rule inputs today and can be explicitly deferred.
  public static func required(unit: String, mode: SensorSamplingMode, panelVisible: Bool) -> Bool {
    mode == .all || panelVisible || unit == "°C"
  }
}

import Foundation

public enum SensorSamplingMode: String, Codable { case all, whenNeeded }
public enum SensorDemand {
  /// All temperature keys feed maximum-temperature history and threshold rules every tick.
  /// Enabled individual rules also require their specific keys at the chosen cadence.
  public static func required(
    unit: String, mode: SensorSamplingMode, panelVisible: Bool, ruleRequired: Bool = false
  ) -> Bool {
    mode == .all || panelVisible || unit == "°C" || ruleRequired
  }
}

import Foundation

/// Presentation conversions do not change the rule engine's stored native units.
public enum NotificationPresentation {
  public static func title(_ metric: String) -> String {
    switch metric {
    case "cpu": return "CPU usage"
    case "gpu": return "GPU usage"
    case "memory": return "Memory used"
    case "battery": return "Battery charge"
    case "temperature": return "Highest temperature"
    case "diskFree": return "Free space on the first volume"
    case "download": return "Download speed"
    case "upload": return "Upload speed"
    case "thermal": return "Thermal pressure"
    case "diskRead": return "Storage read speed"
    case "diskWrite": return "Storage write speed"
    default: return SensorIdentity.key(metric: metric).map { "Sensor " + $0 } ?? "Hardware value"
    }
  }
  public static func scale(_ metric: String) -> Double {
    ["download", "upload", "diskRead", "diskWrite"].contains(metric) ? 1_000_000 : 1
  }
  public static func unit(_ metric: String, sensorUnit: String? = nil) -> String {
    switch metric {
    case "cpu", "gpu", "memory", "battery": return "%"
    case "temperature": return "°C"
    case "diskFree": return "GiB"
    case "download", "upload", "diskRead", "diskWrite": return "MB/s"
    case "thermal": return "level"
    default: return sensorUnit ?? ""
    }
  }
  public static func summary(_ rule: ThresholdRule, sensorName: String? = nil) -> String {
    let label = sensorName ?? title(rule.metric)
    let scale = scale(rule.metric)
    func value(_ number: Double) -> String {
      if rule.metric == "thermal", number.rounded() == number, (0...3).contains(number) {
        return ["normal", "fair", "serious", "critical"][Int(number)]
      }
      let unit = unit(rule.metric, sensorUnit: rule.sensorUnit)
      return String(format: "%g", number / scale)
        + (unit == "%" ? "%" : unit.isEmpty ? "" : " " + unit)
    }
    let bounds = value(rule.threshold)
    let condition: String
    switch rule.comparison {
    case .above: condition = "above " + bounds
    case .below: condition = "below " + bounds
    case .atLeast: condition = "at least " + bounds
    case .atMost: condition = "at most " + bounds
    case .inside:
      condition = "between " + bounds + " and " + value(rule.upperThreshold ?? rule.threshold)
    case .outside:
      condition = "outside " + bounds + " to " + value(rule.upperThreshold ?? rule.threshold)
    }
    return label + " " + condition
      + (rule.duration > 0 ? " for " + String(format: "%g", rule.duration) + " seconds" : "")
  }
}

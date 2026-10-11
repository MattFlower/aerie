import Foundation

public struct DaylightConfiguration: Codable, Equatable {
  public var enabled = false
  public var name = ""
  public var latitude = 0.0, longitude = 0.0
  public var zone = "Etc/UTC"
  public init() {}
  public var valid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 64
      && name.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
      && latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude)
      && (-180...180).contains(longitude) && zone.utf8.count <= 64
      && TimeZone(identifier: zone) != nil
  }
}
public enum SolarBand: String, CaseIterable {
  case daylight, civil, nautical, astronomical
  var elevation: Double {
    switch self {
    case .daylight: return -0.833;
    case .civil: return -6
    case .nautical: return -12;
    case .astronomical: return -18
    }
  }
}
public struct SolarBoundary {
  public enum State { case transitions, continuousAbove, continuousBelow }
  public var band: SolarBand
  public var rises: [Date], sets: [Date]
  public var secondsAbove: Double
  public var state: State
}
public struct SolarDay {
  public var interval: DateInterval
  public var zone: TimeZone
  public var boundaries: [SolarBoundary]
  public var transits: [Date]
  public static func make(date: Date, configuration: DaylightConfiguration) -> SolarDay? {
    guard configuration.enabled, configuration.valid, date.timeIntervalSince1970.isFinite,
      abs(date.timeIntervalSince1970) < 1e11, let zone = TimeZone(identifier: configuration.zone)
    else { return nil }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    guard let year = calendar.dateComponents([.year], from: date).year,
      (1901...2099).contains(year),
      let interval = calendar.dateInterval(of: .day, for: date),
      (72000...100800).contains(interval.duration)
    else { return nil }
    let latitude = configuration.latitude * .pi / 180
    func elevation(_ seconds: Double) -> Double {
      let instant = interval.start.addingTimeInterval(seconds)
      let angles = SolarAngles.at(instant)
      let utcMinutes = instant.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) / 60
      let solarMinutes = (utcMinutes + angles.equationMinutes + 4 * configuration.longitude)
      let hourAngle = (solarMinutes / 4 - 180) * .pi / 180
      let cosine =
        sin(latitude) * sin(angles.declination) + cos(latitude) * cos(angles.declination)
        * cos(hourAngle)
      return 90 - acos(max(-1, min(1, cosine))) * 180 / .pi
    }
    let samples = SolarCurve.samples(duration: interval.duration, evaluate: elevation)
    let boundaries = SolarBand.allCases.map { band -> SolarBoundary in
      var rises: [Date] = [], sets: [Date] = [], roots: [Double] = []
      for (left, right) in zip(samples, samples.dropFirst()) {
        let a = left.value - band.elevation, b = right.value - band.elevation
        guard (a < 0 && b >= 0) || (a >= 0 && b < 0) else { continue }
        var low = left.time, high = right.time
        for _ in 0..<28 {
          let middle = (low + high) / 2, value = elevation(middle) - band.elevation
          if (value >= 0) == (a >= 0) { low = middle } else { high = middle }
        }
        let root = (low + high) / 2
        guard root < interval.duration, roots.last.map({ root - $0 > 0.01 }) ?? true else {
          continue
        }
        roots.append(root)
        let instant = interval.start.addingTimeInterval(root)
        if b > a { rises.append(instant) } else { sets.append(instant) }
      }
      let edges = [0.0] + roots + [interval.duration]
      var secondsAbove = 0.0
      for (left, right) in zip(edges, edges.dropFirst()) where right > left {
        if elevation((left + right) / 2) >= band.elevation { secondsAbove += right - left }
      }
      let state: SolarBoundary.State =
        roots.isEmpty
        ? (secondsAbove > 0 ? .continuousAbove : .continuousBelow) : .transitions
      return SolarBoundary(
        band: band, rises: rises, sets: sets, secondsAbove: secondsAbove, state: state)
    }
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let midnight = utc.startOfDay(for: interval.start)
    var transits: [Date] = []
    for offset in -1...2 {
      let base = midnight.addingTimeInterval(Double(offset) * 86400)
      var noon = base.addingTimeInterval((720 - 4 * configuration.longitude) * 60)
      for _ in 0..<4 {
        noon = base.addingTimeInterval(
          (720 - 4 * configuration.longitude - SolarAngles.at(noon).equationMinutes) * 60)
      }
      if noon >= interval.start && noon < interval.end { transits.append(noon) }
    }
    return SolarDay(
      interval: interval, zone: zone, boundaries: boundaries, transits: transits.sorted())
  }
}

/// Geometric solar position from published solar equations; horizon/twilight thresholds are separate.
private struct SolarAngles {
  var declination: Double, equationMinutes: Double
  static func at(_ date: Date) -> SolarAngles {
    let century = (date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545) / 36525
    func radians(_ value: Double) -> Double { value * .pi / 180 }
    let longitude = radians(
      (280.46646 + century * (36000.76983 + 0.0003032 * century)).truncatingRemainder(
        dividingBy: 360))
    let anomaly = radians(357.52911 + century * (35999.05029 - 0.0001537 * century))
    let eccentricity = 0.016708634 - century * (0.000042037 + 0.0000001267 * century)
    let center = radians(
      sin(anomaly) * (1.914602 - century * (0.004817 + 0.000014 * century))
        + sin(2 * anomaly) * (0.019993 - 0.000101 * century) + sin(3 * anomaly) * 0.000289)
    let omega = radians(125.04 - 1934.136 * century)
    let apparent = longitude + center - radians(0.00569 + 0.00478 * sin(omega))
    let meanObliquity =
      23 + (26 + (21.448 - century * (46.815 + century * (0.00059 - 0.001813 * century))) / 60) / 60
    let obliquity = radians(meanObliquity + 0.00256 * cos(omega))
    let y = pow(tan(obliquity / 2), 2)
    let equation =
      y * sin(2 * longitude) - 2 * eccentricity * sin(anomaly)
      + 4 * eccentricity * y * sin(anomaly) * cos(2 * longitude)
      - 0.5 * y * y * sin(4 * longitude) - 1.25 * eccentricity * eccentricity * sin(2 * anomaly)
    return SolarAngles(
      declination: asin(sin(obliquity) * sin(apparent)), equationMinutes: 4 * equation * 180 / .pi)
  }
}

/// A bounded smooth-curve grid with refined extrema, so brief polar transitions are not rounded away.
enum SolarCurve {
  struct Point { var time, value: Double }
  static func samples(duration: Double, evaluate: (Double) -> Double) -> [Point] {
    guard duration.isFinite, duration > 0, duration <= 100800 else { return [] }
    let count = Int(ceil(duration / 300))
    var points = (0...count).map { i -> Point in
      let time = min(duration, Double(i) * 300); return Point(time: time, value: evaluate(time))
    }
    var brackets: [(Double, Double, Bool)] = []
    for index in 1..<count {
      let before = points[index - 1], point = points[index], after = points[index + 1]
      if point.value >= before.value && point.value >= after.value,
        point.value > before.value || point.value > after.value
      {
        brackets.append((before.time, after.time, true))
      }
      if point.value <= before.value && point.value <= after.value,
        point.value < before.value || point.value < after.value
      {
        brackets.append((before.time, after.time, false))
      }
    }
    // An extremum can fall between a day boundary and its first/last grid point.
    for (left, right) in [(0.0, min(300, duration)), (max(0, duration - 300), duration)] {
      brackets.append((left, right, true)); brackets.append((left, right, false))
    }
    for (start, end, maximum) in brackets {
      var low = start, high = end
      for _ in 0..<32 {
        let a = low + (high - low) / 3, b = high - (high - low) / 3
        if (evaluate(a) < evaluate(b)) == maximum { low = a } else { high = b }
      }
      let time = (low + high) / 2; points.append(Point(time: time, value: evaluate(time)))
    }
    return points.sorted { $0.time < $1.time }
  }
}

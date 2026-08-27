import Foundation
import HealthKit

struct HealthKitPayload: Codable { let version: Int; let days: [HealthKitDay] }
struct HealthKitDay: Codable {
  let date: String
  var sleepHours: Double?
  var restingHeartRate: Double?
  var hrv: Double?
  var vo2Max: Double?
  var steps: Double?
  var activeCalories: Double?
  var weight: Double?
  var workouts: [HealthKitWorkout] = []
}
struct HealthKitWorkout: Codable { let name: String; let type: String; let duration: Double }
struct HealthKitSyncResult { let payload: HealthKitPayload }

final class HealthKitSyncManager {
  private let store = HKHealthStore()
  private let defaults = UserDefaults.standard
  private let formatter = ISO8601DateFormatter()
  private var types: [HKSampleType] {
    [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
     HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
     HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
     HKObjectType.quantityType(forIdentifier: .vo2Max)!,
     HKObjectType.quantityType(forIdentifier: .stepCount)!,
     HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
     HKObjectType.quantityType(forIdentifier: .bodyMass)!,
     HKObjectType.workoutType()]
  }
  func requestAuthorizationAndSync(_ done: @escaping (Result<HealthKitSyncResult, Error>) -> Void) {
    store.requestAuthorization(toShare: [], read: Set(types)) { [weak self] ok, error in
      if let error { done(.failure(error)); return }
      guard ok else { done(.failure(NSError(domain: "HealthDashboard", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit permission was not granted."]))); return }
      self?.run(done)
    }
  }
  func syncIfAuthorized(_ done: @escaping (Result<HealthKitSyncResult, Error>) -> Void) {
    store.getRequestStatusForAuthorization(toShare: [], read: Set(types)) { [weak self] status, error in
      if let error { done(.failure(error)); return }
      if status == .unnecessary { self?.run(done) }
    }
  }
  private func run(_ done: @escaping (Result<HealthKitSyncResult, Error>) -> Void) {
    let group = DispatchGroup(), lock = NSLock()
    var output: [String: HealthKitDay] = [:], failure: Error?
    for type in types {
      group.enter()
      let key = "healthkit.anchor." + type.identifier
      let anchor = defaults.data(forKey: key).flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
      let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, newAnchor, error in
        defer { group.leave() }
        if let error { lock.lock(); failure = error; lock.unlock(); return }
        lock.lock()
        (samples ?? []).forEach { self?.map($0, into: &output) }
        if let newAnchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true) { self?.defaults.set(data, forKey: key) }
        lock.unlock()
      }
      store.execute(query)
    }
    group.notify(queue: .global()) {
      if let failure { done(.failure(failure)); return }
      done(.success(HealthKitSyncResult(payload: HealthKitPayload(version: 1, days: Array(output.values)))))
    }
  }
  private func map(_ sample: HKSample, into days: inout [String: HealthKitDay]) {
    let key = String(formatter.string(from: sample.startDate).prefix(10))
    var day = days[key] ?? HealthKitDay(date: key)
    if let q = sample as? HKQuantitySample {
      switch q.quantityType.identifier {
      case HKQuantityTypeIdentifier.restingHeartRate.rawValue: day.restingHeartRate = q.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
      case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue: day.hrv = q.quantity.doubleValue(for: .secondUnit(with: .milli))
      case HKQuantityTypeIdentifier.vo2Max.rawValue: day.vo2Max = q.quantity.doubleValue(for: HKUnit.literUnit(with: .milli).unitDivided(by: .kilogramUnit().unitDivided(by: .minute())))
      case HKQuantityTypeIdentifier.stepCount.rawValue: day.steps = (day.steps ?? 0) + q.quantity.doubleValue(for: .count())
      case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue: day.activeCalories = (day.activeCalories ?? 0) + q.quantity.doubleValue(for: .kilocalorie())
      case HKQuantityTypeIdentifier.bodyMass.rawValue: day.weight = q.quantity.doubleValue(for: .pound())
      default: break
      }
    } else if let category = sample as? HKCategorySample {
      if category.categoryType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue { day.sleepHours = (day.sleepHours ?? 0) + category.endDate.timeIntervalSince(category.startDate) / 3600 }
    } else if let workout = sample as? HKWorkout {
      day.workouts.append(HealthKitWorkout(name: "HealthKit workout " + String(workout.workoutActivityType.rawValue), type: "healthkit", duration: workout.duration / 60))
    }
    days[key] = day
  }
}

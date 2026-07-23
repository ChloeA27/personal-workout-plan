import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var lastSyncDate: Date?
    @Published var lastSyncStatus: String = "尚未同步"

    private let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]
        if let activitySummaryType = HKObjectType.activitySummaryType() as HKObjectType? {
            types.insert(activitySummaryType)
        }
        return types
    }()

    func requestAuthorization() async {
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            enableBackgroundDelivery()
        } catch {
            lastSyncStatus = "授权失败: \(error.localizedDescription)"
        }
    }

    private func enableBackgroundDelivery() {
        for type in readTypes {
            guard let sampleType = type as? HKSampleType else { continue }
            store.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { _, error in
                if let error {
                    print("Background delivery setup failed for \(sampleType): \(error)")
                }
            }
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, _ in
                Task { @MainActor in
                    await self?.syncToday()
                }
                completionHandler()
            }
            store.execute(query)
        }
    }

    /// 手动或自动触发：采集今天的数据并上传
    func syncToday() async {
        let summary = await collectDailySummary(for: Date())
        do {
            try await GitHubUploader.shared.upload(summary: summary)
            lastSyncDate = Date()
            lastSyncStatus = "同步成功 \(summary.date)"
        } catch {
            lastSyncStatus = "上传失败: \(error.localizedDescription)"
        }
    }

    func collectDailySummary(for date: Date) async -> DailyHealthSummary {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let steps = sumQuantity(.stepCount, unit: .count(), predicate: predicate)
        async let restingEnergy = sumQuantity(.basalEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        async let activeEnergy = sumQuantity(.activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        async let restingHR = averageQuantity(.restingHeartRate, unit: HKUnit(from: "count/min"), predicate: predicate)
        async let hrv = averageQuantity(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), predicate: predicate)
        async let sleep = collectSleep(predicate: predicate)
        async let workouts = collectWorkouts(predicate: predicate)
        async let activity = collectActivitySummary(for: date)

        return DailyHealthSummary(
            date: DateFormatter.isoDate.string(from: start),
            steps: await steps,
            restingHeartRate: await restingHR,
            hrvSDNN: await hrv,
            restingEnergy: await restingEnergy,
            activeEnergy: await activeEnergy,
            activitySummary: await activity,
            sleep: await sleep,
            workouts: await workouts
        )
    }

    private func sumQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func averageQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func collectSleep(predicate: NSPredicate) async -> SleepSummary? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                var stageMinutes: [String: Double] = [:]
                var asleepMinutes: Double = 0
                var inBedMinutes: Double = 0
                for sample in samples {
                    let minutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        inBedMinutes += minutes
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        stageMinutes["core", default: 0] += minutes
                        asleepMinutes += minutes
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        stageMinutes["deep", default: 0] += minutes
                        asleepMinutes += minutes
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        stageMinutes["rem", default: 0] += minutes
                        asleepMinutes += minutes
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        stageMinutes["unspecified", default: 0] += minutes
                        asleepMinutes += minutes
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        stageMinutes["awake", default: 0] += minutes
                    default:
                        break
                    }
                }
                continuation.resume(returning: SleepSummary(
                    totalAsleepMinutes: asleepMinutes,
                    inBedMinutes: inBedMinutes,
                    stages: stageMinutes
                ))
            }
            store.execute(query)
        }
    }

    private func collectWorkouts(predicate: NSPredicate) async -> [WorkoutSummary] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }
                let results = workouts.map { workout -> WorkoutSummary in
                    WorkoutSummary(
                        type: workout.workoutActivityType.name,
                        start: ISO8601DateFormatter().string(from: workout.startDate),
                        end: ISO8601DateFormatter().string(from: workout.endDate),
                        durationMinutes: workout.duration / 60.0,
                        totalEnergyBurned: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                            .sumQuantity()?.doubleValue(for: .kilocalorie()),
                        avgHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?
                            .averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
                    )
                }
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }

    private func collectActivitySummary(for date: Date) async -> ActivitySummary? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.calendar = calendar
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: components, end: components)
        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let summary = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ActivitySummary(
                    moveMinutes: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
                    standHours: summary.appleStandHours.doubleValue(for: .count())
                ))
            }
            store.execute(query)
        }
    }
}

extension DateFormatter {
    static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .traditionalStrengthTraining: return "traditionalStrengthTraining"
        case .functionalStrengthTraining: return "functionalStrengthTraining"
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .yoga: return "yoga"
        case .highIntensityIntervalTraining: return "hiit"
        case .coreTraining: return "coreTraining"
        default: return "other"
        }
    }
}

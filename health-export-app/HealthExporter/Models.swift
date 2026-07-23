import Foundation

struct DailyHealthSummary: Codable {
    let date: String
    let steps: Double?
    let restingHeartRate: Double?
    let hrvSDNN: Double?
    let restingEnergy: Double?
    let activeEnergy: Double?
    let activitySummary: ActivitySummary?
    let sleep: SleepSummary?
    let workouts: [WorkoutSummary]
}

struct ActivitySummary: Codable {
    let moveMinutes: Double
    let exerciseMinutes: Double
    let standHours: Double
}

struct SleepSummary: Codable {
    let totalAsleepMinutes: Double
    let inBedMinutes: Double
    let stages: [String: Double]
}

struct WorkoutSummary: Codable {
    let type: String
    let start: String
    let end: String
    let durationMinutes: Double
    let totalEnergyBurned: Double?
    let avgHeartRate: Double?
}

import Foundation

public enum Sport: String, Codable, CaseIterable, Identifiable, SelectableItem, Sendable {
    public var id: String { self.rawValue }
    public var name: String { self.rawValue }

    public var iconName: String? {
        self.rawValue.lowercased()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
    // --- END OF CHANGE ---
    
    public var iconText: String? { nil }

       case aerobics = "Aerobics"
       case agilityTraining = "Agility Training"
       case americanFootball = "American Football"
       case animalFlow = "Animal Flow"
       case armWrestling = "Arm Wrestling"
       case athletics = "Athletics"
       case balanceTraining = "Balance Training"
       case barre = "Barre"
       case baseball = "Baseball"
       case basketball = "Basketball"
       case beginners = "Beginners"
       case bodybuilding = "Bodybuilding"
       case boxing = "Boxing"
       case breakdancing = "Breakdancing"
       case calisthenics = "Calisthenics"
       case capoeira = "Capoeira"
       case cardio = "Cardio"
       case cheerleading = "Cheerleading"
       case circuitTraining = "Circuit Training"
       case crossfit = "Crossfit"
       case cycling = "Cycling"
       case dance = "Dance"
       case enduranceSports = "Endurance Sports"
       case fitness = "Fitness"
       case football = "Football"
       case golf = "Golf"
       case gymnastics = "Gymnastics"
       case hiit = "HIIT"
       case hiking = "Hiking"
       case hockey = "Hockey"
       case homeWorkouts = "Home Workouts"
       case iceSkating = "Ice Skating"
       case judo = "Judo"
       case jumpRope = "Jump Rope"
       case kayaking = "Kayaking"
       case kettlebellTraining = "Kettlebell Training"
       case kickboxing = "Kickboxing"
       case martialArts = "Martial Arts"
       case obstacleCourseRacing = "Obstacle Course Racing"
       case olympicWeightlifting = "Olympic Weightlifting"
       case parkour = "Parkour"
       case partnerTraining = "Partner Training"
       case pilates = "Pilates"
       case rockClimbing = "Rock Climbing"
       case rollerSkating = "Roller Skating"
       case rowing = "Rowing"
       case running = "Running"
       case skateboarding = "Skateboarding"
       case skiing = "Skiing"
       case speedSkating = "Speed Skating"
       case strengthTraining = "Strength Training"
       case surfing = "Surfing"
       case swimming = "Swimming"
       case tennis = "Tennis"
       case triathlon = "Triathlon"
       case volleyball = "Volleyball"
       case wrestling = "Wrestling"
       case yoga = "Yoga"
}

import Foundation

/// GPS position
public struct Position: Codable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Int?
    public let speed: Int?
    public let heading: Int?
    public let time: Date
    public let accuracy: Int
    
    public init(
        latitude: Double,
        longitude: Double,
        altitude: Int?,
        speed: Int?,
        heading: Int?,
        time: Date,
        accuracy: Int
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.heading = heading
        self.time = time
        self.accuracy = accuracy
    }
}


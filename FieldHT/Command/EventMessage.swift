import Foundation

/// Event message types
public enum EventMessage {
    case statusChanged(Status)
    case radioStatusChanged(Status)
    case channelChanged(Channel)
    case settingsChanged(Settings)
    case beaconSettingsChanged(BeaconSettings)
    case positionChanged(Position)
    case tncDataFragmentReceived(TncDataFragment)
    case tncDataFragmentTransmitted(TncDataFragment)
    case raw(EventType, Data)
}

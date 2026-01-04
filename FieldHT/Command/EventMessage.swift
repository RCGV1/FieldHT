import Foundation

/// Event message types
public enum EventMessage {
    case statusChanged(Status)
    case channelChanged(Channel)
    case settingsChanged(Settings)
    case tncDataFragmentReceived(TncDataFragment)
    case unknown(Data)
}


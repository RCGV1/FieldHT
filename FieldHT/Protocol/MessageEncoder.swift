import Foundation

/// Protocol message encoder/decoder (legacy - use ProtocolEncoder/ProtocolDecoder)
public struct MessageEncoder {
    /// Encode a command message to bytes
    public static func encode(
        commandGroup: CommandGroup,
        command: UInt16,
        isReply: Bool = false,
        body: Data = Data()
    ) -> Data {
        return ProtocolEncoder.encodeMessage(
            commandGroup: commandGroup,
            command: command,
            isReply: isReply,
            body: body
        )
    }
    
    /// Decode bytes to a protocol message
    public static func decode(_ data: Data) -> (commandGroup: CommandGroup, command: UInt16, isReply: Bool, body: Data)? {
        do {
            let message = try ProtocolDecoder.decodeMessage(data)
            return (message.commandGroup, message.command, message.isReply, message.body)
        } catch {
            return nil
        }
    }
}


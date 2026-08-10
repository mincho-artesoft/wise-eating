import CoreMedia

/// Exact frame positions for frame-packed media archives.
///
/// Constructing CMTime from decimal seconds truncates some non-terminating
/// frame times and can return the preceding image under zero tolerance.
enum FrameArchiveClock {
    static func time(
        forFrameIndex frameIndex: Int,
        framesPerSecond: Int64,
        timescale: CMTimeScale
    ) -> CMTime {
        precondition(frameIndex >= 0, "Frame index must not be negative")
        precondition(framesPerSecond > 0, "Frame rate must be positive")
        let integerTimescale = Int64(timescale)
        precondition(integerTimescale > 0, "Media timescale must be positive")
        precondition(
            integerTimescale % framesPerSecond == 0,
            "Media timescale must divide evenly by its frame rate"
        )
        let ticksPerFrame = integerTimescale / framesPerSecond
        return CMTime(
            value: Int64(frameIndex) * ticksPerFrame,
            timescale: timescale
        )
    }
}

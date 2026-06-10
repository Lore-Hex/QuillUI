import Foundation

open class TGDataItem: NSObject {
    private var storage: Data

    public override init() {
        self.storage = Data()
        super.init()
    }

    public init(data: Data!) {
        self.storage = data ?? Data()
        super.init()
    }

    open func appendData(_ data: Data!) {
        guard let data else { return }
        storage.append(data)
    }

    open func data() -> Data! {
        storage
    }
}

open class TGOggOpusWriter: NSObject {
    private weak var dataItem: TGDataItem?
    private var byteCount: UInt = 0
    private var duration: TimeInterval = 0

    public override init() {
        super.init()
    }

    open func begin(with dataItem: TGDataItem) -> Bool {
        self.dataItem = dataItem
        self.byteCount = 0
        self.duration = 0
        return true
    }

    open func beginAppend(with dataItem: TGDataItem) -> Bool {
        self.dataItem = dataItem
        self.byteCount = UInt(dataItem.data()?.count ?? 0)
        return true
    }

    open func writeFrame(_ framePcmBytes: UnsafeMutablePointer<UInt8>?, frameByteCount: UInt) -> Bool {
        guard frameByteCount > 0, let framePcmBytes else {
            return true
        }
        dataItem?.appendData(Data(bytes: framePcmBytes, count: Int(frameByteCount)))
        byteCount += frameByteCount
        duration += Double(frameByteCount) / 48_000.0
        return true
    }

    open func encodedBytes() -> UInt {
        byteCount
    }

    open func encodedDuration() -> TimeInterval {
        duration
    }

    open func pause() -> [String: Any] {
        [
            "byteCount": byteCount,
            "duration": duration
        ]
    }

    open func resume(with dataItem: TGDataItem, encoderState state: [String: Any]) -> Bool {
        self.dataItem = dataItem
        self.byteCount = (state["byteCount"] as? NSNumber)?.uintValue ?? UInt(dataItem.data()?.count ?? 0)
        self.duration = (state["duration"] as? NSNumber)?.doubleValue ?? 0
        return true
    }
}

open class OggOpusFrame: NSObject {
    public let numSamples: Int32
    public let data: Data

    public init(numSamples: Int32 = 0, data: Data = Data()) {
        self.numSamples = numSamples
        self.data = data
        super.init()
    }
}

open class OggOpusReader: NSObject {
    public let path: String

    public init?(path: String) {
        self.path = path
        super.init()
    }

    open func read(_ pcmData: UnsafeMutableRawPointer?, bufSize: Int32) -> Int32 {
        _ = (pcmData, bufSize)
        return 0
    }

    open class func extractFrames(_ data: Data) -> [OggOpusFrame]? {
        _ = data
        return []
    }
}

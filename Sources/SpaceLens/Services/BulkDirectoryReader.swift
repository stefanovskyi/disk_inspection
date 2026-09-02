import Foundation
import Darwin

enum LowLevelFileKind: Equatable, Sendable {
    case directory
    case regular
    case symbolicLink
    case other
}

struct LowLevelFileMetadata: Sendable {
    let name: String
    let kind: LowLevelFileKind
    let size: Int64
    let identity: FileIdentity?
    let isReadable: Bool
}

struct LowLevelDirectoryEntry: Sendable {
    let url: URL
    let metadata: LowLevelFileMetadata?
}

enum LowLevelMetadataReader {
    static func metadata(at url: URL) throws -> LowLevelFileMetadata {
        var value = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.lstat(path, &value)
        }
        guard result == 0 else { throw posixError() }

        let type = value.st_mode & mode_t(S_IFMT)
        let kind: LowLevelFileKind
        switch type {
        case mode_t(S_IFDIR): kind = .directory
        case mode_t(S_IFREG): kind = .regular
        case mode_t(S_IFLNK): kind = .symbolicLink
        default: kind = .other
        }

        let allocatedBytes = value.st_blocks.multipliedReportingOverflow(by: 512)
        let size = allocatedBytes.overflow
            ? Int64.max
            : max(Int64(allocatedBytes.partialValue), 0)

        return LowLevelFileMetadata(
            name: displayName(for: url),
            kind: kind,
            size: size,
            identity: FileIdentity(
                device: UInt64(bitPattern: Int64(value.st_dev)),
                inode: UInt64(value.st_ino)
            ),
            isReadable: true
        )
    }

    private static func displayName(for url: URL) -> String {
        if url.path == "/" { return "Macintosh HD" }
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    fileprivate static func posixError(_ code: Int32 = errno) -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
}

/// Reads directory names and metadata in kernel-sized batches with getattrlistbulk(2).
/// The syscall reports symbolic-link metadata without following the link.
enum BulkDirectoryReader {
    static let minimumBufferSize = 4 * 1024
    static let defaultBufferSize = 64 * 1024
    private static let signpostEntryThreshold = 256
    private static let signpostDurationThresholdNanoseconds: UInt64 = 1_000_000
    private static let standaloneBufferPool = BulkDirectoryBufferPool(
        capacity: 1,
        bufferSize: defaultBufferSize
    )

    static func contents(of directoryURL: URL) throws -> [LowLevelDirectoryEntry] {
        try contents(of: directoryURL, using: standaloneBufferPool)
    }

    static func contents(
        of directoryURL: URL,
        using bufferPool: BulkDirectoryBufferPool,
        diagnostics: ScanDiagnosticCounters? = nil
    ) throws -> [LowLevelDirectoryEntry] {
        let signposter = SpaceLensSignposts.directoryRead
        let measuresSignpost = signposter.isEnabled
        let signpostStart = measuresSignpost ? DispatchTime.now().uptimeNanoseconds : 0
        var measuredEntryCount = 0
        defer {
            if measuresSignpost {
                let duration = DispatchTime.now().uptimeNanoseconds &- signpostStart
                if measuredEntryCount >= signpostEntryThreshold
                    || duration >= signpostDurationThresholdNanoseconds {
                    signposter.emitEvent(
                        "DirectoryReadSample",
                        "entries=\(measuredEntryCount) durationNanoseconds=\(duration)"
                    )
                }
            }
        }

        let descriptor = directoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw LowLevelMetadataReader.posixError() }
        defer { Darwin.close(descriptor) }

        return try bufferPool.withBuffer { buffer, requestedAttributes in
            var entries: [LowLevelDirectoryEntry] = []

            while true {
                let count = getattrlistbulk(
                    descriptor,
                    requestedAttributes,
                    buffer.baseAddress,
                    buffer.count,
                    0
                )

                guard count >= 0 else { throw LowLevelMetadataReader.posixError() }
                guard count > 0 else { return entries }
                diagnostics?.recordSyscallBatch()
                measuredEntryCount += Int(count)

                try parseBatch(
                    buffer,
                    entryCount: count,
                    parentURL: directoryURL,
                    diagnostics: diagnostics,
                    appendingTo: &entries
                )
            }
        }
    }

    private static func parseBatch(
        _ buffer: UnsafeMutableRawBufferPointer,
        entryCount: Int32,
        parentURL: URL,
        diagnostics: ScanDiagnosticCounters?,
        appendingTo entries: inout [LowLevelDirectoryEntry]
    ) throws {
        let bytes = UnsafeRawBufferPointer(buffer)
        var entryOffset = 0
        for _ in 0..<Int(entryCount) {
            let entry = try parseEntry(
                in: bytes,
                at: entryOffset,
                parentURL: parentURL,
                diagnostics: diagnostics
            )
            entries.append(entry.value)
            entryOffset += entry.length
        }
    }

    private static func parseEntry(
        in batch: UnsafeRawBufferPointer,
        at offset: Int,
        parentURL: URL,
        diagnostics: ScanDiagnosticCounters?
    ) throws -> (value: LowLevelDirectoryEntry, length: Int) {
        var lengthCursor = AttributeCursor(bytes: batch, offset: offset, limit: batch.count)
        let recordLength = Int(try lengthCursor.read(UInt32.self, default: 0))
        guard recordLength >= MemoryLayout<UInt32>.size,
              offset <= batch.count - recordLength else {
            throw LowLevelMetadataReader.posixError(EIO)
        }

        var cursor = AttributeCursor(
            bytes: batch,
            offset: offset + MemoryLayout<UInt32>.size,
            limit: offset + recordLength
        )
        let returned = try cursor.read(attribute_set_t.self, default: attribute_set_t())

        // ATTR_CMN_ERROR is a special case: getattrlistbulk places it immediately
        // after ATTR_CMN_RETURNED_ATTRS rather than in normal common-attribute order.
        let entryError: UInt32
        if returned.commonattr & UInt32(ATTR_CMN_ERROR) != 0 {
            entryError = try cursor.read(UInt32.self, default: 0)
        } else {
            entryError = 0
        }

        guard returned.commonattr & UInt32(ATTR_CMN_NAME) != 0 else {
            throw LowLevelMetadataReader.posixError(EIO)
        }
        let nameReferenceOffset = cursor.offset
        let nameReference = try cursor.read(attrreference_t.self, default: attrreference_t())
        let name = try readName(
            reference: nameReference,
            referenceOffset: nameReferenceOffset,
            bytes: batch,
            recordStart: offset,
            recordEnd: offset + recordLength
        )

        var device: dev_t?
        if returned.commonattr & UInt32(ATTR_CMN_DEVID) != 0 {
            device = try cursor.read(dev_t.self, default: 0)
        }

        var objectType: fsobj_type_t?
        if returned.commonattr & UInt32(ATTR_CMN_OBJTYPE) != 0 {
            objectType = try cursor.read(fsobj_type_t.self, default: 0)
        }

        var inode: UInt64?
        if returned.commonattr & UInt32(ATTR_CMN_FILEID) != 0 {
            inode = try cursor.read(UInt64.self, default: 0)
        }

        var logicalSize: off_t?
        if returned.fileattr & UInt32(ATTR_FILE_TOTALSIZE) != 0 {
            logicalSize = try cursor.read(off_t.self, default: 0)
        }

        var allocatedSize: off_t?
        if returned.fileattr & UInt32(ATTR_FILE_ALLOCSIZE) != 0 {
            allocatedSize = try cursor.read(off_t.self, default: 0)
        }

        let kind = kind(for: objectType)
        let entryURL = parentURL.appendingPathComponent(name, isDirectory: kind == .directory)
        let identity: FileIdentity?
        if let device, let inode {
            identity = FileIdentity(
                device: UInt64(bitPattern: Int64(device)),
                inode: inode
            )
        } else {
            identity = nil
        }

        let bulkMetadata: LowLevelFileMetadata?
        if let kind {
            let reportedSize = allocatedSize ?? logicalSize
            if kind == .directory || reportedSize != nil {
                bulkMetadata = LowLevelFileMetadata(
                    name: name,
                    kind: kind,
                    size: max(Int64(reportedSize ?? 0), 0),
                    identity: identity,
                    isReadable: entryError == 0
                )
            } else {
                bulkMetadata = nil
            }
        } else {
            bulkMetadata = nil
        }

        // Filesystems may omit optional attributes. Fall back to one lstat(2)
        // only for those entries; APFS's normal path remains fully batched.
        let metadata: LowLevelFileMetadata?
        if entryError != 0 {
            metadata = bulkMetadata ?? LowLevelFileMetadata(
                name: name,
                kind: kind ?? .other,
                size: 0,
                identity: identity,
                isReadable: false
            )
        } else if let bulkMetadata,
                  bulkMetadata.identity != nil || bulkMetadata.kind != .directory {
            metadata = bulkMetadata
        } else {
            diagnostics?.recordFallbackLstat()
            metadata = try? LowLevelMetadataReader.metadata(at: entryURL)
        }

        return (
            LowLevelDirectoryEntry(url: entryURL, metadata: metadata),
            recordLength
        )
    }

    private static func kind(for objectType: fsobj_type_t?) -> LowLevelFileKind? {
        guard let objectType else { return nil }
        switch objectType {
        case fsobj_type_t(VDIR.rawValue): return .directory
        case fsobj_type_t(VREG.rawValue): return .regular
        case fsobj_type_t(VLNK.rawValue): return .symbolicLink
        default: return .other
        }
    }

    private static func readName(
        reference: attrreference_t,
        referenceOffset: Int,
        bytes: UnsafeRawBufferPointer,
        recordStart: Int,
        recordEnd: Int
    ) throws -> String {
        let start = referenceOffset + Int(reference.attr_dataoffset)
        let length = Int(reference.attr_length)
        guard start >= recordStart,
              length > 0,
              start <= recordEnd - length else {
            throw LowLevelMetadataReader.posixError(EIO)
        }

        let rawName = UnsafeRawBufferPointer(rebasing: bytes[start..<(start + length)])
        let terminator = rawName.firstIndex(of: 0) ?? rawName.endIndex
        return String(decoding: rawName[..<terminator], as: UTF8.self)
    }
}

final class ScanDiagnosticCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ScanDiagnosticSnapshot()

    func recordSyscallBatch() {
        lock.withLock { value.syscallBatches += 1 }
    }

    func recordFallbackLstat() {
        lock.withLock { value.fallbackLstatCalls += 1 }
    }

    func recordDirectoryTask() {
        lock.withLock { value.directoryTasks += 1 }
    }

    func recordNodeDecisions(retained: Int, discarded: Int) {
        lock.withLock {
            value.retainedNodes += retained
            value.discardedNodes += discarded
        }
    }

    func recordProgressEmission() {
        lock.withLock { value.progressEmissions += 1 }
    }

    func snapshot(bufferAllocations: Int) -> ScanDiagnosticSnapshot {
        lock.withLock {
            var snapshot = value
            snapshot.bufferAllocations = bufferAllocations
            return snapshot
        }
    }
}

/// Retains at most one reusable, uninitialized syscall buffer per scan worker.
/// If an isolated provider syscall outlives its timeout while holding every pooled
/// buffer, later reads use short-lived overflow buffers rather than waiting on it.
final class BulkDirectoryBufferPool: @unchecked Sendable {
    let capacity: Int
    let bufferSize: Int

    private let lock = NSLock()
    private var availableBuffers: [BulkDirectoryBuffer] = []
    private var pooledAllocations = 0
    private var totalAllocations = 0

    init(capacity: Int, bufferSize: Int) {
        precondition(capacity > 0)
        precondition(bufferSize >= BulkDirectoryReader.minimumBufferSize)
        self.capacity = capacity
        self.bufferSize = bufferSize
    }

    var pooledBufferCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pooledAllocations
    }

    var allocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalAllocations
    }

    func withBuffer<Result>(
        _ body: (
            UnsafeMutableRawBufferPointer,
            UnsafeMutablePointer<attrlist>
        ) throws -> Result
    ) rethrows -> Result {
        let lease = acquire()
        defer { release(lease) }

        return try lease.buffer.withUnsafeResources(body)
    }

    private func acquire() -> BufferLease {
        lock.lock()
        if let buffer = availableBuffers.popLast() {
            lock.unlock()
            return BufferLease(buffer: buffer, isPooled: true)
        }

        let isPooled = pooledAllocations < capacity
        if isPooled {
            pooledAllocations += 1
        }
        totalAllocations += 1
        lock.unlock()

        return BufferLease(
            buffer: BulkDirectoryBuffer(byteCount: bufferSize),
            isPooled: isPooled
        )
    }

    private func release(_ lease: BufferLease) {
        guard lease.isPooled else { return }
        lock.lock()
        availableBuffers.append(lease.buffer)
        lock.unlock()
    }
}

private struct BufferLease {
    let buffer: BulkDirectoryBuffer
    let isPooled: Bool
}

private final class BulkDirectoryBuffer {
    private let bytes: UnsafeMutableRawPointer
    private let byteCount: Int
    private var requestedAttributes: attrlist

    init(byteCount: Int) {
        self.byteCount = byteCount
        bytes = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<UInt64>.alignment
        )

        var requested = attrlist()
        requested.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        requested.commonattr = UInt32(ATTR_CMN_RETURNED_ATTRS)
            | UInt32(ATTR_CMN_NAME)
            | UInt32(ATTR_CMN_DEVID)
            | UInt32(ATTR_CMN_OBJTYPE)
            | UInt32(ATTR_CMN_FILEID)
            | UInt32(ATTR_CMN_ERROR)
        requested.fileattr = UInt32(ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE)
        requestedAttributes = requested
    }

    deinit {
        bytes.deallocate()
    }

    func withUnsafeResources<Result>(
        _ body: (
            UnsafeMutableRawBufferPointer,
            UnsafeMutablePointer<attrlist>
        ) throws -> Result
    ) rethrows -> Result {
        try withUnsafeMutablePointer(to: &requestedAttributes) { requestedAttributes in
            try body(
                UnsafeMutableRawBufferPointer(start: bytes, count: byteCount),
                requestedAttributes
            )
        }
    }
}

private struct AttributeCursor {
    let bytes: UnsafeRawBufferPointer
    var offset: Int
    let limit: Int

    mutating func read<T>(_ type: T.Type, default defaultValue: T) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset <= limit - size else {
            throw LowLevelMetadataReader.posixError(EIO)
        }

        var value = defaultValue
        withUnsafeMutableBytes(of: &value) { destination in
            destination.copyBytes(from: bytes[offset..<(offset + size)])
        }
        offset += (size + 3) & ~3
        return value
    }
}

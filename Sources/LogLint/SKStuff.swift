import Foundation

public protocol SKQueueDelegate {
  func receivedNotification(_ notification: SKQueueNotification, path: String, queue: SKQueue)
}

public enum SKQueueNotificationString: String {
  case Rename
  case Write
  case Delete
  case AttributeChange
  case SizeIncrease
  case LinkCountChange
  case AccessRevocation
  case Unlock
  case DataAvailable
}

public struct SKQueueNotification: OptionSet {
  public let rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  public static let None             = SKQueueNotification(rawValue: 0)
  public static let Rename           = SKQueueNotification(rawValue: UInt32(NOTE_RENAME))
  public static let Write            = SKQueueNotification(rawValue: UInt32(NOTE_WRITE))
  public static let Delete           = SKQueueNotification(rawValue: UInt32(NOTE_DELETE))
  public static let AttributeChange  = SKQueueNotification(rawValue: UInt32(NOTE_ATTRIB))
  public static let SizeIncrease     = SKQueueNotification(rawValue: UInt32(NOTE_EXTEND))
  public static let LinkCountChange  = SKQueueNotification(rawValue: UInt32(NOTE_LINK))
  public static let AccessRevocation = SKQueueNotification(rawValue: UInt32(NOTE_REVOKE))
  public static let Unlock           = SKQueueNotification(rawValue: UInt32(NOTE_FUNLOCK))
  public static let DataAvailable    = SKQueueNotification(rawValue: UInt32(NOTE_NONE))
  public static let Default          = SKQueueNotification(rawValue: UInt32(INT_MAX))

  public func toStrings() -> [SKQueueNotificationString] {
    var s = [SKQueueNotificationString]()
    if contains(.Rename)           { s.append(.Rename) }
    if contains(.Write)            { s.append(.Write) }
    if contains(.Delete)           { s.append(.Delete) }
    if contains(.AttributeChange)  { s.append(.AttributeChange) }
    if contains(.SizeIncrease)     { s.append(.SizeIncrease) }
    if contains(.LinkCountChange)  { s.append(.LinkCountChange) }
    if contains(.AccessRevocation) { s.append(.AccessRevocation) }
    if contains(.Unlock)           { s.append(.Unlock) }
    if contains(.DataAvailable)    { s.append(.DataAvailable) }
    return s
  }
}

public class SKQueue {
  private let kqueueId: Int32
  private var watchedPaths = [String: Int32]()
  private var keepWatcherThreadRunning = false
  public var delegate: SKQueueDelegate?

  public init?(delegate: SKQueueDelegate? = nil) {
    kqueueId = kqueue()
    if kqueueId == -1 {
      return nil
    }
    self.delegate = delegate
  }

  deinit {
    keepWatcherThreadRunning = false
    removeAllPaths()
    close(kqueueId)
  }

  public func addPath(_ path: String, notifyingAbout notification: SKQueueNotification = SKQueueNotification.Default) throws {
    var fileDescriptor: Int32! = watchedPaths[path]
    if fileDescriptor == nil {
      fileDescriptor = open(FileManager.default.fileSystemRepresentation(withPath: path), O_EVTONLY)
      guard fileDescriptor >= 0 else {
        throw NSError()
        }
      watchedPaths[path] = fileDescriptor
    }

    var edit = kevent(
      ident: UInt(fileDescriptor),
      filter: Int16(EVFILT_VNODE),
      flags: UInt16(EV_ADD | EV_CLEAR),
      fflags: notification.rawValue,
      data: 0,
      udata: nil
    )
    kevent(kqueueId, &edit, 1, nil, 0, nil)

    if !keepWatcherThreadRunning {
      keepWatcherThreadRunning = true
      DispatchQueue.global().async(execute: watcherThread)
    }
  }

  private func watcherThread() {
    var event = kevent()
    var timeout = timespec(tv_sec: 1, tv_nsec: 0)
    while (keepWatcherThreadRunning) {
      if kevent(kqueueId, nil, 0, &event, 1, &timeout) > 0 && event.filter == EVFILT_VNODE && event.fflags > 0 {
        guard let (path, _) = watchedPaths.first(where: { $1 == event.ident }) else { continue }
        let notification = SKQueueNotification(rawValue: event.fflags)
        DispatchQueue.global().async {
          self.delegate?.receivedNotification(notification, path: path, queue: self)
        }
      }
    }
  }

  public func isPathWatched(_ path: String) -> Bool {
    return watchedPaths[path] != nil
  }

  public func removePath(_ path: String) {
    if let fileDescriptor = watchedPaths.removeValue(forKey: path) {
      close(fileDescriptor)
    }
  }

  public func removeAllPaths() {
    watchedPaths.keys.forEach(removePath)
  }

  public func numberOfWatchedPaths() -> Int {
    return watchedPaths.count
  }

  public func fileDescriptorForPath(_ path: String) -> Int32 {
    if let fileDescriptor = watchedPaths[path] {
      return fcntl(fileDescriptor, F_DUPFD)
    }
    return -1
  }
}

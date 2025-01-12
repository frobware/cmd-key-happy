import Foundation

@inline(__always)
func debugVariable<T: AnyObject>(_ name: String, _ object: T, file: String = #file, line: Int = #line) {
    let retainCount = CFGetRetainCount(object as CFTypeRef)
    let address = Unmanaged.passUnretained(object).toOpaque()
    let filename = (file as NSString).lastPathComponent
    CKHLog.debug("RC [\(filename):\(line)]:\(name)(\(type(of: object)) \(address)) \(retainCount)")
}

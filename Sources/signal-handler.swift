import Dispatch

/// Manages Unix signal handling using GCD dispatch sources.
///
/// This class allows multiple signals to share the same action and
/// ensures safe handling by transitioning signal handling from the
/// asynchronous context, where only a limited set of operations are
/// safe, to the main dispatch queue.
class SignalHandler {
    private var signalSources: [Int32: DispatchSourceSignal] = [:]
    private var sharedHandlers: [(signals: [Int32], action: (Int32) -> Void)] = []

    /// Adds a handler for one or more signals.
    ///
    /// - Parameters:
    ///   - signals: An array of signal numbers to handle.
    ///   - action: A closure to execute when any of the signals is received.
    ///             The signal number is passed to the closure.
    func addHandler(for signals: [Int32], action: @escaping (Int32) -> Void) {
        for signo in signals {
            guard !sharedHandlers.contains(where: { $0.signals.contains(signo) }) else {
                continue
            }
            signal(signo, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signo, queue: .main)
            source.setEventHandler {
                action(signo)
            }
            source.resume()
            signalSources[signo] = source
        }

        sharedHandlers.append((signals: signals, action: action))
    }

    /// Removes a handler for the specified signals.
    ///
    /// - Parameter signals: The signals to stop handling.
    func removeHandler(for signals: [Int32]) {
        for signo in signals {
            signalSources[signo]?.cancel()
            signalSources.removeValue(forKey: signo)
        }
        sharedHandlers.removeAll { handler in
            handler.signals.allSatisfy(signals.contains)
        }
    }

    /// Cancels all active signal sources and cleans up resources.
    func cleanup() {
        signalSources.values.forEach { $0.cancel() }
        signalSources.removeAll()
        sharedHandlers.removeAll()
    }

    deinit {
        cleanup()
    }
}

import Foundation
import Network

struct AgentHookCallback {
    let paneId: String
    let tabId: String
    let workspaceId: String
    let projectId: String
    let provider: String
    let eventType: AgentHookEvent
    let rawEventName: String
}

/// Loopback HTTP server that receives notify-hook callbacks from running agents.
/// Binds to 127.0.0.1 on a kernel-assigned port; the port is written to
/// `~/.cterm/hooks/port` so the shell hook script can read it without the
/// CTERM_PORT env var being present.
final class AgentHookServer {
    static let shared = AgentHookServer()

    private let queue = DispatchQueue(label: "cterm.agent-hook-server", qos: .utility)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private(set) var port: UInt16 = 0

    /// Fired on the main queue whenever a hook callback is received.
    var onEvent: ((AgentHookCallback) -> Void)?

    private init() {}

    func start() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            do {
                let params = NWParameters.tcp
                params.requiredLocalEndpoint = NWEndpoint.hostPort(
                    host: .ipv4(.loopback),
                    port: .any
                )
                params.allowLocalEndpointReuse = true
                let listener = try NWListener(using: params)
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handleListenerState(state)
                }
                listener.newConnectionHandler = { [weak self] conn in
                    self?.accept(conn)
                }
                listener.start(queue: self.queue)
                self.listener = listener
            } catch {
                NSLog("[agent-hook] listener start failed: \(error)")
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            for (_, conn) in self?.connections ?? [:] { conn.cancel() }
            self?.connections.removeAll()
            self?.port = 0
        }
    }

    // MARK: - Connection handling

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue {
                self.port = port
                writePortFile(port)
            }
        case .failed(let error):
            NSLog("[agent-hook] listener failed: \(error)")
            listener?.cancel()
            listener = nil
        default:
            break
        }
    }

    private func accept(_ conn: NWConnection) {
        let key = ObjectIdentifier(conn)
        connections[key] = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async { self?.connections.removeValue(forKey: key) }
            default:
                break
            }
        }
        conn.start(queue: queue)
        receive(on: conn, buffer: Data())
    }

    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let error {
                NSLog("[agent-hook] receive error: \(error)")
                conn.cancel()
                return
            }

            var next = buffer
            if let data, !data.isEmpty { next.append(data) }

            if self.tryHandle(request: next, on: conn) {
                return
            }

            if complete {
                conn.cancel()
                return
            }

            if next.count > 16 * 1024 {
                // Oversized request; not a legitimate hook call.
                conn.cancel()
                return
            }

            self.receive(on: conn, buffer: next)
        }
    }

    /// Returns true when a full HTTP request has been parsed and responded to.
    private func tryHandle(request data: Data, on conn: NWConnection) -> Bool {
        guard let headerEnd = findHeaderEnd(in: data) else { return false }
        let headerData = data.prefix(headerEnd)
        guard let header = String(data: headerData, encoding: .utf8) else {
            respond(conn, status: "400 Bad Request")
            return true
        }

        let lines = header.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).map(String.init)
        guard let requestLine = lines.first else {
            respond(conn, status: "400 Bad Request")
            return true
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            respond(conn, status: "405 Method Not Allowed")
            return true
        }

        let target = String(parts[1])
        guard let (path, query) = splitTarget(target), path == "/hook/complete" else {
            respond(conn, status: "404 Not Found")
            return true
        }

        let params = parseQuery(query)
        if let callback = makeCallback(from: params) {
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(callback)
            }
        }

        respond(conn, status: "204 No Content")
        return true
    }

    private func respond(_ conn: NWConnection, status: String) {
        let body = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        conn.send(content: body.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: - Parsing helpers

    private func findHeaderEnd(in data: Data) -> Int? {
        let pattern: [UInt8] = [0x0d, 0x0a, 0x0d, 0x0a]
        guard data.count >= pattern.count else { return nil }
        for i in 0...(data.count - pattern.count) {
            var matched = true
            for j in 0..<pattern.count {
                if data[data.startIndex + i + j] != pattern[j] { matched = false; break }
            }
            if matched { return i + pattern.count }
        }
        return nil
    }

    private func splitTarget(_ target: String) -> (String, String)? {
        if let q = target.firstIndex(of: "?") {
            let path = String(target[..<q])
            let query = String(target[target.index(after: q)...])
            return (path, query)
        }
        return (target, "")
    }

    private func parseQuery(_ query: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = kv.first.map(String.init)?.removingPercentEncoding else { continue }
            let value = kv.count > 1
                ? String(kv[1]).removingPercentEncoding ?? ""
                : ""
            if !key.isEmpty { out[key] = value }
        }
        return out
    }

    private func makeCallback(from params: [String: String]) -> AgentHookCallback? {
        let paneId = params["paneId"] ?? ""
        guard !paneId.isEmpty else { return nil }

        let rawEvent = params["eventType"] ?? ""
        guard let event = AgentHookEventMapper.map(rawEvent) else { return nil }

        return AgentHookCallback(
            paneId: paneId,
            tabId: params["tabId"] ?? "",
            workspaceId: params["workspaceId"] ?? "",
            projectId: params["projectId"] ?? "",
            provider: params["provider"] ?? "",
            eventType: event,
            rawEventName: rawEvent
        )
    }

    // MARK: - Port file

    private func writePortFile(_ port: UInt16) {
        let url = AgentHookLayout.portFile
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? String(port).data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

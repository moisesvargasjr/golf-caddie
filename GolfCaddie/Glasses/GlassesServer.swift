import Foundation
import Network

// Embedded loopback HTTP server for the glasses integration.
// Contract: golf-caddie-glasses/docs/IOS_INTEGRATION_CONTRACT.md
//
// Bound to 127.0.0.1:8417 only (never 0.0.0.0 — round data must not leave the
// phone). One low-frequency client (the Even App WebView on the same device).
// NWConnection callbacks run off the main actor; every request hops to
// @MainActor before touching RoundController, and for POST the mutation and
// the response snapshot happen in one hop with no await between, so
// read-after-write holds by construction.
@MainActor
final class GlassesServer {
    static let port: UInt16 = 8417

    private var listener: NWListener?
    private weak var controller: RoundController?
    private unowned let location: LocationManager
    private let battery = BatteryMonitor()
    private let queue = DispatchQueue(label: "com.moisesvargasjr.golfcaddie.glasses-server")
    private let encoder = JSONEncoder()

    init(location: LocationManager) {
        self.location = location
    }

    func attach(controller: RoundController) {
        self.controller = controller
    }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: Self.port)!
        )
        guard let listener = try? NWListener(using: params) else {
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in self?.stop() }
            }
        }
        let connectionQueue = queue
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: connectionQueue)
            self?.receiveRequest(connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - HTTP plumbing (off-main)

    private nonisolated func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data, !data.isEmpty { buffer.append(data) }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: buffer.startIndex ..< headerEnd.lowerBound)
                let (method, path) = Self.parseRequestLine(headerData)
                let contentLength = Self.contentLength(headerData)
                let bodyStart = headerEnd.upperBound
                let received = buffer.distance(from: bodyStart, to: buffer.endIndex)

                // Wait for the full declared body before dispatching (only
                // matters for POST /api/club; the other endpoints send no body
                // so contentLength is 0 and this is a no-op).
                if received < contentLength && error == nil && !isComplete {
                    self.receiveRequest(connection, buffer: buffer)
                    return
                }

                let requestBody = contentLength > 0
                    ? buffer.subdata(in: bodyStart ..< buffer.index(bodyStart, offsetBy: min(contentLength, received)))
                    : Data()

                Task { @MainActor in
                    let (status, body) = self.handle(method: method, path: path, requestBody: requestBody)
                    let response = Self.httpResponse(status: status, jsonBody: body)
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receiveRequest(connection, buffer: buffer)
        }
    }

    private nonisolated static func parseRequestLine(_ headerData: Data) -> (method: String, path: String) {
        guard let text = String(data: headerData, encoding: .utf8),
              let firstLine = text.split(separator: "\r\n", maxSplits: 1).first
        else { return ("", "") }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return ("", "") }
        return (String(parts[0]).uppercased(), String(parts[1]))
    }

    private nonisolated static func contentLength(_ headerData: Data) -> Int {
        guard let text = String(data: headerData, encoding: .utf8) else { return 0 }
        for line in text.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
            else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    private nonisolated static func httpResponse(status: Int, jsonBody: Data) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        default: reason = "OK"
        }
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        header += "Content-Length: \(jsonBody.count)\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"
        var data = Data(header.utf8)
        data.append(jsonBody)
        return data
    }

    // MARK: - Routing (@MainActor — mutate then map in one hop)

    private func handle(method: String, path: String, requestBody: Data) -> (Int, Data) {
        if method == "OPTIONS" {
            return (204, Data())
        }

        switch (method, path) {
        case ("GET", "/api/health"):
            return (200, Data(#"{"ok":true}"#.utf8))

        case ("GET", "/api/state"):
            return (200, encodeState())

        case ("POST", "/api/shot"):
            guard let controller, controller.isActive else {
                return (409, noActiveHoleBody())
            }
            do {
                try controller.logShotFromGlasses()
                return (200, encodeState())
            } catch {
                return (409, noActiveHoleBody())
            }

        case ("POST", "/api/shot/undo"):
            guard let controller, controller.isActive else {
                return (409, noActiveHoleBody())
            }
            do {
                try controller.undoLastActionFromGlasses()
                return (200, encodeState())
            } catch {
                return (409, noActiveHoleBody())
            }

        case ("POST", "/api/club"):
            guard let controller, controller.isActive else {
                return (409, noActiveHoleBody())
            }
            guard let shortName = Self.parseClubShortName(requestBody) else {
                return (400, unknownClubBody())
            }
            do {
                try controller.setCurrentClubFromGlasses(shortName: shortName)
                return (200, encodeState())
            } catch GlassesError.unknownClub {
                return (400, unknownClubBody())
            } catch {
                return (409, noActiveHoleBody())
            }

        case ("POST", "/api/hole/advance"):
            guard let controller, controller.isActive else {
                return (409, noActiveHoleBody())
            }
            do {
                try controller.advanceHoleFromGlasses()
                return (200, encodeState())
            } catch {
                return (409, noActiveHoleBody())
            }

        default:
            return (404, Data(#"{"error":"not_found"}"#.utf8))
        }
    }

    private func encodeState() -> Data {
        let state: GolfState
        if let controller {
            state = GlassesStateMapper.snapshot(
                controller: controller,
                location: location,
                batteryPercent: battery.percent
            )
        } else {
            state = .idle
        }
        return (try? encoder.encode(state)) ?? Data(#"{"contractVersion":1,"active":false}"#.utf8)
    }

    private func noActiveHoleBody() -> Data {
        Data(#"{"error":"no_active_hole"}"#.utf8)
    }

    private func unknownClubBody() -> Data {
        Data(#"{"error":"unknown_club"}"#.utf8)
    }

    /// Extract the `club` short name from a `{"club":"<shortName>"}` body.
    /// Returns nil for missing/malformed JSON or an empty/non-string value;
    /// the caller maps that to 400 unknown_club (the contract treats an
    /// unparseable club the same as an unknown one).
    private nonisolated static func parseClubShortName(_ body: Data) -> String? {
        guard !body.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let club = obj["club"] as? String,
              !club.isEmpty
        else { return nil }
        return club
    }
}

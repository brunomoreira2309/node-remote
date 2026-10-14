import Foundation
import Security
import CryptoKit

enum TVCertificateDecision: Equatable { case matched, approvalRequired, rejected }
enum TVCertificatePolicy {
    static func decide(expected: String?, received: String, canApprove: Bool) -> TVCertificateDecision {
        if let expected { return expected == received ? .matched : .rejected }
        return canApprove ? .approvalRequired : .rejected
    }
}

// TVs usually have a private certificate. Explicit first-time approval pins
// the leaf for this host; an existing pin must always match, including input sockets.
final class TVCertificateTrust: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    let host: String
    let port: Int
    private let lock = NSLock()
    private var fingerprint: String?
    private var approval: (@Sendable (String, String) async -> Bool)?
    private var trustError: Error?
    private var opening: [Int: CheckedContinuation<Void, Error>] = [:]
    init(host: String, port: Int) { self.host = host; self.port = port }
    func configure(fingerprint: String?, approval: (@Sendable (String, String) async -> Bool)?) {
        lock.lock()
        self.fingerprint = fingerprint
        self.approval = approval
        trustError = nil
        lock.unlock()
    }
    func approvedFingerprint() -> String? {
        lock.lock(); defer { lock.unlock() }
        return fingerprint
    }
    private func reject(_ message: String, _ completion: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        lock.lock(); trustError = RemoteError.message(message); lock.unlock()
        completion(.cancelAuthenticationChallenge, nil)
    }
    private func approve(_ digest: String) {
        lock.lock(); fingerprint = digest; lock.unlock()
    }
    func open(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock(); opening[task.taskIdentifier] = continuation; lock.unlock()
            task.resume()
        }
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        lock.lock(); let continuation = opening.removeValue(forKey: webSocketTask.taskIdentifier); lock.unlock()
        continuation?.resume()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let continuation = opening.removeValue(forKey: task.taskIdentifier); let failure = trustError; lock.unlock()
        continuation?.resume(throwing: failure ?? error ?? RemoteError.message("A conexão com a TV fechou antes de abrir."))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        guard challenge.protectionSpace.host == host, challenge.protectionSpace.port == port,
              let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = certificates.first else {
            reject("A TV não apresentou um certificado para o endereço local escolhido.", completionHandler)
            return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        lock.lock(); let expected = fingerprint; let requestApproval = approval; lock.unlock()
        switch TVCertificatePolicy.decide(expected: expected, received: digest, canApprove: requestApproval != nil) {
        case .matched:
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        case .rejected:
            reject(expected == nil
                ? "Esta TV ainda não tem um certificado confiável. Clique em Conectar para confirmar o primeiro pareamento."
                : "O certificado da TV mudou. Confira o aparelho e pareie de novo nas configurações.", completionHandler)
            return
        case .approvalRequired: break
        }
        guard let requestApproval else {
            reject("Esta TV ainda não tem um certificado confiável. Clique em Conectar para confirmar o primeiro pareamento.", completionHandler)
            return
        }
        Task {
            guard await requestApproval(host, digest) else {
                reject("O certificado da TV não foi aprovado.", completionHandler)
                return
            }
            approve(digest)
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }
}

enum RemoteError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

@MainActor final class WebOSConnection {
    let host: String
    private let session: URLSession
    private let trust: TVCertificateTrust
    private var socket: URLSessionWebSocketTask?
    private lazy var pointerChannel = PointerChannel { [weak self] in
        guard let self else { throw CancellationError() }
        let result = try await request("com.webos.service.networkinput/getPointerInputSocket")
        guard let path = result["socketPath"] as? String, let url = URL(string: path), url.host == host, url.scheme == "wss", url.port == 3001 else {
            throw RemoteError.message("A TV não ofereceu um canal de navegação local compatível.")
        }
        let task = session.webSocketTask(with: url)
        do { try await trust.open(task); try Task.checkCancellation(); return WebSocketPointerTransport(task: task) }
        catch { task.cancel(with: .goingAway, reason: nil); throw error }
    }
    private var receiver: Task<Void, Never>?
    private var waiters: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var subscriptions: [String: ([String: Any]) -> Void] = [:]
    var onPairing: (() -> Void)?
    var onDisconnect: ((Error) -> Void)?
    var onEvent: ((String, String) -> Void)?
    var onPointerState: ((Bool) -> Void)?
    var onCertificateTrust: (@MainActor (String, String) async -> Bool)?
    init(host: String) {
        self.host = host
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        trust = TVCertificateTrust(host: host, port: 3001)
        session = URLSession(configuration: configuration, delegate: trust, delegateQueue: nil)
    }

    func connect(allowFirstUseTrust: Bool = false) async throws {
        guard TVHost.local(host), let url = URL(string: "wss://\(host):3001/") else { throw RemoteError.message("Digite o IPv4 local da TV.") }
        let pairingHost = host
        let saved = await Task.detached(priority: .userInitiated) {
            (PairingKey.read(pairingHost), TVCertificatePin.read(pairingHost))
        }.value
        let storedKey = saved.0, storedPin = saved.1
        let confirmation = onCertificateTrust
        guard storedPin != nil || (allowFirstUseTrust && confirmation != nil) else {
            throw RemoteError.message("Esta TV ainda não tem um certificado confiável. Clique em Conectar para confirmar o primeiro pareamento.")
        }
        let approval: (@Sendable (String, String) async -> Bool)?
        if allowFirstUseTrust {
            approval = { host, fingerprint in await confirmation?(host, fingerprint) ?? false }
        } else { approval = nil }
        trust.configure(fingerprint: storedPin, approval: approval)
        try Task.checkCancellation()
        let ws = session.webSocketTask(with: url); socket = ws
        try await trust.open(ws)
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let frame = try await ws.receive()
                    let data: Data
                    switch frame { case .string(let s): data = Data(s.utf8); case .data(let d): data = d; @unknown default: continue }
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    self?.handle(object)
                }
            } catch { if !Task.isCancelled { self?.failed(error) } }
        }
        guard let path = AppResources.bundle.url(forResource: "registration", withExtension: "json"),
              var payload = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any] else { throw RemoteError.message("O manifesto de pareamento não está disponível.") }
        if let key = storedKey { payload["client-key"] = key }
        let answer = try await exchange(["type": "register", "id": "register", "payload": payload], timeout: 90)
        try Task.checkCancellation()
        guard storedKey != nil || !(answer["client-key"] as? String ?? "").isEmpty else {
            throw RemoteError.message("A TV não forneceu uma chave de pareamento.")
        }
        if let key = answer["client-key"] as? String, key != storedKey {
            try await Task.detached(priority: .userInitiated) { try PairingKey.save(key, host: pairingHost) }.value
        }
        // First-use trust is durable only after the TV has authorized SSAP pairing.
        if storedPin == nil, let fingerprint = trust.approvedFingerprint() {
            try await Task.detached(priority: .userInitiated) { try TVCertificatePin.save(fingerprint, host: pairingHost) }.value
        }
    }
    private func handle(_ object: [String: Any]) {
        guard let id = object["id"] as? String else { return }
        let payload = object["payload"] as? [String: Any] ?? [:]
        let type = object["type"] as? String ?? ""
        if id == "register", type == "response" { onPairing?(); return }
        if type == "error" {
            onEvent?("Erro", object["error"] as? String ?? "A TV recusou o comando.")
            waiters.removeValue(forKey: id)?.resume(throwing: RemoteError.message(object["error"] as? String ?? "A TV recusou o comando.")); return
        }
        if type == "registered" || type == "response" {
            if payload["returnValue"] as? Bool == false {
                waiters.removeValue(forKey: id)?.resume(throwing: RemoteError.message(payload["errorText"] as? String ?? "Este comando não está disponível nesta TV."))
            } else { waiters.removeValue(forKey: id)?.resume(returning: payload); subscriptions[id]?(payload) }
        }
    }
    private func failed(_ error: Error) {
        let pending = waiters; waiters.removeAll(); pending.values.forEach { $0.resume(throwing: error) }
        onDisconnect?(error)
    }
    func close() {
        receiver?.cancel(); receiver = nil; pointerChannel.close(); socket?.cancel(with: .goingAway, reason: nil)
        socket = nil; subscriptions.removeAll(); session.invalidateAndCancel()
        let pending = waiters; waiters.removeAll(); pending.values.forEach { $0.resume(throwing: CancellationError()) }
    }
    private func exchange(_ object: [String: Any], timeout: UInt64 = 12) async throws -> [String: Any] {
        guard let ws = socket, let id = object["id"] as? String else { throw RemoteError.message("Conecte-se à TV primeiro.") }
        let data = try JSONSerialization.data(withJSONObject: object), message = String(decoding: data, as: UTF8.self)
        return try await withCheckedThrowingContinuation { continuation in
            waiters[id] = continuation
            Task { [weak self] in
                do { try await ws.send(.string(message)) }
                catch { self?.waiters.removeValue(forKey: id)?.resume(throwing: error) }
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeout * 1_000_000_000)
                self?.waiters.removeValue(forKey: id)?.resume(throwing: RemoteError.message(id == "register" ? "O pareamento expirou. Aceite a conexão na TV e tente de novo." : "A TV demorou demais para responder."))
            }
        }
    }
    func request(_ uri: String, _ payload: [String: Any] = [:]) async throws -> [String: Any] {
        // Record the operation name only; never record text input or pairing keys.
        let method = uri.split(separator: "/").last.map(String.init) ?? ""
        onEvent?(method.hasPrefix("get") || method.hasPrefix("list") ? "Leitura" : "Comando", uri)
        return try await exchange(["type": "request", "id": UUID().uuidString, "uri": "ssap://" + uri, "payload": payload])
    }
    func subscribe(_ uri: String, callback: @escaping ([String: Any]) -> Void) async throws {
        let id = UUID().uuidString; subscriptions[id] = callback
        do { _ = try await exchange(["type": "subscribe", "id": id, "uri": "ssap://" + uri]) }
        catch { subscriptions.removeValue(forKey: id); throw error }
    }
    private var inputChannel: PointerChannel {
        pointerChannel.onState = { [weak self] in self?.onPointerState?($0) }
        return pointerChannel
    }
    func button(_ name: String) async throws { try await inputChannel.send(PointerMessage.button(name)) }
    func move(dx: Int, dy: Int) async throws { try await inputChannel.send(PointerMessage.move(dx: min(80, max(-80, dx)), dy: min(80, max(-80, dy)))) }
    func click() async throws { try await inputChannel.send(PointerMessage.click) }
    func checkPointer() async throws { try await inputChannel.check() }
}

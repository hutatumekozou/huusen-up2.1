import Foundation
import Network

final class WebAdminServer {
    private let settings: OverlaySettings
    private let preferredPort: UInt16
    private var port: NWEndpoint.Port
    private let showNow: () -> Void
    private let showCodexCompletion: (String, String, String, Bool) -> Void
    private let settingsChanged: () -> Void
    private let pauseChanged: () -> Void
    private let queue = DispatchQueue(label: "BalloonOverlayApp.WebAdminServer")
    private var listener: NWListener?

    var adminURL: URL {
        URL(string: "http://localhost:\(port.rawValue)/")!
    }

    init(
        settings: OverlaySettings,
        port: UInt16 = 8765,
        showNow: @escaping () -> Void,
        showCodexCompletion: @escaping (String, String, String, Bool) -> Void,
        settingsChanged: @escaping () -> Void,
        pauseChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.preferredPort = port
        self.port = NWEndpoint.Port(rawValue: port)!
        self.showNow = showNow
        self.showCodexCompletion = showCodexCompletion
        self.settingsChanged = settingsChanged
        self.pauseChanged = pauseChanged
    }

    func start() {
        stop()
        start(onCandidateAt: 0)
    }

    private func start(onCandidateAt index: Int) {
        let candidates = portCandidates
        guard index < candidates.count else {
            NSLog("Web admin server failed to start on any port from \(preferredPort) to \(preferredPort + 34)")
            return
        }

        let portValue = candidates[index]
        guard let candidatePort = NWEndpoint.Port(rawValue: portValue) else {
            start(onCandidateAt: index + 1)
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: candidatePort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                switch state {
                case .ready:
                    NSLog("Web admin server started on port \(portValue)")
                case let .failed(error):
                    NSLog("Web admin server failed on port \(portValue): \(error)")
                    self?.queue.async { [weak self, weak listener] in
                        guard let self, let listener, self.listener === listener else { return }
                        listener.cancel()
                        self.listener = nil
                        self.start(onCandidateAt: index + 1)
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }
            port = candidatePort
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            NSLog("Web admin server could not use port \(portValue): \(error)")
            start(onCandidateAt: index + 1)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequestData(from: connection, buffer: Data())
    }

    private var portCandidates: [UInt16] {
        let fallbackPorts = (preferredPort...(preferredPort + 34)).filter { $0 != preferredPort }
        return [preferredPort] + fallbackPorts
    }

    private func receiveRequestData(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 24_000_000) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            guard !nextBuffer.isEmpty else {
                connection.cancel()
                return
            }

            if isComplete && !self.isCompleteRequest(nextBuffer) {
                connection.cancel()
                return
            }

            guard self.isCompleteRequest(nextBuffer) else {
                self.receiveRequestData(from: connection, buffer: nextBuffer)
                return
            }

            let request = String(data: nextBuffer, encoding: .utf8) ?? ""
            let response = self.response(for: request)
            connection.send(content: response, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func isCompleteRequest(_ data: Data) -> Bool {
        guard let request = String(data: data, encoding: .utf8) else {
            return true
        }

        guard let headerRange = request.range(of: "\r\n\r\n") else {
            return false
        }

        let headerText = String(request[..<headerRange.lowerBound])
        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts[0].lowercased() == "content-length" else {
                    return nil
                }
                return Int(parts[1])
            }
            .first ?? 0
        let headerByteCount = Data(request[..<headerRange.upperBound].utf8).count
        return data.count >= headerByteCount + contentLength
    }

    private func response(for request: String) -> Data {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync {
                self.response(for: request)
            }
        }

        let path = requestPath(from: request)

        switch path.path {
        case "/":
            return httpResponse(
                status: "200 OK",
                body: renderPage(
                    message: path.query["message"],
                    tab: path.query["tab"],
                    editID: path.query["edit"],
                    editGenreName: path.query["editGenreName"],
                    editMiddleCategoryGenreName: path.query["editMiddleCategoryGenreName"],
                    editMiddleCategoryName: path.query["editMiddleCategoryName"],
                    editSmallCategoryGenreName: path.query["editSmallCategoryGenreName"],
                    editSmallCategoryMiddleCategoryName: path.query["editSmallCategoryMiddleCategoryName"],
                    editSmallCategoryName: path.query["editSmallCategoryName"],
                    itemNumberSearch: path.query["itemNumberSearch"],
                    listSort: path.query["listSort"],
                    listGenreFilter: path.query["listGenreFilter"],
                    listMiddleCategoryFilter: path.query["listMiddleCategoryFilter"],
                    listSmallCategoryFilter: path.query["listSmallCategoryFilter"],
                    listFavoriteFilter: path.query["listFavoriteFilter"],
                    returnTo: path.query["returnTo"],
                    returnScrollY: path.query["returnScrollY"]
                )
            )
        case "/show":
            if let id = path.query["id"].flatMap(UUID.init(uuidString:)) {
                DispatchQueue.main.async {
                    if self.settings.presentBalloonOnce(id: id) {
                        self.showNow()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.settings.activateNextEnabledBalloon()
                    self.showNow()
                }
            }
            return redirect(to: showRedirectPath(from: path.query))
        case "/codex-complete":
            let title = path.query["title"] ?? "Codex作業完了"
            let message = path.query["message"] ?? "作業が完了しました"
            let details = path.query["details"] ?? path.query["detail"] ?? ""
            let status = (path.query["status"] ?? "success").lowercased()
            let isSuccess = !["fail", "failed", "failure", "error", "warning"].contains(status)
            DispatchQueue.main.async {
                self.showCodexCompletion(title, message, details, isSuccess)
            }
            return httpResponse(
                status: "200 OK",
                body: "{\"ok\":true,\"shown\":true}\n",
                contentType: "application/json; charset=utf-8"
            )
        case "/delete":
            if let id = path.query["id"].flatMap(UUID.init(uuidString:)) {
                DispatchQueue.main.async {
                    self.settings.deleteBalloon(id: id)
                    self.settingsChanged()
                }
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: "deleted"))
        case "/toggle-balloon":
            if let id = path.query["id"].flatMap(UUID.init(uuidString:)) {
                let isEnabled = path.query["enabled"] == "1"
                DispatchQueue.main.async {
                    self.settings.setBalloonEnabled(id: id, isEnabled: isEnabled)
                    self.settingsChanged()
                }
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: "updated"))
        case "/toggle-favorite":
            if let id = path.query["id"].flatMap(UUID.init(uuidString:)) {
                let isFavorite = path.query["favorite"] == "1"
                DispatchQueue.main.async {
                    self.settings.setBalloonFavorite(id: id, isFavorite: isFavorite)
                    self.settingsChanged()
                }
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: "updated"))
        case "/toggle-all-balloons":
            let isEnabled = path.query["enabled"] == "1"
            DispatchQueue.main.async {
                if isEnabled {
                    if self.settings.canRestoreAllStopState {
                        self.settings.restoreAllStopState()
                    } else {
                        self.settings.setAllBalloonsEnabled(true)
                    }
                } else {
                    self.settings.setAllBalloonsEnabled(false)
                }
                self.settingsChanged()
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: isEnabled ? "allRestored" : "allStopped"))
        case "/resume-all-balloons":
            DispatchQueue.main.async {
                let wasPaused = self.settings.isPaused
                self.settings.setAllBalloonsEnabled(true)
                self.settings.setPaused(false)
                if wasPaused {
                    self.pauseChanged()
                } else {
                    self.settingsChanged()
                }
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: "allResumed"))
        case "/toggle-genre-balloons":
            if let genreName = path.query["genre"] {
                let isEnabled = path.query["enabled"] == "1"
                DispatchQueue.main.async {
                    self.settings.setBalloonsEnabled(inGenre: genreName, isEnabled: isEnabled)
                    self.settingsChanged()
                }
                return redirect(to: listActionRedirectPath(from: path.query, message: isEnabled ? "genreRestored" : "genreStopped"))
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: "updated"))
        case "/resume-genre-balloons":
            if let genreName = path.query["genre"] {
                DispatchQueue.main.async {
                    let wasPaused = self.settings.isPaused
                    self.settings.setBalloonsEnabled(inGenre: genreName, isEnabled: true)
                    self.settings.setPaused(false)
                    if wasPaused {
                        self.pauseChanged()
                    } else {
                        self.settingsChanged()
                    }
                }
                return redirect(to: listActionRedirectPath(from: path.query, message: "genreResumed"))
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: "updated"))
        case "/toggle-middle-category-balloons":
            if let genreName = path.query["genre"], let middleCategoryName = path.query["middleCategory"] {
                let isEnabled = path.query["enabled"] == "1"
                DispatchQueue.main.async {
                    self.settings.setBalloonsEnabled(inGenre: genreName, middleCategoryName: middleCategoryName, isEnabled: isEnabled)
                    self.settingsChanged()
                }
                return redirect(to: listActionRedirectPath(from: path.query, message: isEnabled ? "middleCategoryRestored" : "middleCategoryStopped"))
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: "updated"))
        case "/resume-middle-category-balloons":
            if let genreName = path.query["genre"], let middleCategoryName = path.query["middleCategory"] {
                DispatchQueue.main.async {
                    let wasPaused = self.settings.isPaused
                    self.settings.setBalloonsEnabled(inGenre: genreName, middleCategoryName: middleCategoryName, isEnabled: true)
                    self.settings.setPaused(false)
                    if wasPaused {
                        self.pauseChanged()
                    } else {
                        self.settingsChanged()
                    }
                }
                return redirect(to: listActionRedirectPath(from: path.query, message: "middleCategoryResumed"))
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: "updated"))
        case "/toggle-small-category-balloons":
            if let genreName = path.query["genre"],
               let middleCategoryName = path.query["middleCategory"],
               let smallCategoryName = path.query["smallCategory"] {
                let isEnabled = path.query["enabled"] == "1"
                DispatchQueue.main.async {
                    self.settings.setBalloonsEnabled(inGenre: genreName, middleCategoryName: middleCategoryName, smallCategoryName: smallCategoryName, isEnabled: isEnabled)
                    self.settingsChanged()
                }
                return redirect(to: listActionRedirectPath(from: path.query, message: isEnabled ? "smallCategoryRestored" : "smallCategoryStopped"))
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: "updated"))
        case "/resume-small-category-balloons":
            if let genreName = path.query["genre"],
               let middleCategoryName = path.query["middleCategory"],
               let smallCategoryName = path.query["smallCategory"] {
                DispatchQueue.main.async {
                    let wasPaused = self.settings.isPaused
                    self.settings.setBalloonsEnabled(inGenre: genreName, middleCategoryName: middleCategoryName, smallCategoryName: smallCategoryName, isEnabled: true)
                    self.settings.setPaused(false)
                    if wasPaused {
                        self.pauseChanged()
                    } else {
                        self.settingsChanged()
                    }
                }
                return redirect(to: listActionRedirectPath(from: path.query, message: "smallCategoryResumed"))
            }
            return redirect(to: listActionRedirectPath(from: path.query, message: "updated"))
        case "/set-launch-position":
            let positionName = path.query["launchPositionName"] ?? ""
            let climbSpeed = path.query.doubleValue(for: "climbSpeed", fallback: settings.climbSpeed)
            let selectedTab = path.query["tab"] ?? "create"
            DispatchQueue.main.async {
                self.settings.updateLaunchSettings(positionName: positionName, climbSpeed: climbSpeed)
                self.settingsChanged()
            }
            return redirect(to: "/?tab=\(selectedTab.urlQueryEscaped)&message=launchPositionUpdated")
        case "/edit-genre":
            let genreName = path.query["manageGenreName"] ?? ""
            return redirect(to: "/?tab=create&editGenreName=\(genreName.urlQueryEscaped)#category-editor")
        case "/rename-genre":
            let genreName = path.query["targetGenreName"] ?? path.query["manageGenreName"] ?? ""
            let newGenreName = path.query["renamedGenreName"] ?? ""
            DispatchQueue.main.async {
                self.settings.renameGenre(from: genreName, to: newGenreName)
                self.settingsChanged()
            }
            return redirect(to: "/?tab=create&message=categoryUpdated")
        case "/delete-genre":
            let genreName = path.query["manageGenreName"] ?? ""
            DispatchQueue.main.async {
                self.settings.deleteGenre(named: genreName)
                self.settingsChanged()
            }
            return redirect(to: "/?tab=create&message=categoryDeleted")
        case "/edit-middle-category":
            let genreName = path.query["manageMiddleCategoryGenreName"] ?? ""
            let middleCategoryName = path.query["manageMiddleCategoryName"] ?? ""
            return redirect(to: "/?tab=create&editMiddleCategoryGenreName=\(genreName.urlQueryEscaped)&editMiddleCategoryName=\(middleCategoryName.urlQueryEscaped)#category-editor")
        case "/rename-middle-category":
            let genreName = path.query["targetMiddleCategoryGenreName"] ?? path.query["manageMiddleCategoryGenreName"] ?? ""
            let middleCategoryName = path.query["targetMiddleCategoryName"] ?? path.query["manageMiddleCategoryName"] ?? ""
            let newMiddleCategoryName = path.query["renamedMiddleCategoryName"] ?? ""
            DispatchQueue.main.async {
                self.settings.renameMiddleCategory(inGenre: genreName, from: middleCategoryName, to: newMiddleCategoryName)
                self.settingsChanged()
            }
            return redirect(to: "/?tab=create&message=categoryUpdated")
        case "/delete-middle-category":
            let genreName = path.query["manageMiddleCategoryGenreName"] ?? ""
            let middleCategoryName = path.query["manageMiddleCategoryName"] ?? ""
            DispatchQueue.main.async {
                self.settings.deleteMiddleCategory(inGenre: genreName, named: middleCategoryName)
                self.settingsChanged()
            }
            return redirect(to: "/?tab=create&message=categoryDeleted")
        case "/edit-small-category":
            let genreName = path.query["manageSmallCategoryGenreName"] ?? ""
            let middleCategoryName = path.query["manageSmallCategoryMiddleCategoryName"] ?? ""
            let smallCategoryName = path.query["manageSmallCategoryName"] ?? ""
            return redirect(to: "/?tab=create&editSmallCategoryGenreName=\(genreName.urlQueryEscaped)&editSmallCategoryMiddleCategoryName=\(middleCategoryName.urlQueryEscaped)&editSmallCategoryName=\(smallCategoryName.urlQueryEscaped)#category-editor")
        case "/rename-small-category":
            let genreName = path.query["targetSmallCategoryGenreName"] ?? path.query["manageSmallCategoryGenreName"] ?? ""
            let middleCategoryName = path.query["targetSmallCategoryMiddleCategoryName"] ?? path.query["manageSmallCategoryMiddleCategoryName"] ?? ""
            let smallCategoryName = path.query["targetSmallCategoryName"] ?? path.query["manageSmallCategoryName"] ?? ""
            let newSmallCategoryName = path.query["renamedSmallCategoryName"] ?? ""
            DispatchQueue.main.async {
                self.settings.renameSmallCategory(inGenre: genreName, middleCategoryName: middleCategoryName, from: smallCategoryName, to: newSmallCategoryName)
                self.settingsChanged()
            }
            return redirect(to: "/?tab=create&message=categoryUpdated")
        case "/delete-small-category":
            let genreName = path.query["manageSmallCategoryGenreName"] ?? ""
            let middleCategoryName = path.query["manageSmallCategoryMiddleCategoryName"] ?? ""
            let smallCategoryName = path.query["manageSmallCategoryName"] ?? ""
            DispatchQueue.main.async {
                self.settings.deleteSmallCategory(inGenre: genreName, middleCategoryName: middleCategoryName, named: smallCategoryName)
                self.settingsChanged()
            }
            return redirect(to: "/?tab=create&message=categoryDeleted")
        case "/pause":
            DispatchQueue.main.async {
                self.settings.setPaused(true)
                self.pauseChanged()
            }
            return redirect(to: "/?tab=\(path.query["tab"] ?? "create")&message=paused")
        case "/resume":
            DispatchQueue.main.async {
                self.settings.setPaused(false)
                self.pauseChanged()
            }
            return redirect(to: "/?tab=\(path.query["tab"] ?? "create")&message=resumed")
        case "/test-balloon":
            let query = path.query
            DispatchQueue.main.async {
                self.settings.presentTemporaryBalloon(self.temporaryBalloon(from: query))
                self.showNow()
            }
            return httpResponse(
                status: "200 OK",
                body: "{\"ok\":true,\"shown\":true}\n",
                contentType: "application/json; charset=utf-8"
            )
        case "/save":
            let query = path.query
            DispatchQueue.main.async {
                let imageDataURL = query["removeImageData"] == "on" ? "" : query["imageDataURL"]
                let backImageDataURL = query["removeBackImageData"] == "on" ? "" : query["backImageDataURL"]
                let explanationImageDataURLs = (1...8).map { index in
                    query["removeExplanationImageData\(index)"] == "on" ? "" : (query["explanationImageDataURL\(index)"] ?? "")
                }
                let newGenreName = (query["newGenreName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let genreName = newGenreName.isEmpty ? (query["selectedGenreName"] ?? "") : newGenreName
                let newMiddleCategoryName = (query["newMiddleCategoryName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let middleCategoryName = newMiddleCategoryName.isEmpty ? (query["selectedMiddleCategoryName"] ?? "") : newMiddleCategoryName
                let newSmallCategoryName = (query["newSmallCategoryName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let smallCategoryName = newSmallCategoryName.isEmpty ? (query["selectedSmallCategoryName"] ?? "") : newSmallCategoryName
                let title = query["title"] ?? ""
                let frontText = query["text"] ?? ""
                self.settings.updateGlobalSettings(
                    intervalMinutes: query.doubleValue(for: "intervalMinutes", fallback: self.settings.displayInterval / 60),
                    randomIntervalMinSeconds: query.doubleValue(for: "randomIntervalMinSeconds", fallback: self.settings.randomIntervalMinSeconds),
                    randomIntervalMaxSeconds: query.doubleValue(for: "randomIntervalMaxSeconds", fallback: self.settings.randomIntervalMaxSeconds),
                    climbSpeed: query.doubleValue(for: "climbSpeed", fallback: self.settings.climbSpeed)
                )

                if let id = query["id"].flatMap(UUID.init(uuidString:)) {
                    self.settings.updateBalloon(
                        id: id,
                        title: title,
                        text: frontText,
                        explanationText: query["explanationText"] ?? "",
                        explanationImageDataURLs: explanationImageDataURLs,
                        imageName: nil,
                        imageDataURL: imageDataURL,
                        backText: query["backText"] ?? "",
                        backImageName: nil,
                        backImageDataURL: backImageDataURL,
                        textFontSize: query.doubleValue(for: "textFontSize", fallback: 0),
                        imageCaptionFontSize: 0,
                        imageScale: query.doubleValue(for: "imageScale", fallback: 1.0),
                        textOffsetX: query.doubleValue(for: "textOffsetX", fallback: 0),
                        textOffsetY: query.doubleValue(for: "textOffsetY", fallback: 0),
                        imageCaptionOffsetX: query.doubleValue(for: "imageCaptionOffsetX", fallback: 0),
                        imageCaptionOffsetY: query.doubleValue(for: "imageCaptionOffsetY", fallback: 0),
                        genreName: genreName,
                        middleCategoryName: middleCategoryName,
                        smallCategoryName: smallCategoryName,
                        colorName: query["colorName"] ?? OverlaySettings.colorOptions[0].name,
                        customBalloonDesignDataURL: query["customBalloonDesignDataURL"],
                        customBalloonDesignScale: query.doubleValue(for: "customBalloonDesignScale", fallback: 1.0),
                        positionName: query["positionName"] ?? "ランダム",
                        sizeName: query["sizeName"] ?? "標準",
                        pausesAtMiddle: query["pausesAtMiddle"] == "on",
                        middlePauseDuration: query.doubleValue(for: "middlePauseDuration", fallback: 15.0)
                    )
                } else {
                    self.settings.addBalloon(
                        title: title,
                        text: frontText,
                        explanationText: query["explanationText"] ?? "",
                        explanationImageDataURLs: explanationImageDataURLs,
                        imageName: nil,
                        imageDataURL: imageDataURL,
                        backText: query["backText"] ?? "",
                        backImageName: nil,
                        backImageDataURL: backImageDataURL,
                        textFontSize: query.doubleValue(for: "textFontSize", fallback: 0),
                        imageCaptionFontSize: 0,
                        imageScale: query.doubleValue(for: "imageScale", fallback: 1.0),
                        textOffsetX: query.doubleValue(for: "textOffsetX", fallback: 0),
                        textOffsetY: query.doubleValue(for: "textOffsetY", fallback: 0),
                        imageCaptionOffsetX: query.doubleValue(for: "imageCaptionOffsetX", fallback: 0),
                        imageCaptionOffsetY: query.doubleValue(for: "imageCaptionOffsetY", fallback: 0),
                        genreName: genreName,
                        middleCategoryName: middleCategoryName,
                        smallCategoryName: smallCategoryName,
                        colorName: query["colorName"] ?? OverlaySettings.colorOptions[0].name,
                        customBalloonDesignDataURL: query["customBalloonDesignDataURL"],
                        customBalloonDesignScale: query.doubleValue(for: "customBalloonDesignScale", fallback: 1.0),
                        positionName: query["positionName"] ?? "ランダム",
                        sizeName: query["sizeName"] ?? "標準",
                        pausesAtMiddle: query["pausesAtMiddle"] == "on",
                        middlePauseDuration: query.doubleValue(for: "middlePauseDuration", fallback: 15.0)
                    )
                }
                self.settingsChanged()
            }
            return redirect(to: saveRedirectPath(from: query))
        default:
            return httpResponse(status: "404 Not Found", body: "Not Found")
        }
    }

    private func saveRedirectPath(from query: [String: String]) -> String {
        guard query["id"].flatMap(UUID.init(uuidString:)) != nil,
              let returnTo = query["returnTo"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              returnTo.hasPrefix("/") else {
            return "/?tab=list&message=saved"
        }

        return appendingQueryItems(
            to: sanitizedReturnPath(returnTo),
            items: [
                URLQueryItem(name: "message", value: "saved"),
                URLQueryItem(name: "restoreScrollY", value: query["returnScrollY"] ?? "0")
            ]
        )
    }

    private func showRedirectPath(from query: [String: String]) -> String {
        guard let returnTo = query["returnTo"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              returnTo.hasPrefix("/") else {
            return "/?tab=list&message=shown"
        }

        return appendingQueryItems(
            to: sanitizedReturnPath(returnTo),
            items: [
                URLQueryItem(name: "message", value: "shown"),
                URLQueryItem(name: "restoreScrollY", value: query["returnScrollY"] ?? "0")
            ]
        )
    }

    private func listActionRedirectPath(from query: [String: String], message: String) -> String {
        guard let returnTo = query["returnTo"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              returnTo.hasPrefix("/") else {
            return appendingQueryItems(
                to: "/",
                items: [
                    URLQueryItem(name: "tab", value: "list"),
                    URLQueryItem(name: "message", value: message)
                ]
            )
        }

        var items = [URLQueryItem(name: "message", value: message)]
        if let returnScrollY = query["returnScrollY"] {
            items.append(URLQueryItem(name: "restoreScrollY", value: returnScrollY))
        }
        return appendingQueryItems(to: sanitizedReturnPath(returnTo), items: items)
    }

    private func temporaryBalloon(from query: [String: String]) -> BalloonProfile {
        let imageDataURL = query["removeImageData"] == "on" ? "" : query["imageDataURL"]
        let backImageDataURL = query["removeBackImageData"] == "on" ? "" : query["backImageDataURL"]
        let explanationImageDataURLs = (1...8).map { index in
            query["removeExplanationImageData\(index)"] == "on" ? "" : (query["explanationImageDataURL\(index)"] ?? "")
        }
        let newGenreName = (query["newGenreName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let genreName = newGenreName.isEmpty ? (query["selectedGenreName"] ?? "") : newGenreName
        let newMiddleCategoryName = (query["newMiddleCategoryName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let middleCategoryName = newMiddleCategoryName.isEmpty ? (query["selectedMiddleCategoryName"] ?? "") : newMiddleCategoryName
        let newSmallCategoryName = (query["newSmallCategoryName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let smallCategoryName = newSmallCategoryName.isEmpty ? (query["selectedSmallCategoryName"] ?? "") : newSmallCategoryName
        let colorName = query["colorName"] ?? OverlaySettings.colorOptions[0].name
        let color = OverlaySettings.colorOptions.first(where: { $0.name == colorName }) ?? OverlaySettings.colorOptions[0]
        let hasCustomBalloonDesign = colorName == OverlaySettings.customBalloonDesignName
            && (query["customBalloonDesignDataURL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
        let title = (query["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "作成中の風船テスト"
        let text = (query["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFrontImage = imageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil

        return BalloonProfile(
            id: UUID(),
            itemNumber: query["id"].flatMap(UUID.init(uuidString:)).flatMap { id in
                settings.balloons.first(where: { $0.id == id })?.itemNumber
            } ?? 0,
            title: title,
            text: text.isEmpty && !hasFrontImage ? "🎈" : text,
            explanationText: query["explanationText"] ?? "",
            explanationImageDataURLs: explanationImageDataURLs,
            imageName: nil,
            imageDataURL: imageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            backText: query["backText"] ?? "",
            backImageName: nil,
            backImageDataURL: backImageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            textFontSize: clampedFontSize(query.doubleValue(for: "textFontSize", fallback: 0)),
            imageCaptionFontSize: 0,
            imageScale: clampedImageScale(query.doubleValue(for: "imageScale", fallback: 1.0)),
            textOffsetX: clampedPositionOffset(query.doubleValue(for: "textOffsetX", fallback: 0)),
            textOffsetY: clampedPositionOffset(query.doubleValue(for: "textOffsetY", fallback: 0)),
            imageCaptionOffsetX: clampedPositionOffset(query.doubleValue(for: "imageCaptionOffsetX", fallback: 0)),
            imageCaptionOffsetY: clampedPositionOffset(query.doubleValue(for: "imageCaptionOffsetY", fallback: 0)),
            genreName: genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "作成テスト",
            middleCategoryName: middleCategoryName,
            smallCategoryName: smallCategoryName,
            colorName: hasCustomBalloonDesign ? OverlaySettings.customBalloonDesignName : color.name,
            colorStartHex: color.startHex,
            colorEndHex: color.endHex,
            customBalloonDesignDataURL: query["customBalloonDesignDataURL"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            customBalloonDesignScale: clampedCustomBalloonDesignScale(query.doubleValue(for: "customBalloonDesignScale", fallback: 1.0)),
            positionName: "中央",
            sizeName: query["sizeName"] ?? "標準",
            pausesAtMiddle: true,
            middlePauseDuration: 999,
            isEnabled: true,
            isFavorite: false,
            correctCount: 0,
            incorrectCount: 0,
            lastReviewedAt: nil,
            createdAt: Date()
        )
    }

    private func clampedFontSize(_ value: Double) -> Double {
        value <= 0 ? 0 : min(max(value, 4), 90)
    }

    private func clampedImageScale(_ value: Double) -> Double {
        min(max(value, 0.6), 2.0)
    }

    private func clampedPositionOffset(_ value: Double) -> Double {
        min(max(value, -0.45), 0.45)
    }

    private func clampedCustomBalloonDesignScale(_ value: Double) -> Double {
        min(max(value, 0.5), 2.5)
    }

    private func sanitizedReturnPath(_ path: String) -> String {
        let parts = splitPathAndQuery(path)
        var components = URLComponents()
        components.percentEncodedPath = parts.path
        if let query = parts.query {
            components.percentEncodedQuery = query
        }
        let transientQueryNames: Set<String> = ["returnTo", "returnScrollY", "restoreScrollY"]
        components.queryItems = (components.queryItems ?? []).filter { !transientQueryNames.contains($0.name) }
        return components.string ?? path
    }

    private func appendingQueryItems(to path: String, items: [URLQueryItem]) -> String {
        let parts = splitPathAndQuery(path)
        var components = URLComponents()
        components.percentEncodedPath = parts.path
        if let query = parts.query {
            components.percentEncodedQuery = query
        }

        var queryItems = (components.queryItems ?? []).filter { existingItem in
            !items.contains(where: { $0.name == existingItem.name })
        }
        queryItems.append(contentsOf: items)
        components.queryItems = queryItems
        return components.string ?? path
    }

    private func requestPath(from request: String) -> (path: String, query: [String: String]) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            return ("/", [:])
        }

        let method = String(parts[0])
        let rawPath = String(parts[1])
        let pathParts = splitPathAndQuery(rawPath)
        var components = URLComponents()
        components.percentEncodedPath = pathParts.path
        if let query = pathParts.query {
            components.percentEncodedQuery = query
        }

        var query: [String: String] = [:]
        (components.queryItems ?? []).forEach { item in
            query[item.name] = item.value ?? ""
        }
        if method == "POST", let body = request.components(separatedBy: "\r\n\r\n").dropFirst().first {
            parseURLEncodedForm(body).forEach { key, value in
                query[key] = value
            }
        }
        return (components.path.isEmpty ? "/" : components.path, query)
    }

    private func splitPathAndQuery(_ path: String) -> (path: String, query: String?) {
        guard let questionMarkIndex = path.firstIndex(of: "?") else {
            return (path.isEmpty ? "/" : path, nil)
        }

        let pathPart = String(path[..<questionMarkIndex])
        let queryStart = path.index(after: questionMarkIndex)
        return (pathPart.isEmpty ? "/" : pathPart, String(path[queryStart...]))
    }

    private func parseURLEncodedForm(_ body: String) -> [String: String] {
        var values: [String: String] = [:]

        body.split(separator: "&", omittingEmptySubsequences: false).forEach { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first else { return }

            let key = formValue(from: String(name))
            let value = parts.count > 1 ? formValue(from: String(parts[1])) : ""
            values[key] = value
        }

        return values
    }

    private func formValue(from value: String) -> String {
        value
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? value
    }

    private func redirect(to path: String) -> Data {
        let headers = [
            "HTTP/1.1 303 See Other",
            "Location: \(path)",
            "Content-Length: 0",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(headers.utf8)
    }

    private func httpResponse(status: String, body: String, contentType: String = "text/html; charset=utf-8") -> Data {
        let bodyData = Data(body.utf8)
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var data = Data(headers.utf8)
        data.append(bodyData)
        return data
    }

    private func renderPage(
        message: String?,
        tab: String?,
        editID: String?,
        editGenreName: String?,
        editMiddleCategoryGenreName: String?,
        editMiddleCategoryName: String?,
        editSmallCategoryGenreName: String?,
        editSmallCategoryMiddleCategoryName: String?,
        editSmallCategoryName: String?,
        itemNumberSearch: String?,
        listSort: String?,
        listGenreFilter: String?,
        listMiddleCategoryFilter: String?,
        listSmallCategoryFilter: String?,
        listFavoriteFilter: String?,
        returnTo: String?,
        returnScrollY: String?
    ) -> String {
        let intervalMinutes = String(format: "%.1f", settings.displayInterval / 60)
        let randomIntervalMinSeconds = String(format: "%.0f", settings.randomIntervalMinSeconds)
        let randomIntervalMaxSeconds = String(format: "%.0f", settings.randomIntervalMaxSeconds)
        let climbSpeed = String(format: "%.0f", settings.climbSpeed)
        let activeBalloon = settings.activeBalloon
        let editingID = editID.flatMap(UUID.init(uuidString:))
        let editingBalloon = editingID.flatMap { id in settings.balloons.first(where: { $0.id == id }) }
        let formBalloon = editingBalloon ?? activeBalloon
        let imageName = formBalloon.imageName ?? ""
        let imageDataURL = formBalloon.imageDataURL ?? ""
        let backImageName = formBalloon.backImageName ?? ""
        let backImageDataURL = formBalloon.backImageDataURL ?? ""
        let previewContent = renderPreviewContent(imageDataURL: imageDataURL, imageName: imageName, text: frontTextInputValue(for: formBalloon))
        let selectedTab = editingBalloon != nil ? "create" : (tab == "list" ? "list" : "create")
        let status = settings.isPaused ? "一時停止中" : "稼働中"
        let escapedMessage = message.map { "<p class=\"notice\">\(messageText(for: $0))</p>" } ?? ""
        let colorOptions = renderColorOptions(
            selectedName: formBalloon.colorName,
            customBalloonDesignDataURL: formBalloon.customBalloonDesignDataURL,
            customBalloonDesignScale: formBalloon.customBalloonDesignScale
        )
        let headerPositionOptions = renderSelectPositionOptions(selectedName: settings.launchPositionName)
        let positionOptions = renderPositionOptions(selectedName: formBalloon.positionName)
        let sizeOptions = renderSizeOptions(selectedName: formBalloon.sizeName)
        let createTabClass = selectedTab == "create" ? "tab active" : "tab"
        let listTabClass = selectedTab == "list" ? "tab active" : "tab"
        let tabContent = selectedTab == "list"
            ? renderListPanel(
                itemNumberSearch: itemNumberSearch,
                listSort: listSort,
                genreFilter: listGenreFilter,
                middleCategoryFilter: listMiddleCategoryFilter,
                smallCategoryFilter: listSmallCategoryFilter,
                favoriteFilter: listFavoriteFilter
            )
            : renderCreatePanel(
                intervalMinutes: intervalMinutes,
                randomIntervalMinSeconds: randomIntervalMinSeconds,
                randomIntervalMaxSeconds: randomIntervalMaxSeconds,
                climbSpeed: climbSpeed,
                activeBalloon: formBalloon,
                editingID: editingBalloon?.id,
                imageName: imageName,
                imageDataURL: imageDataURL,
                backImageName: backImageName,
                backImageDataURL: backImageDataURL,
                previewContent: previewContent,
                colorOptions: colorOptions,
                positionOptions: positionOptions,
                sizeOptions: sizeOptions,
                editGenreName: editGenreName,
                editMiddleCategoryGenreName: editMiddleCategoryGenreName,
                editMiddleCategoryName: editMiddleCategoryName,
                editSmallCategoryGenreName: editSmallCategoryGenreName,
                editSmallCategoryMiddleCategoryName: editSmallCategoryMiddleCategoryName,
                editSmallCategoryName: editSmallCategoryName,
                returnTo: returnTo,
                returnScrollY: returnScrollY
            )

        return """
        <!doctype html>
        <html lang="ja">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Balloon Overlay 管理</title>
          <style>
            body {
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
              background: #f6f7f9;
              color: #1d1d1f;
            }
            main {
              max-width: 760px;
              margin: 0 auto;
              padding: 40px 20px;
            }
            header {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 20px;
              margin-bottom: 24px;
            }
            h1 {
              font-size: 28px;
              margin: 0 0 8px;
            }
            .status {
              font-size: 14px;
              color: #5f6368;
            }
            .panel {
              background: white;
              border: 1px solid #dddfe5;
              border-radius: 8px;
              padding: 22px;
              margin-bottom: 16px;
            }
            .panel-heading {
              display: flex;
              justify-content: space-between;
              align-items: center;
              gap: 16px;
            }
            .panel-heading h2 {
              margin: 0;
            }
            .panel form > .panel-heading {
              margin-bottom: 18px;
            }
            .heading-actions {
              display: flex;
              flex-wrap: wrap;
              gap: 10px;
              align-items: center;
              justify-content: flex-end;
              margin-left: auto;
            }
            .heading-meta {
              color: #5f6368;
              margin: 8px 0 0;
            }
            .tabs {
              display: flex;
              gap: 8px;
              border-bottom: 1px solid #dddfe5;
              margin: 0 0 18px;
            }
            .tab {
              display: inline-flex;
              align-items: center;
              height: 42px;
              padding: 0 14px;
              color: #5f6368;
              text-decoration: none;
              border-bottom: 3px solid transparent;
              font-weight: 700;
            }
            .tab.active {
              color: #1769e0;
              border-bottom-color: #1769e0;
            }
            .grid {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 16px;
            }
            .full {
              grid-column: 1 / -1;
            }
            .triple-row {
              grid-column: 1 / -1;
              display: grid;
              grid-template-columns: repeat(3, minmax(0, 1fr));
              gap: 16px;
            }
            .color-size-row {
              grid-column: 1 / -1;
              display: grid;
              grid-template-columns: minmax(0, 1fr) minmax(230px, 0.65fr);
              gap: 16px;
              align-items: start;
            }
            .top-field {
              margin-bottom: 18px;
            }
            .preview {
              width: 320px;
              max-width: 100%;
              display: inline-grid;
              gap: 8px;
              justify-items: center;
              align-items: start;
              margin-bottom: 22px;
            }
            .preview-balloon {
              --preview-size: 96px;
              --preview-content-size: calc(var(--preview-size) * 0.82);
              --preview-top-inset: calc(var(--preview-content-size) * 0.02);
              --preview-caption-height: calc(var(--preview-content-size) * 0.24);
              --preview-image-max-height: 82%;
              width: 96px;
              height: 120px;
              margin: 0 auto;
              position: relative;
            }
            .preview-balloon.large {
              --preview-size: 192px;
              width: 192px;
              height: 240px;
            }
            .preview-balloon.extra-large {
              --preview-size: 288px;
              width: 288px;
              height: 360px;
            }
            .preview-body {
              --preview-image-scale: \(formatImageScale(formBalloon.imageScale));
              --preview-text-offset-x: 0px;
              --preview-text-offset-y: 0px;
              --preview-image-offset-x: 0px;
              --preview-image-offset-y: 0px;
              --preview-color-start: \(formBalloon.colorStartHex);
              --preview-color-end: \(formBalloon.colorEndHex);
              width: var(--preview-size);
              height: var(--preview-size);
              display: flex;
              align-items: center;
              justify-content: center;
              position: relative;
              background: transparent;
              color: white;
              font-size: \(previewTextFontSize(for: formBalloon, large: false))px;
              font-weight: 700;
              overflow: visible;
              text-align: center;
              white-space: pre-wrap;
              line-height: 1.15;
            }
            .preview-body::before {
              content: "";
              position: absolute;
              inset: 0;
              z-index: 0;
              border-radius: 50%;
              background: linear-gradient(135deg, var(--preview-color-start), var(--preview-color-end));
              box-shadow: 0 8px 22px rgba(0, 0, 0, 0.16);
            }
            .preview-body::after {
              content: "";
              position: absolute;
              left: 21%;
              top: 18%;
              z-index: 0;
              width: 22%;
              height: 22%;
              border-radius: 50%;
              background: rgba(255, 255, 255, 0.35);
              pointer-events: none;
            }
            .preview-body.custom-balloon-design {
              background-color: transparent;
              overflow: visible;
            }
            .preview-body.custom-balloon-design::before {
              background-image: var(--custom-balloon-design-image);
              background-position: center;
              background-repeat: no-repeat;
              background-size: contain;
              transform: scale(var(--custom-balloon-design-scale, 1));
              transform-origin: center;
              pointer-events: none;
              box-shadow: none;
            }
            .preview-body.custom-balloon-design::after {
              display: none;
            }
            .preview-body.custom-balloon-design .preview-image-stack {
              position: relative;
              z-index: 1;
            }
            .preview-body.has-back {
              --preview-top-inset: calc(var(--preview-content-size) * 0.16);
            }
            .preview-content {
              position: relative;
              z-index: 2;
              transform: translate(var(--preview-text-offset-x, 0px), var(--preview-text-offset-y, 0px));
            }
            .preview-body > .preview-content {
              width: var(--preview-content-size);
              height: var(--preview-content-size);
              display: grid;
              place-items: center;
              box-sizing: border-box;
              padding: calc(var(--preview-size) * 0.03);
            }
            .preview-balloon.large .preview-body {
              width: var(--preview-size);
              height: var(--preview-size);
              font-size: \(previewTextFontSize(for: formBalloon))px;
            }
            .preview-balloon.extra-large .preview-body {
              width: var(--preview-size);
              height: var(--preview-size);
              font-size: \(previewTextFontSize(for: formBalloon))px;
            }
            .preview-image-stack {
              position: relative;
              isolation: isolate;
              display: grid;
              place-items: center;
              width: var(--preview-content-size);
              height: var(--preview-content-size);
              border-radius: 50%;
              overflow: hidden;
            }
            .preview-image-stack > img,
            .preview-image-stack > .preview-image-caption {
              grid-area: 1 / 1;
            }
            .preview-image-caption {
              position: relative;
              z-index: 10;
              display: flex;
              align-items: center;
              justify-content: center;
              align-self: start;
              justify-self: center;
              width: 88%;
              max-width: 88%;
              height: var(--preview-caption-height);
              color: white;
              font-size: \(previewImageCaptionFontSize(for: formBalloon, large: false))px;
              line-height: 1.1;
              text-align: center;
              overflow: visible;
              overflow-wrap: anywhere;
              white-space: pre-wrap;
              text-shadow: 0 1px 2px rgba(0, 0, 0, 0.35);
              pointer-events: none;
              transform: translate(var(--preview-text-offset-x, 0px), calc(var(--preview-top-inset) + var(--preview-text-offset-y, 0px)));
            }
            .preview-balloon.large .preview-image-caption {
              font-size: \(previewImageCaptionFontSize(for: formBalloon))px;
            }
            .preview-balloon.extra-large .preview-image-caption {
              font-size: \(previewImageCaptionFontSize(for: formBalloon))px;
            }
            .preview-body img {
              position: relative;
              z-index: 1;
              display: block;
              max-width: calc(82% * var(--preview-image-scale, 1));
              max-height: calc(var(--preview-image-max-height) * var(--preview-image-scale, 1));
              object-fit: contain;
              transform: translate(var(--preview-image-offset-x, 0px), calc(var(--preview-top-inset) + var(--preview-image-offset-y, 0px)));
            }
            .preview-image-stack.has-caption {
              --preview-image-max-height: 62%;
            }
            .preview-body.has-back .preview-image-stack.has-caption {
              --preview-caption-height: calc(var(--preview-content-size) * 0.20);
              --preview-image-max-height: 54%;
            }
            .preview-image-stack.has-caption.many-caption-lines {
              --preview-caption-height: calc(var(--preview-content-size) * 0.32);
              --preview-image-max-height: 48%;
            }
            .preview-badges {
              position: absolute;
              left: 50%;
              top: calc(var(--preview-size) * 0.12 - 10px);
              z-index: 12;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              gap: 6px;
              transform: translateX(-50%);
              pointer-events: none;
            }
            .preview-balloon.large .preview-badges {
              top: calc(var(--preview-size) * 0.12 - 16px);
              gap: 8px;
            }
            .preview-balloon.extra-large .preview-badges {
              top: calc(var(--preview-size) * 0.12 - 24px);
              gap: 10px;
            }
            .preview-badge {
              min-width: 44px;
              min-height: 20px;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              box-sizing: border-box;
              padding: 0 8px;
              border-radius: 999px;
              border: 1px solid rgba(0, 0, 0, 0.14);
              background: rgba(255, 255, 255, 0.92);
              color: rgba(0, 0, 0, 0.82);
              font-size: 10px;
              font-weight: 800;
              line-height: 1;
              box-shadow: 0 2px 6px rgba(0, 0, 0, 0.14);
              white-space: nowrap;
            }
            .preview-badge.dark {
              min-width: 32px;
              background: #111827;
              color: white;
              font-size: 14px;
              letter-spacing: 1px;
            }
            .preview-balloon.large .preview-badge {
              min-width: 70px;
              min-height: 32px;
              padding: 0 14px;
              font-size: 15px;
            }
            .preview-balloon.large .preview-badge.dark {
              min-width: 52px;
              font-size: 22px;
            }
            .preview-balloon.extra-large .preview-badge {
              min-width: 102px;
              min-height: 48px;
              padding: 0 20px;
              font-size: 22px;
            }
            .preview-balloon.extra-large .preview-badge.dark {
              min-width: 78px;
              font-size: 32px;
            }
            .preview-item-number {
              position: absolute;
              left: 50%;
              bottom: 12px;
              z-index: 13;
              min-width: 42px;
              min-height: 22px;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              box-sizing: border-box;
              padding: 0 10px;
              border-radius: 999px;
              border: 1px solid rgba(0, 0, 0, 0.12);
              background: rgba(255, 255, 255, 0.92);
              color: rgba(0, 0, 0, 0.78);
              font-size: 14px;
              font-weight: 800;
              transform: translateX(-50%);
              box-shadow: 0 2px 7px rgba(0, 0, 0, 0.14);
            }
            .preview-balloon.large .preview-item-number {
              bottom: 26px;
              min-width: 70px;
              min-height: 36px;
              font-size: 26px;
            }
            .preview-balloon.extra-large .preview-item-number {
              bottom: 44px;
              min-width: 104px;
              min-height: 54px;
              font-size: 38px;
            }
            .file-row {
              display: grid;
              gap: 8px;
            }
            .genre-fields {
              display: grid;
              gap: 10px;
            }
            .genre-fields span {
              display: grid;
              gap: 7px;
            }
            .category-action-block {
              padding: 12px;
              border: 1px solid #d9dde5;
              border-radius: 8px;
              background: #e9ecef;
            }
            .category-add-block {
              border-color: #b8bec8;
              background: #cbd1da;
              font-weight: 800;
            }
            .category-add-block input,
            .category-add-block select,
            .category-add-block button {
              font-weight: 400;
            }
            .genre-add-row {
              display: grid;
              grid-template-columns: minmax(0, 1fr) auto;
              gap: 8px;
              align-items: center;
            }
            .middle-category-add-row {
              display: grid;
              grid-template-columns: minmax(150px, 0.4fr) minmax(0, 1fr) auto;
              gap: 8px;
              align-items: center;
            }
            .small-category-add-row {
              display: grid;
              grid-template-columns: minmax(120px, 0.3fr) minmax(120px, 0.3fr) minmax(0, 1fr) auto;
              gap: 8px;
              align-items: center;
            }
            .genre-add-row button {
              height: 36px;
              padding: 0 14px;
              white-space: nowrap;
            }
            .middle-category-add-row button,
            .small-category-add-row button {
              height: 36px;
              padding: 0 14px;
              white-space: nowrap;
            }
            .category-manage-row {
              display: grid;
              grid-template-columns: minmax(0, 1fr) auto auto;
              gap: 8px;
              align-items: center;
            }
            .middle-category-manage-row {
              display: grid;
              grid-template-columns: minmax(130px, 0.35fr) minmax(130px, 0.35fr) auto auto;
              gap: 8px;
              align-items: center;
            }
            .small-category-manage-row {
              display: grid;
              grid-template-columns: minmax(110px, 0.25fr) minmax(110px, 0.25fr) minmax(110px, 0.25fr) auto auto;
              gap: 8px;
              align-items: center;
            }
            .category-manage-row button {
              height: 36px;
              padding: 0 14px;
              white-space: nowrap;
            }
            .middle-category-manage-row button,
            .small-category-manage-row button {
              height: 36px;
              padding: 0 14px;
              white-space: nowrap;
            }
            .category-edit-panel {
              display: grid;
              gap: 10px;
              padding: 12px;
              border: 1px solid #d9dde5;
              border-radius: 6px;
              background: #f7f9fc;
            }
            .category-edit-panel p {
              margin: 0;
              color: #5f6368;
              font-size: 13px;
            }
            .category-edit-actions {
              display: grid;
              grid-template-columns: minmax(0, 1fr) auto auto;
              gap: 8px;
              align-items: center;
            }
            .file-row input[type="file"] {
              height: auto;
              padding: 8px 10px;
            }
            .explanation-image-field {
              display: grid;
              gap: 10px;
            }
            .explanation-image-grid {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 10px;
            }
            .explanation-image-item {
              display: grid;
              gap: 8px;
              padding: 10px;
              border: 1px solid #d9dde5;
              border-radius: 6px;
              background: #f7f9fc;
            }
            .attachment-image-item.attached,
            .explanation-image-item.attached {
              border-color: #f4a8c8;
              background: #fff0f6;
            }
            .attachment-image-title,
            .explanation-image-title {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 8px;
              font-weight: 700;
            }
            .attachment-image-title-actions,
            .explanation-image-title-actions {
              display: inline-flex;
              align-items: center;
              gap: 8px;
              margin-left: auto;
            }
            .attachment-image-title small,
            .explanation-image-title small {
              color: #5f6368;
              font-weight: 600;
            }
            .attachment-image-item.attached small,
            .explanation-image-item.attached small {
              color: #c2185b;
            }
            .image-check-button {
              min-height: 28px;
              padding: 4px 10px;
              font-size: 12px;
              font-weight: 700;
            }
            .image-check-button[disabled] {
              color: #9aa0a6;
              background: #f3f4f6;
              cursor: default;
            }
            .image-remove-button {
              min-height: 36px;
              padding: 0 12px;
              white-space: nowrap;
            }
            .image-remove-button[disabled] {
              color: #9aa0a6;
              border-color: #d1d5db;
              background: #f3f4f6;
              cursor: default;
            }
            .explanation-image-item input[type="file"] {
              height: auto;
              padding: 8px 10px;
            }
            .file-control-row {
              display: grid;
              grid-template-columns: minmax(0, 1fr) auto;
              gap: 12px;
              align-items: center;
            }
            .grid-spacer {
              display: block;
            }
            .row-start {
              grid-column: 1;
            }
            .file-hint {
              color: #5f6368;
              font-size: 12px;
              margin: 0;
            }
            .clearline {
              display: flex;
              align-items: center;
              gap: 8px;
              color: #1d1d1f;
              font-size: 14px;
            }
            .clearline input {
              width: 18px;
              height: 18px;
              padding: 0;
            }
            .preview-knot {
              width: 0;
              height: 0;
              border-left: 9px solid transparent;
              border-right: 9px solid transparent;
              border-top: 15px solid \(formBalloon.colorEndHex);
              margin: -3px auto 0;
            }
            .preview-balloon.large .preview-knot {
              border-left-width: 18px;
              border-right-width: 18px;
              border-top-width: 30px;
              margin-top: -6px;
            }
            .preview-controls {
              display: flex;
              justify-content: center;
            }
            .preview-side-toggle {
              display: inline-flex;
              gap: 8px;
              margin: 0;
            }
            .preview-side-button {
              min-height: 34px;
              padding: 0 16px;
              border-radius: 999px;
            }
            .preview-side-button.active {
              background: #111;
              border-color: #111;
              color: #fff;
            }
            .preview-meta {
              color: #5f6368;
              margin: 0;
            }
            label {
              display: grid;
              gap: 7px;
              font-size: 13px;
              color: #3c4043;
            }
            .front-entry,
            .back-entry,
            .explanation-entry {
              padding: 12px;
              border-radius: 8px;
              border: 1px solid rgba(0, 0, 0, 0.06);
            }
            .front-entry {
              background: #fff0f5;
            }
            .back-entry {
              background: #eef8ff;
            }
            .explanation-entry {
              background: #f0fff4;
            }
            input, select, textarea {
              height: 36px;
              border: 1px solid #c7cbd1;
              border-radius: 6px;
              padding: 0 10px;
              font-size: 15px;
              background: #fff;
            }
            textarea {
              min-height: 96px;
              padding: 10px;
              resize: vertical;
              font-family: inherit;
              line-height: 1.5;
            }
            textarea.compact {
              min-height: 74px;
            }
            .font-controls {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 10px;
            }
            .font-controls.single {
              grid-template-columns: minmax(0, 1fr);
            }
            .position-controls {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 14px;
            }
            .font-control {
              display: grid;
              gap: 8px;
            }
            .position-control {
              display: grid;
              gap: 8px;
            }
            .font-control-head {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 8px;
              color: #3c4043;
              font-size: 13px;
            }
            .font-size-display {
              color: #5f6368;
              font-size: 12px;
              font-weight: 700;
            }
            .font-step-row {
              display: flex;
              align-items: center;
              gap: 10px;
            }
            .font-step {
              position: relative;
              width: 48px;
              height: 48px;
              padding: 0;
              border: 0;
              background: transparent;
            }
            .font-step::before {
              content: "";
              position: absolute;
              left: 4px;
              top: 4px;
              width: 31px;
              height: 31px;
              border: 5px solid #111;
              border-radius: 50%;
            }
            .font-step::after {
              content: "";
              position: absolute;
              left: 32px;
              top: 32px;
              width: 18px;
              height: 6px;
              border-radius: 999px;
              background: #111;
              transform: rotate(45deg);
              transform-origin: left center;
            }
            .font-step span {
              position: absolute;
              left: 10px;
              top: 8px;
              width: 22px;
              height: 22px;
              display: grid;
              place-items: center;
              color: #111;
              font-size: 31px;
              font-weight: 900;
              line-height: 1;
            }
            .font-auto {
              height: 34px;
              padding: 0 12px;
              font-size: 13px;
            }
            .position-pad {
              width: 156px;
              display: grid;
              grid-template-columns: repeat(3, 48px);
              grid-template-rows: repeat(3, 40px);
              gap: 4px;
              align-items: center;
              justify-items: center;
            }
            .position-step,
            .position-reset {
              width: 44px;
              height: 38px;
              display: grid;
              place-items: center;
              padding: 0;
              border-radius: 8px;
              font-weight: 800;
              line-height: 1;
            }
            .position-step {
              font-size: 20px;
            }
            .position-reset {
              width: 52px;
              font-size: 12px;
              line-height: 1.1;
            }
            .attachment-preview-modal {
              position: fixed;
              inset: 0;
              z-index: 1000;
              display: none;
              align-items: center;
              justify-content: center;
              padding: 24px;
              background: rgba(0, 0, 0, 0.62);
            }
            .attachment-preview-modal.open {
              display: flex;
            }
            .attachment-preview-panel {
              width: min(760px, 94vw);
              max-height: 90vh;
              display: grid;
              grid-template-rows: auto minmax(0, 1fr) auto;
              gap: 14px;
              padding: 18px;
              border-radius: 10px;
              background: #fff;
              box-shadow: 0 20px 50px rgba(0, 0, 0, 0.35);
            }
            .attachment-preview-head {
              display: flex;
              align-items: flex-start;
              justify-content: space-between;
              gap: 16px;
            }
            .attachment-preview-head h3 {
              margin: 0;
              font-size: 18px;
            }
            .attachment-preview-filename {
              margin: 6px 0 0;
              color: #5f6368;
              font-size: 13px;
              overflow-wrap: anywhere;
            }
            .attachment-preview-body {
              min-height: 220px;
              display: grid;
              place-items: center;
              overflow: hidden;
              border: 1px solid #d9dde5;
              border-radius: 8px;
              background: #f7f9fc;
            }
            .attachment-preview-body img {
              display: block;
              max-width: 100%;
              max-height: 62vh;
              object-fit: contain;
            }
            .attachment-preview-actions {
              display: flex;
              justify-content: flex-end;
            }
            .attachment-preview-close {
              min-width: 120px;
            }
            input[type="checkbox"] {
              width: 18px;
              height: 18px;
              padding: 0;
            }
            .checkline {
              min-height: 36px;
              display: flex;
              align-items: center;
              gap: 8px;
              color: #1d1d1f;
              font-size: 15px;
            }
            .swatches {
              display: grid;
              grid-template-columns: repeat(7, 42px);
              gap: 10px;
            }
            .swatch input {
              position: absolute;
              opacity: 0;
              pointer-events: none;
            }
            .swatch span {
              width: 34px;
              height: 34px;
              display: block;
              border-radius: 50%;
              border: 3px solid transparent;
              box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.18);
              cursor: pointer;
            }
            .swatch input:checked + span {
              border-color: #1769e0;
            }
            .custom-design-slot {
              position: relative;
              width: 42px;
              height: 42px;
              display: block;
            }
            .custom-design-thumbnail {
              display: grid !important;
              place-items: center;
              overflow: hidden;
              color: #5f6368;
              background: #f3f4f6;
              font-size: 10px;
              font-weight: 800;
              line-height: 1;
            }
            .custom-design-thumbnail img {
              width: 100%;
              height: 100%;
              object-fit: contain;
            }
            #customBalloonDesignFileInput {
              display: none;
            }
            .custom-design-upload {
              position: absolute;
              right: -6px;
              bottom: -6px;
              width: 20px;
              height: 20px;
              display: grid;
              place-items: center;
              padding: 0;
              border-radius: 50%;
              border: 1px solid #1769e0;
              background: #1769e0;
              color: #fff;
              font-size: 16px;
              font-weight: 800;
              line-height: 1;
            }
            .custom-design-tools {
              grid-column: 1 / -1;
              display: inline-flex;
              align-items: center;
              gap: 8px;
              min-height: 32px;
              color: #5f6368;
              font-size: 12px;
              font-weight: 700;
            }
            .custom-design-tools[hidden] {
              display: none;
            }
            .custom-design-size-button {
              width: 30px;
              height: 30px;
              display: grid;
              place-items: center;
              padding: 0;
              border-radius: 50%;
              color: #1769e0;
              border-color: #1769e0;
              font-size: 20px;
              font-weight: 800;
              line-height: 1;
            }
            .custom-design-scale-value {
              min-width: 44px;
              color: #1d1d1f;
              text-align: center;
            }
            .segmented {
              display: grid;
              grid-template-columns: repeat(4, minmax(0, 1fr));
              gap: 8px;
            }
            .segmented.two {
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
            .segmented.three {
              grid-template-columns: repeat(3, minmax(0, 1fr));
            }
            .segment input {
              position: absolute;
              opacity: 0;
              pointer-events: none;
            }
            .segment span {
              min-height: 36px;
              display: grid;
              place-items: center;
              border: 1px solid #b8bdc6;
              border-radius: 6px;
              background: #fff;
              cursor: pointer;
              font-size: 14px;
            }
            .segment input:checked + span {
              background: #1769e0;
              border-color: #1769e0;
              color: white;
            }
            .list {
              display: grid;
              gap: 18px;
              margin-top: 14px;
            }
            .genre-group {
              display: grid;
              gap: 10px;
            }
            .middle-category-group {
              display: grid;
              gap: 10px;
            }
            .middle-category-heading {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 10px;
              margin-top: 8px;
              padding: 8px 12px;
              border-radius: 8px;
              background: #fff8e1;
              border: 1px solid #f4d28b;
            }
            .middle-category-heading h4 {
              margin: 0;
              font-size: 14px;
            }
            .middle-category-count {
              color: #5f6368;
              font-size: 12px;
              white-space: nowrap;
            }
            .middle-category-actions {
              display: flex;
              gap: 8px;
              align-items: center;
              flex-wrap: wrap;
              justify-content: flex-end;
            }
            .small-category-group {
              display: grid;
              gap: 10px;
            }
            .small-category-heading {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 10px;
              margin-top: 8px;
              padding: 8px 12px;
              border-radius: 8px;
              background: #efffdd;
              border: 1px solid #ccefb0;
            }
            .small-category-heading.resale {
              background: #eef7ff;
              border-color: #b8daf7;
            }
            .small-category-heading.resale-ladies {
              background: #fff0f6;
              border-color: #f4a8c8;
            }
            .small-category-heading.resale-other {
              background: #f0fff4;
              border-color: #bbf7d0;
            }
            .small-category-heading.simple-rule {
              background: #f3f4f6;
              border-color: #d1d5db;
            }
            .small-category-heading.mind-dlab {
              background: #f3e8ff;
              border-color: #c084fc;
            }
            .small-category-heading h4 {
              margin: 0;
              font-size: 14px;
            }
            .small-category-count {
              color: #5f6368;
              font-size: 12px;
              white-space: nowrap;
            }
            .small-category-actions {
              display: flex;
              gap: 8px;
              align-items: center;
              flex-wrap: wrap;
              justify-content: flex-end;
            }
            .genre-heading {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 12px;
              padding-bottom: 6px;
              border-bottom: 1px solid #e0e3e8;
            }
            .genre-heading h3 {
              margin: 0;
              font-size: 16px;
            }
            .genre-title-pill {
              display: inline-flex;
              align-items: center;
              justify-content: center;
              min-height: 42px;
              padding: 0 18px;
              border: 1px solid #111;
              border-radius: 8px;
              background: #111;
              color: #fff;
              font-weight: 800;
              line-height: 1.2;
            }
            .genre-count {
              color: #5f6368;
              font-size: 13px;
            }
            .genre-actions {
              display: flex;
              gap: 8px;
              align-items: center;
              flex-wrap: wrap;
              justify-content: flex-end;
            }
            .item {
              display: grid;
              grid-template-columns: 74px minmax(0, 1fr) auto;
              gap: 12px;
              align-items: center;
              border: 1px solid #e0e3e8;
              border-radius: 8px;
              padding: 10px;
            }
            .item.enabled {
              border-left: 5px solid #16a34a;
            }
            .item.disabled {
              background: #f8f9fb;
            }
            .item-marker {
              position: relative;
              width: 66px;
              min-height: 48px;
              display: grid;
              gap: 5px;
              place-items: center;
            }
            .item-number {
              display: inline-flex;
              align-items: center;
              justify-content: center;
              min-width: 50px;
              min-height: 20px;
              padding: 0 7px;
              border-radius: 999px;
              background: #eef2ff;
              color: #1d4ed8;
              font-size: 12px;
              font-weight: 800;
            }
            .item-dot {
              width: 30px;
              height: 30px;
              border-radius: 50%;
            }
            .running-mark {
              position: absolute;
              right: 0;
              bottom: 0;
              width: 17px;
              height: 17px;
              border-radius: 50%;
              background: #16a34a;
              border: 3px solid #fff;
              box-shadow: 0 0 0 1px rgba(22, 163, 74, 0.35);
            }
            .item.disabled .item-dot {
              filter: grayscale(1);
              opacity: 0.45;
            }
            .item-title {
              font-weight: 700;
              margin: 0 0 3px;
            }
            .item-status {
              display: inline-flex;
              align-items: center;
              min-height: 22px;
              padding: 0 8px;
              border-radius: 999px;
              background: #dcfce7;
              color: #166534;
              font-size: 12px;
              font-weight: 700;
              margin-left: 8px;
              vertical-align: 2px;
            }
            .item-status.off {
              background: #eef0f3;
              color: #5f6368;
            }
            .favorite-button {
              width: 42px;
              min-width: 42px;
              height: 36px;
              padding: 0;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              font-size: 22px;
              line-height: 1;
              color: #9ca3af;
              border-color: #d1d5db;
            }
            .favorite-button.active {
              color: #fff;
              border-color: #111;
              background: #111;
            }
            .item-meta {
              color: #5f6368;
              font-size: 13px;
              margin: 0;
            }
            .list-filter {
              display: grid;
              grid-template-columns: repeat(3, minmax(135px, 1fr)) 118px 112px;
              column-gap: 12px;
              row-gap: 10px;
              align-items: end;
              margin: 16px 0 14px;
            }
            .list-filter .keyword-filter {
              grid-column: 1 / -1;
              max-width: 520px;
            }
            .list-filter label {
              gap: 6px;
              min-width: 0;
            }
            .list-filter select,
            .list-filter input {
              width: 100%;
              box-sizing: border-box;
            }
            .list-filter button,
            .list-filter a.button {
              width: 100%;
              height: 36px;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              white-space: nowrap;
              padding: 0 8px;
              box-sizing: border-box;
            }
            .empty {
              color: #5f6368;
              margin: 12px 0 0;
            }
            .actions {
              display: flex;
              flex-wrap: wrap;
              gap: 10px;
              margin-top: 18px;
              align-items: center;
            }
            .item .actions {
              flex-wrap: nowrap;
            }
            .item .actions .button {
              height: 36px;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              box-sizing: border-box;
              white-space: nowrap;
            }
            button, a.button, span.button {
              appearance: none;
              border: 1px solid #b8bdc6;
              background: #fff;
              color: #1d1d1f;
              border-radius: 6px;
              padding: 9px 14px;
              font-size: 14px;
              text-decoration: none;
              cursor: pointer;
            }
            span.button {
              cursor: default;
            }
            button.primary, a.primary {
              background: #1769e0;
              border-color: #1769e0;
              color: white;
            }
            button.danger, a.danger {
              background: #d93025;
              border-color: #d93025;
              color: white;
            }
            .disabled-control {
              color: #8a9099;
              background: #f3f4f6;
            }
            .notice {
              padding: 10px 12px;
              border-radius: 6px;
              background: #e9f2ff;
              color: #184f99;
              margin: 0 0 16px;
            }
            .header-position-form {
              flex: 1;
              max-width: 620px;
              display: grid;
              grid-template-columns: minmax(110px, 0.65fr) minmax(125px, 0.75fr) minmax(150px, 1fr) auto;
              gap: 8px;
              align-items: end;
              margin: 0;
            }
            .header-position-form label {
              gap: 6px;
              margin: 0;
              font-weight: 700;
            }
            .header-position-form input,
            .header-position-form select {
              width: 100%;
              box-sizing: border-box;
            }
            .header-position-form button {
              height: 36px;
              padding: 0 12px;
              white-space: nowrap;
            }
            @media (max-width: 620px) {
              header, .grid, .preview, .item, .panel-heading { display: block; }
              .heading-actions { justify-content: flex-start; margin: 12px 0 0; }
              .color-size-row { grid-template-columns: 1fr; }
              .position-controls { grid-template-columns: 1fr; }
              .explanation-image-grid { grid-template-columns: 1fr; }
              label { margin-bottom: 14px; }
              .preview-balloon { margin-bottom: 14px; }
              .item-dot { margin-bottom: 8px; }
              .header-position-form {
                min-width: 0;
                grid-template-columns: 1fr;
                margin-top: 14px;
              }
            }
          </style>
        </head>
        <body>
          <main>
            <header>
              <div>
                <h1>Balloon Overlay</h1>
                <div class="status">状態: \(status) / 管理URL: \(adminURL.absoluteString)</div>
              </div>
              <form class="header-position-form" action="/set-launch-position" method="post">
                <input type="hidden" name="tab" value="\(selectedTab.htmlEscaped)">
                <label>
                  一旦停止時間（秒）
                  <input name="middlePauseDuration" form="balloonCreateForm" type="number" min="0" step="0.1" value="\(formatDuration(formBalloon.middlePauseDuration))">
                </label>
                <label>
                  上昇スピード（px/秒）
                  <input name="climbSpeed" type="number" min="40" max="900" step="10" value="\(climbSpeed)">
                </label>
                <label>
                  風船が這い上がる場所
                  <select name="launchPositionName">
                    \(headerPositionOptions)
                  </select>
                </label>
                <button type="submit">保存</button>
              </form>
            </header>
            \(escapedMessage)
            <nav class="tabs">
              <a class="\(createTabClass)" href="/?tab=create">風船作成</a>
              <a class="\(listTabClass)" href="/?tab=list">作成した風船一覧</a>
            </nav>
            \(tabContent)
          </main>
          <div id="attachmentPreviewModal" class="attachment-preview-modal" aria-hidden="true">
            <div class="attachment-preview-panel" role="dialog" aria-modal="true" aria-labelledby="attachmentPreviewTitle">
              <div class="attachment-preview-head">
                <div>
                  <h3 id="attachmentPreviewTitle">添付した画像</h3>
                  <p id="attachmentPreviewFilename" class="attachment-preview-filename"></p>
                </div>
                <button id="attachmentPreviewTopClose" class="button" type="button">閉じる</button>
              </div>
              <div class="attachment-preview-body">
                <img id="attachmentPreviewImage" alt="添付画像のプレビュー">
              </div>
              <div class="attachment-preview-actions">
                <button id="attachmentPreviewClose" class="button primary attachment-preview-close" type="button">確認しました</button>
              </div>
            </div>
          </div>
          <script>
            const imageFileInput = document.querySelector("#imageFileInput");
            const imageDataURLInput = document.querySelector("#imageDataURLInput");
            const removeImageDataInput = document.querySelector("#removeImageDataInput");
            const imageAttachmentItem = document.querySelector("#imageAttachmentItem");
            const imageStatus = document.querySelector("#imageStatus");
            const imageCheckButton = document.querySelector("#imageCheckButton");
            const backImageFileInput = document.querySelector("#backImageFileInput");
            const backImageDataURLInput = document.querySelector("#backImageDataURLInput");
            const removeBackImageDataInput = document.querySelector("#removeBackImageDataInput");
            const backImageAttachmentItem = document.querySelector("#backImageAttachmentItem");
            const backImageStatus = document.querySelector("#backImageStatus");
            const backImageCheckButton = document.querySelector("#backImageCheckButton");
            const explanationImageSlots = [1, 2, 3, 4, 5, 6, 7, 8].map((index) => ({
              index,
              fileInput: document.querySelector(`#explanationImageFileInput${index}`),
              dataInput: document.querySelector(`#explanationImageDataURLInput${index}`),
              removeInput: document.querySelector(`#removeExplanationImageDataInput${index}`),
              item: document.querySelector(`#explanationImageItem${index}`),
              status: document.querySelector(`#explanationImageStatus${index}`),
              checkButton: document.querySelector(`#explanationImageCheckButton${index}`)
            }));
            const previewBody = document.querySelector("#previewBody");
            const previewBalloon = document.querySelector("#previewBalloon");
            const previewSideButtons = document.querySelectorAll("[data-preview-side]");
            const sizeInputs = document.querySelectorAll('input[name="sizeName"]');
            const colorInputs = document.querySelectorAll('input[name="colorName"]');
            const customBalloonDesignDataURLInput = document.querySelector("#customBalloonDesignDataURLInput");
            const customBalloonDesignFileInput = document.querySelector("#customBalloonDesignFileInput");
            const customBalloonDesignRadio = document.querySelector("#customBalloonDesignRadio");
            const customBalloonDesignThumbnail = document.querySelector("#customBalloonDesignThumbnail");
            const customBalloonDesignUploadButton = document.querySelector("#customBalloonDesignUploadButton");
            const customBalloonDesignScaleInput = document.querySelector("#customBalloonDesignScaleInput");
            const customBalloonDesignTools = document.querySelector("#customBalloonDesignTools");
            const customBalloonDesignScaleValue = document.querySelector("#customBalloonDesignScaleValue");
            const customBalloonDesignScaleDownButton = document.querySelector("#customBalloonDesignScaleDownButton");
            const customBalloonDesignScaleUpButton = document.querySelector("#customBalloonDesignScaleUpButton");
            const genreSelect = document.querySelector('select[name="selectedGenreName"]');
            const newGenreInput = document.querySelector('input[name="newGenreName"]');
            const addGenreButton = document.querySelector("#addGenreButton");
            const middleCategorySelect = document.querySelector('select[name="selectedMiddleCategoryName"]');
            const middleCategoryGenreSelect = document.querySelector('select[name="middleCategoryGenreName"]');
            const manageMiddleCategoryGenreSelect = document.querySelector('select[name="manageMiddleCategoryGenreName"]');
            const manageMiddleCategorySelect = document.querySelector('select[name="manageMiddleCategoryName"]');
            const newMiddleCategoryInput = document.querySelector('input[name="newMiddleCategoryName"]');
            const addMiddleCategoryButton = document.querySelector("#addMiddleCategoryButton");
            const smallCategorySelect = document.querySelector('select[name="selectedSmallCategoryName"]');
            const smallCategoryGenreSelect = document.querySelector('select[name="smallCategoryGenreName"]');
            const smallCategoryMiddleCategorySelect = document.querySelector('select[name="smallCategoryMiddleCategoryName"]');
            const manageGenreSelect = document.querySelector('select[name="manageGenreName"]');
            const manageSmallCategoryGenreSelect = document.querySelector('select[name="manageSmallCategoryGenreName"]');
            const manageSmallCategoryMiddleCategorySelect = document.querySelector('select[name="manageSmallCategoryMiddleCategoryName"]');
            const manageSmallCategorySelect = document.querySelector('select[name="manageSmallCategoryName"]');
            const listGenreFilterSelect = document.querySelector('select[name="listGenreFilter"]');
            const listMiddleCategoryFilterSelect = document.querySelector('select[name="listMiddleCategoryFilter"]');
            const listSmallCategoryFilterSelect = document.querySelector('select[name="listSmallCategoryFilter"]');
            const newSmallCategoryInput = document.querySelector('input[name="newSmallCategoryName"]');
            const addSmallCategoryButton = document.querySelector("#addSmallCategoryButton");
            const editGenreButton = document.querySelector("#editGenreButton");
            const editMiddleCategoryButton = document.querySelector("#editMiddleCategoryButton");
            const editSmallCategoryButton = document.querySelector("#editSmallCategoryButton");
            const categoryEditPanelMount = document.querySelector("#categoryEditPanelMount");
            const resetCreateFormButton = document.querySelector("#resetCreateFormButton");
            const testBalloonButton = document.querySelector("#testBalloonButton");
            const previewTitleMeta = document.querySelector("#previewTitleMeta");
            const previewBackMeta = document.querySelector("#previewBackMeta");
            const previewGenreMeta = document.querySelector("#previewGenreMeta");
            const previewSpeedMeta = document.querySelector("#previewSpeedMeta");
            const previewPositionMeta = document.querySelector("#previewPositionMeta");
            const previewSizeMeta = document.querySelector("#previewSizeMeta");
            const previewPauseMeta = document.querySelector("#previewPauseMeta");
            const previewBackBadge = document.querySelector("#previewBackBadge");
            const textInput = document.querySelector('[name="text"]');
            const backTextInput = document.querySelector('[name="backText"]');
            const textFontSizeInput = document.querySelector('input[name="textFontSize"]');
            const imageScaleInput = document.querySelector('input[name="imageScale"]');
            const textOffsetXInput = document.querySelector('input[name="textOffsetX"]');
            const textOffsetYInput = document.querySelector('input[name="textOffsetY"]');
            const imageCaptionOffsetXInput = document.querySelector('input[name="imageCaptionOffsetX"]');
            const imageCaptionOffsetYInput = document.querySelector('input[name="imageCaptionOffsetY"]');
            const attachmentPreviewModal = document.querySelector("#attachmentPreviewModal");
            const attachmentPreviewTitle = document.querySelector("#attachmentPreviewTitle");
            const attachmentPreviewFilename = document.querySelector("#attachmentPreviewFilename");
            const attachmentPreviewImage = document.querySelector("#attachmentPreviewImage");
            const attachmentPreviewClose = document.querySelector("#attachmentPreviewClose");
            const attachmentPreviewTopClose = document.querySelector("#attachmentPreviewTopClose");
            const listReturnStorageKey = "balloonOverlayLastListReturnPath";
            const listScrollStorageKey = "balloonOverlayLastListScrollY";
            const queryParams = new URLSearchParams(window.location.search);

            function sanitizedPathFromLocation() {
              const url = new URL(window.location.href);
              ["returnTo", "returnScrollY", "restoreScrollY"].forEach((name) => {
                url.searchParams.delete(name);
              });
              return `${url.pathname}${url.search}`;
            }

            function hasListState(path) {
              try {
                const url = new URL(path, window.location.origin);
                return ["itemNumberSearch", "listGenreFilter", "listMiddleCategoryFilter", "listSmallCategoryFilter", "listSort", "listFavoriteFilter"].some((name) => {
                  const value = url.searchParams.get(name);
                  return value !== null && value !== "";
                });
              } catch {
                return false;
              }
            }

            function storedListReturnPath() {
              const stored = sessionStorage.getItem(listReturnStorageKey);
              return stored && stored.startsWith("/") ? stored : "/?tab=list";
            }

            function currentReturnPath() {
              const path = sanitizedPathFromLocation();
              if (new URL(path, window.location.origin).searchParams.get("tab") === "list") {
                sessionStorage.setItem(listReturnStorageKey, path);
                return path;
              }
              return storedListReturnPath();
            }

            if (queryParams.get("tab") === "list") {
              const currentPath = sanitizedPathFromLocation();
              const storedPath = storedListReturnPath();
              if (!hasListState(currentPath) && hasListState(storedPath)) {
                const redirectUrl = new URL(storedPath, window.location.origin);
                ["message", "restoreScrollY"].forEach((name) => {
                  const value = queryParams.get(name);
                  if (value !== null) redirectUrl.searchParams.set(name, value);
                });
                window.location.replace(`${redirectUrl.pathname}${redirectUrl.search}`);
              } else {
                sessionStorage.setItem(listReturnStorageKey, currentPath);
              }
            }

            const restoreScrollY = queryParams.get("restoreScrollY");
            if (restoreScrollY !== null) {
              requestAnimationFrame(() => {
                window.scrollTo(0, Number(restoreScrollY) || 0);
              });
            }

            document.querySelectorAll("[data-edit-button]").forEach((button) => {
              const baseHref = button.getAttribute("href") || button.href;
              button.dataset.baseHref = baseHref;
              button.addEventListener("click", () => {
                sessionStorage.setItem(listScrollStorageKey, String(window.scrollY));
                const editUrl = new URL(button.dataset.baseHref || baseHref, window.location.origin);
                editUrl.searchParams.delete("returnTo");
                editUrl.searchParams.delete("returnScrollY");
                editUrl.searchParams.set("returnTo", currentReturnPath());
                editUrl.searchParams.set("returnScrollY", String(window.scrollY));
                button.href = `${editUrl.pathname}${editUrl.search}${editUrl.hash}`;
              });
            });

            function applyFavoriteButtonState(button, isFavorite) {
              button.dataset.favorite = isFavorite ? "1" : "0";
              button.classList.toggle("active", isFavorite);
              button.textContent = isFavorite ? "⭐️" : "☆";
              button.title = isFavorite ? "お気に入り解除" : "お気に入り";
              const id = button.dataset.id;
              if (id) {
                button.href = `/toggle-favorite?id=${encodeURIComponent(id)}&favorite=${isFavorite ? "0" : "1"}`;
              }
            }

            document.querySelectorAll("[data-favorite-button]").forEach((button) => {
              button.addEventListener("click", async (event) => {
                event.preventDefault();

                const id = button.dataset.id;
                if (!id || button.dataset.loading === "1") return;

                const wasFavorite = button.dataset.favorite === "1";
                const nextFavorite = !wasFavorite;
                button.dataset.loading = "1";
                applyFavoriteButtonState(button, nextFavorite);

                try {
                  const response = await fetch(`/toggle-favorite?id=${encodeURIComponent(id)}&favorite=${nextFavorite ? "1" : "0"}`, {
                    method: "POST"
                  });
                  if (!response.ok) throw new Error("favorite update failed");
                } catch {
                  applyFavoriteButtonState(button, wasFavorite);
                  window.alert("お気に入りの更新に失敗しました。もう一度お試しください。");
                } finally {
                  button.dataset.loading = "0";
                }
              });
            });

            document.querySelectorAll("[data-show-button]").forEach((button) => {
              button.addEventListener("click", async (event) => {
                event.preventDefault();

                const id = button.dataset.id;
                if (!id || button.dataset.loading === "1") return;

                button.dataset.loading = "1";
                try {
                  sessionStorage.setItem(listScrollStorageKey, String(window.scrollY));
                  const showUrl = new URL(button.getAttribute("href") || `/show?id=${encodeURIComponent(id)}`, window.location.origin);
                  showUrl.searchParams.set("returnTo", currentReturnPath());
                  showUrl.searchParams.set("returnScrollY", String(window.scrollY));
                  button.href = `${showUrl.pathname}${showUrl.search}${showUrl.hash}`;
                  const response = await fetch(button.href, {
                    method: "POST"
                  });
                  if (!response.ok) throw new Error("show update failed");
                } catch {
                  window.alert("表示に失敗しました。もう一度お試しください。");
                } finally {
                  button.dataset.loading = "0";
                }
              });
            });

            document.querySelector("#clearListFilters")?.addEventListener("click", () => {
              sessionStorage.removeItem(listReturnStorageKey);
              sessionStorage.removeItem(listScrollStorageKey);
            });

            document.querySelector('form[action="/save"]')?.addEventListener("submit", (event) => {
              const form = event.currentTarget;
              const returnToInput = form.querySelector('input[name="returnTo"]');
              const returnScrollYInput = form.querySelector('input[name="returnScrollY"]');
              if (returnToInput && !hasListState(returnToInput.value)) {
                returnToInput.value = storedListReturnPath();
              }
              if (returnScrollYInput && (!returnScrollYInput.value || returnScrollYInput.value === "0")) {
                returnScrollYInput.value = sessionStorage.getItem(listScrollStorageKey) || "0";
              }
            });

            testBalloonButton?.addEventListener("click", async () => {
              const form = testBalloonButton.closest("form");
              if (!form || testBalloonButton.dataset.loading === "1") return;

              const originalText = testBalloonButton.textContent;
              testBalloonButton.dataset.loading = "1";
              testBalloonButton.disabled = true;
              testBalloonButton.textContent = "テスト表示中...";
              try {
                const response = await fetch("/test-balloon", {
                  method: "POST",
                  body: new URLSearchParams(new FormData(form))
                });
                if (!response.ok) throw new Error("test balloon failed");
              } catch {
                window.alert("テスト表示に失敗しました。もう一度お試しください。");
              } finally {
                testBalloonButton.dataset.loading = "0";
                testBalloonButton.disabled = false;
                testBalloonButton.textContent = originalText;
              }
            });

            function currentScale() {
              return 2;
            }

            function selectedSizeName() {
              return document.querySelector('input[name="sizeName"]:checked')?.value || "";
            }

            function sizedFont(input, fallback) {
              const value = Number(input?.value || 0);
              const scale = currentScale();
              const fallbackSize = input?.name === "textFontSize" && scale > 1 ? 39 : fallback;
              return `${(value > 0 ? value : fallbackSize) * scale}px`;
            }

            function updateFontSizeDisplays() {
              document.querySelectorAll("[data-font-display]").forEach((display) => {
                const name = display.dataset.fontDisplay;
                const input = document.querySelector(`input[name="${name}"]`);
                const value = Number(input?.value || 0);
                display.textContent = value > 0 ? `${value}px` : "自動";
              });
            }

            function currentImageScale() {
              const value = Number(imageScaleInput?.value || 1);
              return Math.min(2.0, Math.max(0.6, Number.isFinite(value) ? value : 1));
            }

            function updateImageScaleDisplays() {
              const scale = currentImageScale();
              document.querySelectorAll("[data-image-scale-display]").forEach((display) => {
                display.textContent = Math.abs(scale - 1) < 0.01 ? "自動" : `${Math.round(scale * 100)}%`;
              });
            }

            function applyPreviewImageScale() {
              if (!previewBody) return;
              previewBody.style.setProperty("--preview-image-scale", currentImageScale());
              updateImageScaleDisplays();
            }

            function currentOffset(input) {
              const value = Number(input?.value || 0);
              return Math.min(0.45, Math.max(-0.45, Number.isFinite(value) ? value : 0));
            }

            function updateOffsetDisplays() {
              document.querySelectorAll("[data-position-display]").forEach((display) => {
                const xInput = document.querySelector(`input[name="${display.dataset.positionX}"]`);
                const yInput = document.querySelector(`input[name="${display.dataset.positionY}"]`);
                const xValue = currentOffset(xInput);
                const yValue = currentOffset(yInput);

                if (Math.abs(xValue) < 0.001 && Math.abs(yValue) < 0.001) {
                  display.textContent = "中央";
                  return;
                }

                const parts = [];
                if (Math.abs(yValue) >= 0.001) {
                  parts.push(`${yValue < 0 ? "上" : "下"} ${Math.round(Math.abs(yValue) * 100)}%`);
                }
                if (Math.abs(xValue) >= 0.001) {
                  parts.push(`${xValue < 0 ? "左" : "右"} ${Math.round(Math.abs(xValue) * 100)}%`);
                }
                display.textContent = parts.join(" / ");
              });
            }

            function applyPreviewTextPositions() {
              if (!previewBody) return;
              const contentSize = 96 * currentScale() * 0.82;
              previewBody.style.setProperty("--preview-text-offset-x", `${currentOffset(textOffsetXInput) * contentSize}px`);
              previewBody.style.setProperty("--preview-text-offset-y", `${currentOffset(textOffsetYInput) * contentSize}px`);
              previewBody.style.setProperty("--preview-image-offset-x", `${currentOffset(imageCaptionOffsetXInput) * contentSize}px`);
              previewBody.style.setProperty("--preview-image-offset-y", `${currentOffset(imageCaptionOffsetYInput) * contentSize}px`);
              updateOffsetDisplays();
            }

            function applyPreviewFontSizes() {
              if (!previewBody) return;
              previewBody.style.fontSize = sizedFont(textFontSizeInput, 26);
              previewBody.querySelectorAll(".preview-image-caption").forEach((caption) => {
                caption.style.fontSize = sizedFont(textFontSizeInput, 12);
              });
              updateFontSizeDisplays();
            }

            function adjustImageScale(delta) {
              if (!imageScaleInput) return;
              imageScaleInput.value = (Math.round(Math.min(2.0, Math.max(0.6, currentImageScale() + delta)) * 10) / 10).toFixed(1);
              applyPreviewImageScale();
            }

            function resetImageScale() {
              if (!imageScaleInput) return;
              imageScaleInput.value = "1.0";
              applyPreviewImageScale();
            }

            function adjustOffset(targetName, delta) {
              const input = document.querySelector(`input[name="${targetName}"]`);
              if (!input) return;
              input.value = (Math.round(Math.min(0.45, Math.max(-0.45, currentOffset(input) + delta)) * 100) / 100).toFixed(2);
              applyPreviewTextPositions();
            }

            function resetPosition(xName, yName) {
              [xName, yName].forEach((name) => {
                const input = document.querySelector(`input[name="${name}"]`);
                if (input) input.value = "0.00";
              });
              applyPreviewTextPositions();
            }

            function setPosition(xName, yName, xValue, yValue) {
              const xInput = document.querySelector(`input[name="${xName}"]`);
              const yInput = document.querySelector(`input[name="${yName}"]`);
              if (xInput) xInput.value = Number(xValue).toFixed(2);
              if (yInput) yInput.value = Number(yValue).toFixed(2);
              applyPreviewTextPositions();
            }

            function applyInitialImageLayout() {
              setPosition("imageCaptionOffsetX", "imageCaptionOffsetY", 0, 0);
              applySizePreset(selectedSizeName());
            }

            function applySizePreset(sizeName) {
              if (textFontSizeInput) textFontSizeInput.value = "16";
              setPosition("textOffsetX", "textOffsetY", 0, -0.03);
            }

            function applySizeSelection(input) {
              if (!input?.checked) return;
              applySizePreset(input.value);
              if (previewSizeMeta) previewSizeMeta.textContent = `サイズ: ${input.value}`;
              applyPreviewFontSizes();
              applyPreviewImageScale();
              applyPreviewTextPositions();
            }

            function applyPreviewColor(input) {
              if (!previewBody || !input) return;
              const start = input.dataset.startHex;
              const end = input.dataset.endHex;
              if (!start || !end) return;
              previewBody.classList.remove("custom-balloon-design");
              previewBody.style.background = "transparent";
              previewBody.style.setProperty("--preview-color-start", start);
              previewBody.style.setProperty("--preview-color-end", end);
              previewBody.style.removeProperty("--custom-balloon-design-image");
              previewBody.style.removeProperty("--custom-balloon-design-scale");
              const knot = previewBalloon?.querySelector(".preview-knot");
              if (knot) knot.style.borderTopColor = end;
            }

            function applyCustomBalloonDesign(dataURL) {
              if (!previewBody || !dataURL) return;
              previewBody.classList.add("custom-balloon-design");
              previewBody.style.background = "transparent";
              previewBody.style.setProperty("--custom-balloon-design-image", `url("${dataURL}")`);
              previewBody.style.setProperty("--custom-balloon-design-scale", currentCustomBalloonDesignScale());
            }

            function updateCustomBalloonDesignThumbnail(dataURL) {
              if (!customBalloonDesignThumbnail) return;
              customBalloonDesignThumbnail.innerHTML = "";
              if (!dataURL) {
                customBalloonDesignThumbnail.textContent = "自作";
                if (customBalloonDesignRadio) customBalloonDesignRadio.disabled = true;
                if (customBalloonDesignTools) customBalloonDesignTools.hidden = true;
                return;
              }

              const image = document.createElement("img");
              image.src = dataURL;
              image.alt = "自作風船";
              customBalloonDesignThumbnail.append(image);
              if (customBalloonDesignRadio) customBalloonDesignRadio.disabled = false;
              if (customBalloonDesignTools) customBalloonDesignTools.hidden = false;
            }

            function currentCustomBalloonDesignScale() {
              const value = Number(customBalloonDesignScaleInput?.value || 1);
              return Math.min(2.5, Math.max(0.5, Number.isFinite(value) ? value : 1));
            }

            function updateCustomBalloonDesignScale(nextScale) {
              const scale = Math.round(Math.min(2.5, Math.max(0.5, nextScale)) * 10) / 10;
              if (customBalloonDesignScaleInput) customBalloonDesignScaleInput.value = scale.toFixed(1);
              if (customBalloonDesignScaleValue) customBalloonDesignScaleValue.textContent = `${Math.round(scale * 100)}%`;
              if (customBalloonDesignRadio?.checked) {
                previewBody?.style.setProperty("--custom-balloon-design-scale", scale);
              }
            }

            function adjustFontSize(targetName, delta) {
              const input = document.querySelector(`input[name="${targetName}"]`);
              if (!input) return;

              const current = Number(input.value || 0);
              const base = current > 0 ? current : 26;
              input.value = String(Math.min(90, Math.max(4, base + delta)));
              applyPreviewFontSizes();
            }

            function resetFontSize(targetName) {
              const input = document.querySelector(`input[name="${targetName}"]`);
              if (!input) return;
              input.value = "0";
              applyPreviewFontSizes();
            }

            function activePreviewSide() {
              return document.querySelector("[data-preview-side].active")?.dataset.previewSide || "front";
            }

            function previewHasBackSide() {
              return Boolean((backTextInput?.value || "").trim() || (backImageDataURLInput?.value || "").trim());
            }

            function applyPreviewBodyState() {
              previewBody?.classList.toggle("has-back", previewHasBackSide());
            }

            function captionLineCount(text) {
              return Math.max(1, String(text || "").split(/\\r\\n|\\r|\\n/).length);
            }

            function setPreviewSide(side) {
              previewSideButtons.forEach((button) => {
                const isActive = button.dataset.previewSide === side;
                button.classList.toggle("active", isActive);
                button.setAttribute("aria-pressed", isActive ? "true" : "false");
              });
              if (previewBackBadge) {
                previewBackBadge.textContent = side === "back" ? "表へ" : "裏あり";
              }
              renderPreviewSide();
            }

            function renderPreviewText(text) {
              if (!previewBody) return;
              applyPreviewBodyState();
              previewBody.innerHTML = "";
              const content = document.createElement("span");
              content.className = "preview-content";
              content.textContent = text || "🎈";
              previewBody.append(content);
              applyPreviewFontSizes();
              applyPreviewTextPositions();
            }

            function renderPreviewImage(dataURL, captionText) {
              if (!previewBody) return;
              applyPreviewBodyState();

              previewBody.innerHTML = "";
              const stack = document.createElement("span");
              const hasManyCaptionLines = captionText && captionLineCount(captionText) > 2;
              stack.className = captionText
                ? `preview-image-stack has-caption${hasManyCaptionLines ? " many-caption-lines" : ""}`
                : "preview-image-stack";

              if (captionText) {
                const caption = document.createElement("span");
                caption.className = "preview-content preview-image-caption";
                caption.textContent = captionText;
                stack.append(caption);
              }

              const image = document.createElement("img");
              image.src = dataURL;
              image.alt = "";
              stack.append(image);

              previewBody.append(stack);
              applyPreviewFontSizes();
              applyPreviewImageScale();
              applyPreviewTextPositions();
            }

            function renderPreviewSide() {
              const side = activePreviewSide();
              if (side === "back") {
                if (backImageDataURLInput?.value) {
                  renderPreviewImage(backImageDataURLInput.value, backTextInput?.value.trim() || "");
                } else {
                  renderPreviewText(backTextInput?.value || "裏面");
                }
                return;
              }

              if (imageDataURLInput?.value) {
                renderPreviewImage(imageDataURLInput.value, textInput?.value.trim() || "");
              } else {
                renderPreviewText(textInput?.value || "🎈");
              }
            }

            function showAttachmentPreview(title, file, dataURL) {
              if (!attachmentPreviewModal || !attachmentPreviewImage) return;
              if (attachmentPreviewTitle) attachmentPreviewTitle.textContent = title;
              if (attachmentPreviewFilename) {
                const fileName = typeof file === "string" ? file : file?.name;
                attachmentPreviewFilename.textContent = fileName ? `ファイル名: ${fileName}` : "";
              }
              attachmentPreviewImage.src = dataURL;
              attachmentPreviewModal.classList.add("open");
              attachmentPreviewModal.setAttribute("aria-hidden", "false");
            }

            function closeAttachmentPreview() {
              if (!attachmentPreviewModal || !attachmentPreviewImage) return;
              attachmentPreviewModal.classList.remove("open");
              attachmentPreviewModal.setAttribute("aria-hidden", "true");
              attachmentPreviewImage.removeAttribute("src");
            }

            function updateAttachmentState(item, status, checkButton, hasImage) {
              item?.classList.toggle("attached", hasImage);
              if (status) status.textContent = hasImage ? "添付済み" : "未添付";
              if (checkButton) checkButton.disabled = !hasImage;
              const removeButton = item?.querySelector("[data-remove-attachment]");
              if (removeButton) removeButton.disabled = !hasImage;
            }

            function resetRemoveControl(control) {
              if (control && "checked" in control) {
                control.checked = false;
              }
            }

            function clearAttachment({ dataInput, fileInput, removeInput, item, status, checkButton, rerender = false }) {
              if (!dataInput?.value && !fileInput?.value) {
                resetRemoveControl(removeInput);
                updateAttachmentState(item, status, checkButton, false);
                return;
              }

              if (!window.confirm("本当に消しますか？")) {
                resetRemoveControl(removeInput);
                return;
              }

              dataInput.value = "";
              if (fileInput) fileInput.value = "";
              resetRemoveControl(removeInput);
              updateAttachmentState(item, status, checkButton, false);
              if (rerender) renderPreviewSide();
            }

            function bindAttachmentRemove(control, options) {
              control?.addEventListener("click", (event) => {
                event.preventDefault();
                clearAttachment(options);
              });

              control?.addEventListener("change", () => {
                if ("checked" in control && !control.checked) return;
                clearAttachment(options);
              });
            }

            function resetField(form, selector, value) {
              const field = form.querySelector(selector);
              if (field) field.value = value;
            }

            function resetChecked(form, selector, checked) {
              const field = form.querySelector(selector);
              if (field) field.checked = checked;
            }

            function resetCreateForm(event) {
              event?.preventDefault();
              const form = resetCreateFormButton?.closest("form");
              if (!form) return;

              resetField(form, 'input[name="title"]', "");
              resetField(form, '[name="text"]', "");
              resetField(form, '[name="backText"]', "");
              resetField(form, 'textarea[name="explanationText"]', "");
              resetField(form, 'input[name="textFontSize"]', "16");
              resetField(form, 'input[name="imageScale"]', "1.0");
              resetField(form, 'input[name="textOffsetX"]', "0.00");
              resetField(form, 'input[name="textOffsetY"]', "-0.03");
              resetField(form, 'input[name="imageCaptionOffsetX"]', "0.00");
              resetField(form, 'input[name="imageCaptionOffsetY"]', "0.00");
              resetField(form, 'input[name="intervalMinutes"]', "1.0");
              resetField(form, 'input[name="climbSpeed"]', "400");
              resetField(form, 'input[name="randomIntervalMinSeconds"]', "5");
              resetField(form, 'input[name="randomIntervalMaxSeconds"]', "600");
              resetField(form, 'input[name="middlePauseDuration"]', "15");
              const headerPauseDurationInput = document.querySelector('input[name="middlePauseDuration"][form="balloonCreateForm"]');
              if (headerPauseDurationInput) headerPauseDurationInput.value = "15";
              resetChecked(form, 'input[name="pausesAtMiddle"]', true);

              const defaultColor = form.querySelector('input[name="colorName"][value="レッド"]') || form.querySelector('input[name="colorName"]');
              if (defaultColor) defaultColor.checked = true;
              applyPreviewColor(defaultColor);
              if (customBalloonDesignFileInput) customBalloonDesignFileInput.value = "";
              if (customBalloonDesignDataURLInput) customBalloonDesignDataURLInput.value = "";
              updateCustomBalloonDesignScale(1);
              updateCustomBalloonDesignThumbnail("");
              const defaultPosition = form.querySelector('input[name="positionName"][value="ランダム"]') || form.querySelector('input[name="positionName"]');
              if (defaultPosition) defaultPosition.value = "ランダム";
              const defaultSize = form.querySelector('input[name="sizeName"][value="ラージ"]') || form.querySelector('input[name="sizeName"]');
              if (defaultSize) defaultSize.checked = true;

              if (genreSelect) genreSelect.value = "未分類";
              if (newGenreInput) newGenreInput.value = "";
              if (middleCategoryGenreSelect) middleCategoryGenreSelect.value = "未分類";
              if (middleCategorySelect) middleCategorySelect.value = "";
              if (manageMiddleCategoryGenreSelect) manageMiddleCategoryGenreSelect.value = "未分類";
              if (manageMiddleCategorySelect) manageMiddleCategorySelect.value = "";
              if (newMiddleCategoryInput) newMiddleCategoryInput.value = "";
              if (smallCategoryGenreSelect) smallCategoryGenreSelect.value = "未分類";
              if (smallCategoryMiddleCategorySelect) smallCategoryMiddleCategorySelect.value = "";
              if (smallCategorySelect) smallCategorySelect.value = "";
              if (manageSmallCategoryGenreSelect) manageSmallCategoryGenreSelect.value = "未分類";
              if (manageSmallCategoryMiddleCategorySelect) manageSmallCategoryMiddleCategorySelect.value = "";
              if (manageSmallCategorySelect) manageSmallCategorySelect.value = "";
              if (newSmallCategoryInput) newSmallCategoryInput.value = "";
              updateMiddleCategoryOptions();
              updateManageMiddleCategoryOptions();
              updateSmallCategoryMiddleCategoryOptions();
              updateManageSmallCategoryMiddleCategoryOptions();
              updateSmallCategoryOptions();
              updateManageSmallCategoryOptions();
              if (imageFileInput) imageFileInput.value = "";
              if (imageDataURLInput) imageDataURLInput.value = "";
              resetRemoveControl(removeImageDataInput);
              updateAttachmentState(imageAttachmentItem, imageStatus, imageCheckButton, false);
              if (backImageFileInput) backImageFileInput.value = "";
              if (backImageDataURLInput) backImageDataURLInput.value = "";
              resetRemoveControl(removeBackImageDataInput);
              updateAttachmentState(backImageAttachmentItem, backImageStatus, backImageCheckButton, false);
              applyPreviewImageScale();
              applyPreviewTextPositions();
              explanationImageSlots.forEach(({ fileInput, dataInput, removeInput, item, status, checkButton }) => {
                if (fileInput) fileInput.value = "";
                if (dataInput) dataInput.value = "";
                resetRemoveControl(removeInput);
                updateAttachmentState(item, status, checkButton, false);
              });
              previewBalloon?.classList.add("large");
              previewBalloon?.classList.remove("extra-large");
              setPreviewSide("front");
              if (previewTitleMeta) previewTitleMeta.textContent = "表面: ";
              if (previewBackMeta) previewBackMeta.textContent = "裏面: なし";
              if (previewGenreMeta) previewGenreMeta.textContent = "名前カテゴリ: 大カテゴリ 未分類";
              if (previewSpeedMeta) previewSpeedMeta.textContent = "上昇スピード: 400 px/秒";
              if (previewPositionMeta) previewPositionMeta.textContent = "上昇位置: ランダム";
              if (previewSizeMeta) previewSizeMeta.textContent = "サイズ: ラージ";
              if (previewPauseMeta) previewPauseMeta.textContent = "中央停止: 15秒";
              applyPreviewFontSizes();
              applyPreviewImageScale();
              applyPreviewTextPositions();
              renderPreviewSide();
            }

            resetCreateFormButton?.addEventListener("click", resetCreateForm);

            function postCategoryEdit(url, values) {
              return fetch(url, {
                method: "POST",
                headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
                body: new URLSearchParams(values)
              });
            }

            function updateGenreOptions(oldName, newName) {
              document.querySelectorAll("select option").forEach((option) => {
                if (option.value === oldName && option.textContent === oldName) {
                  option.value = newName;
                  option.textContent = newName;
                }
                if (option.dataset.genre === oldName) {
                  option.dataset.genre = newName;
                }
              });
            }

            function updateMiddleCategoryOptionsAfterRename(genreName, oldName, newName) {
              [middleCategorySelect, manageMiddleCategorySelect, smallCategoryMiddleCategorySelect, manageSmallCategoryMiddleCategorySelect, listMiddleCategoryFilterSelect].forEach((select) => {
                select?.querySelectorAll("option").forEach((option) => {
                  if (option.value === oldName && (option.dataset.genre || genreName) === genreName) {
                    option.value = newName;
                    option.textContent = newName;
                  }
                });
              });
              document.querySelectorAll("select option").forEach((option) => {
                if (option.dataset.middleCategory === oldName && (option.dataset.genre || genreName) === genreName) {
                  option.dataset.middleCategory = newName;
                }
              });
            }

            function updateSmallCategoryOptionsAfterRename(genreName, middleCategoryName, oldName, newName) {
              [smallCategorySelect, manageSmallCategorySelect, listSmallCategoryFilterSelect].forEach((select) => {
                select?.querySelectorAll("option").forEach((option) => {
                  if (option.value === oldName
                      && (option.dataset.genre || genreName) === genreName
                      && (option.dataset.middleCategory || middleCategoryName) === middleCategoryName) {
                    option.value = newName;
                    option.textContent = newName;
                  }
                });
              });
            }

            function clearCategoryEditPanel() {
              if (categoryEditPanelMount) categoryEditPanelMount.innerHTML = "";
            }

            function showCategoryEditPanel({ title, description, value, onSave }) {
              if (!categoryEditPanelMount) return;

              categoryEditPanelMount.innerHTML = "";
              const panel = document.createElement("span");
              panel.className = "category-edit-panel";

              const heading = document.createElement("strong");
              heading.textContent = title;
              const descriptionNode = document.createElement("p");
              descriptionNode.textContent = description;

              const actions = document.createElement("span");
              actions.className = "category-edit-actions";
              const input = document.createElement("input");
              input.value = value;
              input.placeholder = title.includes("小カテゴリ")
                ? "修正後の小カテゴリ名"
                : title.includes("中カテゴリ")
                  ? "修正後の中カテゴリ名"
                  : "修正後の大カテゴリ名";
              const saveButton = document.createElement("button");
              saveButton.type = "button";
              saveButton.textContent = "保存";
              const cancelButton = document.createElement("button");
              cancelButton.type = "button";
              cancelButton.className = "button";
              cancelButton.textContent = "キャンセル";

              saveButton.addEventListener("click", async () => {
                const nextValue = input.value.trim();
                if (!nextValue) return;
                saveButton.disabled = true;
                try {
                  await onSave(nextValue);
                  clearCategoryEditPanel();
                  updateMiddleCategoryOptions();
                  updateManageMiddleCategoryOptions();
                  updateSmallCategoryMiddleCategoryOptions();
                  updateManageSmallCategoryMiddleCategoryOptions();
                  updateSmallCategoryOptions();
                  updateManageSmallCategoryOptions();
                  updateListMiddleCategoryFilterOptions();
                  updateListSmallCategoryFilterOptions();
                } finally {
                  saveButton.disabled = false;
                }
              });
              cancelButton.addEventListener("click", clearCategoryEditPanel);

              actions.append(input, saveButton, cancelButton);
              panel.append(heading, descriptionNode, actions);
              categoryEditPanelMount.append(panel);
              input.focus();
              input.select();
            }

            function fitImageToBalloon(file, maxSize = 1400, quality = 0.94) {
              return new Promise((resolve, reject) => {
                const reader = new FileReader();
                reader.onload = () => {
                  const image = new Image();
                  image.onload = () => {
                    const scale = Math.min(1, maxSize / Math.max(image.width, image.height));
                    const canvas = document.createElement("canvas");
                    canvas.width = Math.max(1, Math.round(image.width * scale));
                    canvas.height = Math.max(1, Math.round(image.height * scale));
                    const context = canvas.getContext("2d");
                    context.imageSmoothingEnabled = true;
                    context.imageSmoothingQuality = "high";
                    context.clearRect(0, 0, canvas.width, canvas.height);
                    context.fillStyle = "#ffffff";
                    context.fillRect(0, 0, canvas.width, canvas.height);
                    context.drawImage(image, 0, 0, canvas.width, canvas.height);
                    resolve(canvas.toDataURL("image/jpeg", quality));
                  };
                  image.onerror = reject;
                  image.src = reader.result;
                };
                reader.onerror = reject;
                reader.readAsDataURL(file);
              });
            }

            function croppedCustomBalloonDesignDataURL(source, maxSize = 512) {
              return new Promise((resolve, reject) => {
                const image = new Image();
                image.onload = () => {
                  const scale = Math.min(1, maxSize / Math.max(image.width, image.height));
                  const canvas = document.createElement("canvas");
                  canvas.width = Math.max(1, Math.round(image.width * scale));
                  canvas.height = Math.max(1, Math.round(image.height * scale));
                  const context = canvas.getContext("2d");
                  context.imageSmoothingEnabled = true;
                  context.imageSmoothingQuality = "high";
                  context.clearRect(0, 0, canvas.width, canvas.height);
                  context.drawImage(image, 0, 0, canvas.width, canvas.height);

                  const width = canvas.width;
                  const height = canvas.height;
                  const pixels = context.getImageData(0, 0, width, height).data;
                  const edgeColors = [];
                  const sampleStep = Math.max(1, Math.floor(Math.min(width, height) / 24));
                  const addSample = (x, y) => {
                    const index = (y * width + x) * 4;
                    if (pixels[index + 3] > 20) {
                      edgeColors.push([pixels[index], pixels[index + 1], pixels[index + 2]]);
                    }
                  };

                  for (let x = 0; x < width; x += sampleStep) {
                    addSample(x, 0);
                    addSample(x, height - 1);
                  }
                  for (let y = 0; y < height; y += sampleStep) {
                    addSample(0, y);
                    addSample(width - 1, y);
                  }

                  const resemblesEdgeBackground = (r, g, b) => {
                    return edgeColors.some(([er, eg, eb]) => {
                      return Math.abs(r - er) + Math.abs(g - eg) + Math.abs(b - eb) < 42;
                    });
                  };

                  let minX = width;
                  let minY = height;
                  let maxX = -1;
                  let maxY = -1;
                  for (let y = 0; y < height; y += 1) {
                    for (let x = 0; x < width; x += 1) {
                      const index = (y * width + x) * 4;
                      const alpha = pixels[index + 3];
                      if (alpha <= 20) continue;

                      const r = pixels[index];
                      const g = pixels[index + 1];
                      const b = pixels[index + 2];
                      if (edgeColors.length > 0 && resemblesEdgeBackground(r, g, b)) continue;

                      minX = Math.min(minX, x);
                      minY = Math.min(minY, y);
                      maxX = Math.max(maxX, x);
                      maxY = Math.max(maxY, y);
                    }
                  }

                  if (maxX < minX || maxY < minY) {
                    resolve(canvas.toDataURL("image/png"));
                    return;
                  }

                  const padding = Math.ceil(Math.max(width, height) * 0.025);
                  minX = Math.max(0, minX - padding);
                  minY = Math.max(0, minY - padding);
                  maxX = Math.min(width - 1, maxX + padding);
                  maxY = Math.min(height - 1, maxY + padding);

                  const cropWidth = maxX - minX + 1;
                  const cropHeight = maxY - minY + 1;
                  const output = document.createElement("canvas");
                  output.width = cropWidth;
                  output.height = cropHeight;
                  const outputContext = output.getContext("2d");
                  outputContext.imageSmoothingEnabled = true;
                  outputContext.imageSmoothingQuality = "high";
                  outputContext.clearRect(0, 0, cropWidth, cropHeight);
                  outputContext.drawImage(canvas, minX, minY, cropWidth, cropHeight, 0, 0, cropWidth, cropHeight);
                  const outputPixels = outputContext.getImageData(0, 0, cropWidth, cropHeight);
                  const outputData = outputPixels.data;
                  for (let index = 0; index < outputData.length; index += 4) {
                    const alpha = outputData[index + 3];
                    if (alpha <= 20 || (edgeColors.length > 0 && resemblesEdgeBackground(outputData[index], outputData[index + 1], outputData[index + 2]))) {
                      outputData[index + 3] = 0;
                    }
                  }
                  outputContext.putImageData(outputPixels, 0, 0);
                  resolve(output.toDataURL("image/png"));
                };
                image.onerror = reject;
                image.src = source;
              });
            }

            function fitCustomBalloonDesign(file, maxSize = 512) {
              return new Promise((resolve, reject) => {
                const reader = new FileReader();
                reader.onload = () => {
                  croppedCustomBalloonDesignDataURL(reader.result, maxSize).then(resolve, reject);
                };
                reader.onerror = reject;
                reader.readAsDataURL(file);
              });
            }

            customBalloonDesignUploadButton?.addEventListener("click", () => {
              customBalloonDesignFileInput?.click();
            });

            customBalloonDesignFileInput?.addEventListener("change", async () => {
              const file = customBalloonDesignFileInput.files?.[0];
              if (!file || !customBalloonDesignDataURLInput) return;

              try {
                const dataURL = await fitCustomBalloonDesign(file);
                customBalloonDesignDataURLInput.value = dataURL;
                updateCustomBalloonDesignScale(1);
                if (customBalloonDesignRadio) {
                  customBalloonDesignRadio.disabled = false;
                  customBalloonDesignRadio.checked = true;
                }
                updateCustomBalloonDesignThumbnail(dataURL);
                applyCustomBalloonDesign(dataURL);
                showAttachmentPreview("自作風船デザイン", file, dataURL);
              } catch {
                window.alert("自作風船画像を読み込めませんでした。別の画像を選んでください。");
              }
            });

            customBalloonDesignScaleDownButton?.addEventListener("click", () => {
              updateCustomBalloonDesignScale(currentCustomBalloonDesignScale() - 0.1);
            });

            customBalloonDesignScaleUpButton?.addEventListener("click", () => {
              updateCustomBalloonDesignScale(currentCustomBalloonDesignScale() + 0.1);
            });

            imageFileInput?.addEventListener("change", async () => {
              const file = imageFileInput.files?.[0];
              if (!file || !imageDataURLInput || !previewBody) return;

              try {
                const dataURL = await fitImageToBalloon(file);
                imageDataURLInput.value = dataURL;
                resetRemoveControl(removeImageDataInput);
                updateAttachmentState(imageAttachmentItem, imageStatus, imageCheckButton, true);
                applyInitialImageLayout();
                setPreviewSide("front");
                showAttachmentPreview("表に添付した画像", file, dataURL);
              } catch {
                window.alert("画像を読み込めませんでした。別の画像を選んでください。");
              }
            });

            bindAttachmentRemove(removeImageDataInput, {
              dataInput: imageDataURLInput,
              fileInput: imageFileInput,
              removeInput: removeImageDataInput,
              item: imageAttachmentItem,
              status: imageStatus,
              checkButton: imageCheckButton,
              rerender: true
            });

            imageCheckButton?.addEventListener("click", (event) => {
              event.preventDefault();
              if (!imageDataURLInput?.value) return;
              showAttachmentPreview("表に添付した画像", "保存済み画像", imageDataURLInput.value);
            });

            backImageFileInput?.addEventListener("change", async () => {
              const file = backImageFileInput.files?.[0];
              if (!file || !backImageDataURLInput) return;

              try {
                const dataURL = await fitImageToBalloon(file);
                backImageDataURLInput.value = dataURL;
                resetRemoveControl(removeBackImageDataInput);
                updateAttachmentState(backImageAttachmentItem, backImageStatus, backImageCheckButton, true);
                applyInitialImageLayout();
                setPreviewSide("back");
                showAttachmentPreview("裏に添付した画像", file, dataURL);
              } catch {
                window.alert("裏面画像を読み込めませんでした。別の画像を選んでください。");
              }
            });

            bindAttachmentRemove(removeBackImageDataInput, {
              dataInput: backImageDataURLInput,
              fileInput: backImageFileInput,
              removeInput: removeBackImageDataInput,
              item: backImageAttachmentItem,
              status: backImageStatus,
              checkButton: backImageCheckButton,
              rerender: true
            });

            backImageCheckButton?.addEventListener("click", (event) => {
              event.preventDefault();
              if (!backImageDataURLInput?.value) return;
              showAttachmentPreview("裏に添付した画像", "保存済み画像", backImageDataURLInput.value);
            });

            explanationImageSlots.forEach(({ index, fileInput, dataInput, removeInput, item, status, checkButton }) => {
              fileInput?.addEventListener("change", async () => {
                const file = fileInput.files?.[0];
                if (!file || !dataInput) return;

                try {
                  const dataURL = await fitImageToBalloon(file, 1000, 0.9);
                  dataInput.value = dataURL;
                  resetRemoveControl(removeInput);
                  updateAttachmentState(item, status, checkButton, true);
                  showAttachmentPreview(`解説に添付した画像${index}`, file, dataURL);
                } catch {
                  window.alert(`解説画像${index}を読み込めませんでした。別の画像を選んでください。`);
                }
              });

              bindAttachmentRemove(removeInput, {
                dataInput,
                fileInput,
                removeInput,
                item,
                status,
                checkButton
              });

              checkButton?.addEventListener("click", (event) => {
                event.preventDefault();
                if (!dataInput?.value) return;
                showAttachmentPreview(`解説に添付した画像${index}`, "保存済み画像", dataInput.value);
              });
            });

            attachmentPreviewClose?.addEventListener("click", closeAttachmentPreview);
            attachmentPreviewTopClose?.addEventListener("click", closeAttachmentPreview);
            attachmentPreviewModal?.addEventListener("click", (event) => {
              if (event.target === attachmentPreviewModal) closeAttachmentPreview();
            });
            document.addEventListener("keydown", (event) => {
              if (event.key === "Escape") closeAttachmentPreview();
            });

            sizeInputs.forEach((input) => {
              input.addEventListener("change", () => applySizeSelection(input));
              input.addEventListener("click", () => applySizeSelection(input));
            });

            colorInputs.forEach((input) => {
              input.addEventListener("change", () => {
                if (!input.checked) return;
                if (input === customBalloonDesignRadio) {
                  applyCustomBalloonDesign(customBalloonDesignDataURLInput?.value || "");
                } else {
                  applyPreviewColor(input);
                }
              });
            });
            updateCustomBalloonDesignThumbnail(customBalloonDesignDataURLInput?.value || "");
            updateCustomBalloonDesignScale(currentCustomBalloonDesignScale());
            if (customBalloonDesignDataURLInput?.value) {
              croppedCustomBalloonDesignDataURL(customBalloonDesignDataURLInput.value).then((croppedDataURL) => {
                if (!croppedDataURL || croppedDataURL === customBalloonDesignDataURLInput.value) return;
                customBalloonDesignDataURLInput.value = croppedDataURL;
                updateCustomBalloonDesignThumbnail(croppedDataURL);
                if (customBalloonDesignRadio?.checked) {
                  applyCustomBalloonDesign(croppedDataURL);
                }
              }).catch(() => {});
            }

            previewSideButtons.forEach((button) => {
              button.addEventListener("click", () => setPreviewSide(button.dataset.previewSide || "front"));
            });
            textInput?.addEventListener("input", renderPreviewSide);
            backTextInput?.addEventListener("input", renderPreviewSide);
            document.querySelectorAll("[data-font-target]").forEach((button) => {
              button.addEventListener("click", () => {
                const target = button.dataset.fontTarget;
                if (!target) return;
                if (button.dataset.fontAuto === "true") {
                  resetFontSize(target);
                } else {
                  adjustFontSize(target, Number(button.dataset.fontDelta || 0));
                }
              });
            });
            document.querySelectorAll("[data-image-scale-delta]").forEach((button) => {
              button.addEventListener("click", () => {
                adjustImageScale(Number(button.dataset.imageScaleDelta || 0));
              });
            });
            document.querySelectorAll("[data-image-scale-auto]").forEach((button) => {
              button.addEventListener("click", resetImageScale);
            });
            document.querySelectorAll("[data-position-target]").forEach((button) => {
              button.addEventListener("click", () => {
                const target = button.dataset.positionTarget;
                if (!target) return;
                adjustOffset(target, Number(button.dataset.positionDelta || 0));
              });
            });
            document.querySelectorAll("[data-position-reset]").forEach((button) => {
              button.addEventListener("click", () => {
                resetPosition(button.dataset.positionX, button.dataset.positionY);
              });
            });
            applyPreviewImageScale();
            applyPreviewTextPositions();
            renderPreviewSide();

            function selectedLargeCategory() {
              return newGenreInput?.value.trim() || genreSelect?.value || "未分類";
            }

            function selectedMiddleCategory() {
              return middleCategorySelect?.value || "";
            }

            function selectedSmallCategoryGenre() {
              return smallCategoryGenreSelect?.value || selectedLargeCategory();
            }

            function selectedSmallCategoryMiddleCategory() {
              return smallCategoryMiddleCategorySelect?.value || selectedMiddleCategory();
            }

            function updateFilteredOptions(select, isVisible) {
              if (!select) return;
              let hasSelectedVisibleOption = false;

              Array.from(select.options).forEach((option) => {
                const visible = option.value === "" || isVisible(option);
                option.hidden = !visible;
                option.disabled = !visible;
                if (visible && option.selected) {
                  hasSelectedVisibleOption = true;
                }
              });

              if (!hasSelectedVisibleOption) {
                select.value = "";
              }
            }

            function updateMiddleCategoryOptions() {
              const largeCategory = selectedLargeCategory();
              updateFilteredOptions(middleCategorySelect, (option) => (option.dataset.genre || "") === largeCategory);
            }

            function updateManageMiddleCategoryOptions() {
              const largeCategory = manageMiddleCategoryGenreSelect?.value || "未分類";
              updateFilteredOptions(manageMiddleCategorySelect, (option) => (option.dataset.genre || "") === largeCategory);
            }

            function updateSmallCategoryMiddleCategoryOptions() {
              const largeCategory = selectedSmallCategoryGenre();
              updateFilteredOptions(smallCategoryMiddleCategorySelect, (option) => (option.dataset.genre || "") === largeCategory);
            }

            function updateManageSmallCategoryMiddleCategoryOptions() {
              const largeCategory = manageSmallCategoryGenreSelect?.value || "未分類";
              updateFilteredOptions(manageSmallCategoryMiddleCategorySelect, (option) => (option.dataset.genre || "") === largeCategory);
            }

            function updateSmallCategoryOptions() {
              const largeCategory = selectedLargeCategory();
              const middleCategory = selectedMiddleCategory();
              updateFilteredOptions(smallCategorySelect, (option) => {
                return (option.dataset.genre || "") === largeCategory
                  && (option.dataset.middleCategory || "") === middleCategory;
              });
            }

            function updateManageSmallCategoryOptions() {
              const largeCategory = manageSmallCategoryGenreSelect?.value || "未分類";
              const middleCategory = manageSmallCategoryMiddleCategorySelect?.value || "";
              updateFilteredOptions(manageSmallCategorySelect, (option) => {
                return (option.dataset.genre || "") === largeCategory
                  && (option.dataset.middleCategory || "") === middleCategory;
              });
            }

            function updateListMiddleCategoryFilterOptions() {
              const largeCategory = listGenreFilterSelect?.value || "";
              updateFilteredOptions(listMiddleCategoryFilterSelect, (option) => {
                return !largeCategory || (option.dataset.genre || "") === largeCategory;
              });
            }

            function updateListSmallCategoryFilterOptions() {
              const largeCategory = listGenreFilterSelect?.value || "";
              const middleCategory = listMiddleCategoryFilterSelect?.value || "";
              updateFilteredOptions(listSmallCategoryFilterSelect, (option) => {
                return (!largeCategory || (option.dataset.genre || "") === largeCategory)
                  && (!middleCategory || (option.dataset.middleCategory || "") === middleCategory);
              });
            }

            genreSelect?.addEventListener("change", () => {
              if (middleCategoryGenreSelect) {
                middleCategoryGenreSelect.value = selectedLargeCategory();
              }
              if (smallCategoryGenreSelect) {
                smallCategoryGenreSelect.value = selectedLargeCategory();
              }
              updateMiddleCategoryOptions();
              updateSmallCategoryMiddleCategoryOptions();
              updateSmallCategoryOptions();
            });
            middleCategorySelect?.addEventListener("change", updateSmallCategoryOptions);
            newGenreInput?.addEventListener("input", () => {
              updateMiddleCategoryOptions();
              updateSmallCategoryOptions();
            });
            manageMiddleCategoryGenreSelect?.addEventListener("change", updateManageMiddleCategoryOptions);
            smallCategoryGenreSelect?.addEventListener("change", updateSmallCategoryMiddleCategoryOptions);
            manageSmallCategoryGenreSelect?.addEventListener("change", () => {
              updateManageSmallCategoryMiddleCategoryOptions();
              updateManageSmallCategoryOptions();
            });
            manageSmallCategoryMiddleCategorySelect?.addEventListener("change", updateManageSmallCategoryOptions);
            listGenreFilterSelect?.addEventListener("change", () => {
              updateListMiddleCategoryFilterOptions();
              updateListSmallCategoryFilterOptions();
            });
            listMiddleCategoryFilterSelect?.addEventListener("change", updateListSmallCategoryFilterOptions);
            updateMiddleCategoryOptions();
            updateManageMiddleCategoryOptions();
            updateSmallCategoryMiddleCategoryOptions();
            updateManageSmallCategoryMiddleCategoryOptions();
            updateSmallCategoryOptions();
            updateManageSmallCategoryOptions();
            updateListMiddleCategoryFilterOptions();
            updateListSmallCategoryFilterOptions();

            addGenreButton?.addEventListener("click", () => {
              const genreName = newGenreInput?.value.trim();
              if (!genreName || !genreSelect || !newGenreInput) return;

              const existingOption = Array.from(genreSelect.options).find((option) => option.value === genreName);
              if (existingOption) {
                genreSelect.value = genreName;
              } else {
                const option = document.createElement("option");
                option.value = genreName;
                option.textContent = genreName;
                option.selected = true;
                genreSelect.append(option);
              }
              [middleCategoryGenreSelect, manageMiddleCategoryGenreSelect, smallCategoryGenreSelect, manageSmallCategoryGenreSelect].forEach((select) => {
                if (!select) return;
                if (!Array.from(select.options).some((option) => option.value === genreName)) {
                  const option = document.createElement("option");
                  option.value = genreName;
                  option.textContent = genreName;
                  select.append(option);
                }
              });
              if (middleCategoryGenreSelect) middleCategoryGenreSelect.value = genreName;
              if (smallCategoryGenreSelect) smallCategoryGenreSelect.value = genreName;
              newGenreInput.value = "";
              updateMiddleCategoryOptions();
              updateManageMiddleCategoryOptions();
              updateSmallCategoryMiddleCategoryOptions();
              updateManageSmallCategoryMiddleCategoryOptions();
              updateSmallCategoryOptions();
              updateManageSmallCategoryOptions();
            });

            addMiddleCategoryButton?.addEventListener("click", () => {
              const middleCategoryName = newMiddleCategoryInput?.value.trim();
              if (!middleCategoryName || !middleCategorySelect || !newMiddleCategoryInput) return;
              const largeCategory = middleCategoryGenreSelect?.value || selectedLargeCategory();

              [middleCategorySelect, manageMiddleCategorySelect, smallCategoryMiddleCategorySelect, manageSmallCategoryMiddleCategorySelect].forEach((select) => {
                if (!select) return;
                const existingOption = Array.from(select.options).find((option) => {
                  return option.value === middleCategoryName && (option.dataset.genre || "") === largeCategory;
                });
                if (existingOption) {
                  if (select === middleCategorySelect) existingOption.selected = true;
                  return;
                }
                const option = document.createElement("option");
                option.value = middleCategoryName;
                option.textContent = middleCategoryName;
                option.dataset.genre = largeCategory;
                if (select === middleCategorySelect) option.selected = true;
                select.append(option);
              });
              if (genreSelect) genreSelect.value = largeCategory;
              if (middleCategoryGenreSelect) middleCategoryGenreSelect.value = largeCategory;
              if (smallCategoryGenreSelect) smallCategoryGenreSelect.value = largeCategory;
              if (smallCategoryMiddleCategorySelect) smallCategoryMiddleCategorySelect.value = middleCategoryName;
              newMiddleCategoryInput.value = "";
              updateMiddleCategoryOptions();
              updateManageMiddleCategoryOptions();
              updateSmallCategoryMiddleCategoryOptions();
              updateManageSmallCategoryMiddleCategoryOptions();
              updateSmallCategoryOptions();
              updateManageSmallCategoryOptions();
            });

            addSmallCategoryButton?.addEventListener("click", () => {
              const smallCategoryName = newSmallCategoryInput?.value.trim();
              if (!smallCategoryName || !smallCategorySelect || !newSmallCategoryInput) return;
              const largeCategory = selectedSmallCategoryGenre();
              const middleCategory = selectedSmallCategoryMiddleCategory();

              const existingOption = Array.from(smallCategorySelect.options).find((option) => {
                return option.value === smallCategoryName
                  && (option.dataset.genre || "") === largeCategory
                  && (option.dataset.middleCategory || "") === middleCategory;
              });
              if (existingOption) {
                smallCategorySelect.value = smallCategoryName;
              } else {
                const option = document.createElement("option");
                option.value = smallCategoryName;
                option.textContent = smallCategoryName;
                option.dataset.genre = largeCategory;
                option.dataset.middleCategory = middleCategory;
                option.selected = true;
                smallCategorySelect.append(option);
              }
              if (manageSmallCategorySelect && !Array.from(manageSmallCategorySelect.options).some((option) => {
                return option.value === smallCategoryName
                  && (option.dataset.genre || "") === largeCategory
                  && (option.dataset.middleCategory || "") === middleCategory;
              })) {
                const option = document.createElement("option");
                option.value = smallCategoryName;
                option.textContent = smallCategoryName;
                option.dataset.genre = largeCategory;
                option.dataset.middleCategory = middleCategory;
                manageSmallCategorySelect.append(option);
              }
              if (genreSelect) {
                genreSelect.value = largeCategory;
              }
              if (smallCategoryGenreSelect) {
                smallCategoryGenreSelect.value = largeCategory;
              }
              if (middleCategorySelect) {
                middleCategorySelect.value = middleCategory;
              }
              newSmallCategoryInput.value = "";
              updateSmallCategoryOptions();
              updateManageSmallCategoryOptions();
            });

            editGenreButton?.addEventListener("click", () => {
              const genreName = manageGenreSelect?.value || "";
              if (!genreName) return;

              showCategoryEditPanel({
                title: "大カテゴリ名を修正",
                description: `選択中: ${genreName}`,
                value: genreName,
                onSave: async (newGenreName) => {
                  await postCategoryEdit(`/rename-genre?targetGenreName=${encodeURIComponent(genreName)}`, {
                    renamedGenreName: newGenreName
                  });
                  updateGenreOptions(genreName, newGenreName);
                  if (genreSelect?.value === genreName) genreSelect.value = newGenreName;
                  if (middleCategoryGenreSelect?.value === genreName) middleCategoryGenreSelect.value = newGenreName;
                  if (manageMiddleCategoryGenreSelect?.value === genreName) manageMiddleCategoryGenreSelect.value = newGenreName;
                  if (smallCategoryGenreSelect?.value === genreName) smallCategoryGenreSelect.value = newGenreName;
                  if (manageGenreSelect) manageGenreSelect.value = newGenreName;
                  if (manageSmallCategoryGenreSelect?.value === genreName) manageSmallCategoryGenreSelect.value = newGenreName;
                }
              });
            });

            editMiddleCategoryButton?.addEventListener("click", () => {
              const genreName = manageMiddleCategoryGenreSelect?.value || "";
              const middleCategoryName = manageMiddleCategorySelect?.value || "";
              if (!genreName || !middleCategoryName) return;

              showCategoryEditPanel({
                title: "中カテゴリ名を修正",
                description: `大カテゴリ: ${genreName} / 中カテゴリ: ${middleCategoryName}`,
                value: middleCategoryName,
                onSave: async (newMiddleCategoryName) => {
                  await postCategoryEdit(`/rename-middle-category?targetMiddleCategoryGenreName=${encodeURIComponent(genreName)}&targetMiddleCategoryName=${encodeURIComponent(middleCategoryName)}`, {
                    renamedMiddleCategoryName: newMiddleCategoryName
                  });
                  updateMiddleCategoryOptionsAfterRename(genreName, middleCategoryName, newMiddleCategoryName);
                  if (middleCategorySelect?.value === middleCategoryName) middleCategorySelect.value = newMiddleCategoryName;
                  if (manageMiddleCategorySelect) manageMiddleCategorySelect.value = newMiddleCategoryName;
                  if (smallCategoryMiddleCategorySelect?.value === middleCategoryName) smallCategoryMiddleCategorySelect.value = newMiddleCategoryName;
                  if (manageSmallCategoryMiddleCategorySelect?.value === middleCategoryName) manageSmallCategoryMiddleCategorySelect.value = newMiddleCategoryName;
                }
              });
            });

            editSmallCategoryButton?.addEventListener("click", () => {
              const genreName = manageSmallCategoryGenreSelect?.value || "";
              const middleCategoryName = manageSmallCategoryMiddleCategorySelect?.value || "";
              const smallCategoryName = manageSmallCategorySelect?.value || "";
              if (!genreName || !smallCategoryName) return;

              showCategoryEditPanel({
                title: "小カテゴリ名を修正",
                description: `大カテゴリ: ${genreName} / 中カテゴリ: ${middleCategoryName || "未指定"} / 小カテゴリ: ${smallCategoryName}`,
                value: smallCategoryName,
                onSave: async (newSmallCategoryName) => {
                  await postCategoryEdit(`/rename-small-category?targetSmallCategoryGenreName=${encodeURIComponent(genreName)}&targetSmallCategoryMiddleCategoryName=${encodeURIComponent(middleCategoryName)}&targetSmallCategoryName=${encodeURIComponent(smallCategoryName)}`, {
                    renamedSmallCategoryName: newSmallCategoryName
                  });
                  updateSmallCategoryOptionsAfterRename(genreName, middleCategoryName, smallCategoryName, newSmallCategoryName);
                  if (smallCategorySelect?.value === smallCategoryName) smallCategorySelect.value = newSmallCategoryName;
                  if (manageSmallCategorySelect) manageSmallCategorySelect.value = newSmallCategoryName;
                }
              });
            });

          </script>
        </body>
        </html>
        """
    }

    private func renderCreatePanel(
        intervalMinutes: String,
        randomIntervalMinSeconds: String,
        randomIntervalMaxSeconds: String,
        climbSpeed: String,
        activeBalloon: BalloonProfile,
        editingID: UUID?,
        imageName: String,
        imageDataURL: String,
        backImageName: String,
        backImageDataURL: String,
        previewContent: String,
        colorOptions: String,
        positionOptions: String,
        sizeOptions: String,
        editGenreName: String?,
        editMiddleCategoryGenreName: String?,
        editMiddleCategoryName: String?,
        editSmallCategoryGenreName: String?,
        editSmallCategoryMiddleCategoryName: String?,
        editSmallCategoryName: String?,
        returnTo: String?,
        returnScrollY: String?
    ) -> String {
        let hiddenIDInput = editingID.map { "<input type=\"hidden\" name=\"id\" value=\"\($0.uuidString)\">" } ?? ""
        let returnToInput = editingID == nil ? "" : "<input type=\"hidden\" name=\"returnTo\" value=\"\((returnTo ?? "/?tab=list").htmlEscaped)\">"
        let returnScrollYInput = editingID == nil ? "" : "<input type=\"hidden\" name=\"returnScrollY\" value=\"\((returnScrollY ?? "0").htmlEscaped)\">"
        let submitTitle = editingID == nil ? "保存" : "更新"
        let panelTitle = editingID == nil ? "風船作成" : "風船編集"
        let titleValue = editingID == nil ? "" : activeBalloon.title.htmlEscaped
        let textValue = editingID == nil ? "" : frontTextInputValue(for: activeBalloon).htmlEscaped
        let backTextValue = editingID == nil ? "" : backTextInputValue(for: activeBalloon).htmlEscaped
        let textFontSize = editingID == nil ? "16" : formatFontSize(activeBalloon.textFontSize)
        let imageScale = formatImageScale(activeBalloon.imageScale)
        let textOffsetX = formatPositionOffset(activeBalloon.textOffsetX)
        let textOffsetY = editingID == nil ? "-0.03" : formatPositionOffset(activeBalloon.textOffsetY)
        let imageCaptionOffsetX = formatPositionOffset(activeBalloon.imageCaptionOffsetX)
        let imageCaptionOffsetY = formatPositionOffset(activeBalloon.imageCaptionOffsetY)
        let resetLink = editingID == nil ? "" : "<a class=\"button\" href=\"/?tab=create\">新規作成に戻す</a>"
        let genreOptions = renderGenreOptions(selectedName: activeBalloon.genreName)
        let middleCategoryOptions = renderMiddleCategoryOptions(selectedName: activeBalloon.middleCategoryName, selectedGenreName: activeBalloon.genreName)
        let smallCategoryOptions = renderSmallCategoryOptions(
            selectedName: activeBalloon.smallCategoryName,
            selectedGenreName: activeBalloon.genreName,
            selectedMiddleCategoryName: activeBalloon.middleCategoryName
        )
        let explanationImageInputs = renderExplanationImageInputs(for: activeBalloon)
        let explanationImageControls = renderExplanationImageControls(for: activeBalloon)
        let customBalloonDesignDataURL = activeBalloon.customBalloonDesignDataURL ?? ""
        let customBalloonDesignScale = formatCustomBalloonDesignScale(activeBalloon.customBalloonDesignScale)
        let hasCustomBalloonDesign = !customBalloonDesignDataURL.isEmpty && activeBalloon.colorName == OverlaySettings.customBalloonDesignName
        let previewBodyClasses = [
            "preview-body",
            hasCustomBalloonDesign ? "custom-balloon-design" : "",
            hasBackSide(activeBalloon) ? "has-back" : ""
        ].filter { !$0.isEmpty }.joined(separator: " ")
        let previewBodyClass = previewBodyClasses
        let previewBodyStyle = hasCustomBalloonDesign
            ? " style=\"--custom-balloon-design-image: url(&quot;\(customBalloonDesignDataURL.htmlEscaped)&quot;); --custom-balloon-design-scale: \(customBalloonDesignScale);\""
            : ""
        let hasFrontImage = imageDataURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
        let frontImageAttachmentClass = hasFrontImage ? " attached" : ""
        let frontImageStatus = hasFrontImage ? "添付済み" : "未添付"
        let hasBackImage = backImageDataURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
        let backImageAttachmentClass = hasBackImage ? " attached" : ""
        let backImageStatus = hasBackImage ? "添付済み" : "未添付"
        let categoryEditPanel = renderCategoryEditPanel(
            editGenreName: editGenreName,
            editMiddleCategoryGenreName: editMiddleCategoryGenreName,
            editMiddleCategoryName: editMiddleCategoryName,
            editSmallCategoryGenreName: editSmallCategoryGenreName,
            editSmallCategoryMiddleCategoryName: editSmallCategoryMiddleCategoryName,
            editSmallCategoryName: editSmallCategoryName
        )
        let previewBackBadge = hasBackSide(activeBalloon)
            ? "<span id=\"previewBackBadge\" class=\"preview-badge\">裏あり</span>"
            : ""
        let hasExplanation = activeBalloon.explanationText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
            || !activeBalloon.explanationImageDataURLs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.isEmpty
        let previewExplanationBadge = hasExplanation
            ? "<span class=\"preview-badge dark\">•••</span>"
            : ""
        let previewBadges = previewBackBadge.isEmpty && previewExplanationBadge.isEmpty
            ? ""
            : "<div class=\"preview-badges\">\(previewBackBadge)\(previewExplanationBadge)</div>"
        let previewItemNumber = activeBalloon.itemNumber > 0
            ? "<div class=\"preview-item-number\">\(activeBalloon.itemNumber)</div>"
            : ""

        return """
        <section class="panel">
          <form id="balloonCreateForm" action="/save" method="post">
            \(hiddenIDInput)
            \(returnToInput)
            \(returnScrollYInput)
            <input id="imageDataURLInput" type="hidden" name="imageDataURL" value="\(imageDataURL.htmlEscaped)">
            <input id="backImageDataURLInput" type="hidden" name="backImageDataURL" value="\(backImageDataURL.htmlEscaped)">
            <input id="customBalloonDesignDataURLInput" type="hidden" name="customBalloonDesignDataURL" value="\(customBalloonDesignDataURL.htmlEscaped)">
            <input id="customBalloonDesignScaleInput" type="hidden" name="customBalloonDesignScale" value="\(customBalloonDesignScale)">
            <input type="hidden" name="imageCaptionFontSize" value="0">
            <input id="imageScaleInput" type="hidden" name="imageScale" value="\(imageScale)">
            <input id="textOffsetXInput" type="hidden" name="textOffsetX" value="\(textOffsetX)">
            <input id="textOffsetYInput" type="hidden" name="textOffsetY" value="\(textOffsetY)">
            <input id="imageCaptionOffsetXInput" type="hidden" name="imageCaptionOffsetX" value="\(imageCaptionOffsetX)">
            <input id="imageCaptionOffsetYInput" type="hidden" name="imageCaptionOffsetY" value="\(imageCaptionOffsetY)">
            <input type="hidden" name="intervalMinutes" value="\(intervalMinutes)">
            <input type="hidden" name="positionName" value="\(activeBalloon.positionName.htmlEscaped)">
            <input type="hidden" name="pausesAtMiddle" value="on">
            \(explanationImageInputs)
            <div class="panel-heading">
              <h2>\(panelTitle)</h2>
              <span class="heading-actions">
                <button id="testBalloonButton" class="primary" type="button">作成中の風船をテスト表示</button>
                <button id="resetCreateFormButton" type="button">入力中の内容をリセット</button>
              </span>
            </div>
            <label class="top-field">
              タイトル
              <input name="title" value="\(titleValue)" placeholder="例: 商品名 / 問題名 / メモの名前">
            </label>
            <div class="preview" id="previewArea">
              <div class="preview-balloon large" id="previewBalloon">
                \(previewBadges)
                <div class="\(previewBodyClass)" id="previewBody"\(previewBodyStyle)>\(previewContent)</div>
                <div class="preview-knot"></div>
                \(previewItemNumber)
              </div>
              <div class="preview-controls">
                <div class="preview-side-toggle" aria-label="プレビュー面の切り替え">
                  <button class="button preview-side-button active" type="button" data-preview-side="front">表</button>
                  <button class="button preview-side-button" type="button" data-preview-side="back">裏</button>
                </div>
              </div>
            </div>
            <div class="grid">
              <div class="color-size-row">
                <label>
                  風船カラー
                  <div class="swatches">
                    \(colorOptions)
                  </div>
                </label>
                <label>
                  風船サイズ
                  <div class="segmented three">
                    \(sizeOptions)
                  </div>
                </label>
              </div>
              <label class="front-entry">
                表に入れる文字
                <textarea class="compact" name="text" placeholder="例: しばし待たれよ / 水を飲む / これいくらで売れた?">\(textValue)</textarea>
              </label>
              <div id="imageAttachmentItem" class="file-row front-entry attachment-image-item\(frontImageAttachmentClass)">
                <span class="attachment-image-title">
                  表に入れる画像ファイル
                  <span class="attachment-image-title-actions">
                    <button id="imageCheckButton" class="button image-check-button" type="button" \(hasFrontImage ? "" : "disabled")>画像確認</button>
                    <small id="imageStatus">\(frontImageStatus)</small>
                  </span>
                </span>
                <span class="file-control-row">
                  <input id="imageFileInput" type="file" accept="image/*">
                  <button id="removeImageDataInput" class="button danger image-remove-button" type="button" data-remove-attachment \(hasFrontImage ? "" : "disabled")>表面の添付画像を削除</button>
                </span>
              </div>
              <div class="front-entry font-controls">
                <div class="font-control">
                  <input name="textFontSize" type="hidden" value="\(textFontSize)">
                  <div class="font-control-head">
                    <span>表文字サイズ</span>
                    <span class="font-size-display" data-font-display="textFontSize"></span>
                  </div>
                  <div class="font-step-row">
                    <button class="font-step" type="button" data-font-target="textFontSize" data-font-delta="-2" aria-label="表文字を小さく"><span>-</span></button>
                    <button class="font-step" type="button" data-font-target="textFontSize" data-font-delta="2" aria-label="表文字を大きく"><span>+</span></button>
                    <button class="font-auto" type="button" data-font-target="textFontSize" data-font-auto="true">自動</button>
                  </div>
                </div>
                <div class="font-control">
                  <div class="font-control-head">
                    <span>画像サイズ</span>
                    <span class="font-size-display" data-image-scale-display></span>
                  </div>
                  <div class="font-step-row">
                    <button class="font-step" type="button" data-image-scale-delta="-0.1" aria-label="画像を小さく"><span>-</span></button>
                    <button class="font-step" type="button" data-image-scale-delta="0.1" aria-label="画像を大きく"><span>+</span></button>
                    <button class="font-auto" type="button" data-image-scale-auto="true">自動</button>
                  </div>
                </div>
              </div>
              <div class="front-entry position-controls">
                \(renderPositionControl(title: "表文字位置", xName: "textOffsetX", yName: "textOffsetY"))
                \(renderPositionControl(title: "画像位置", xName: "imageCaptionOffsetX", yName: "imageCaptionOffsetY"))
              </div>
              <label class="back-entry">
                裏に入れる文字
                <textarea class="compact" name="backText" placeholder="例: 答え / 解説の要点 / 裏面メモ">\(backTextValue)</textarea>
              </label>
              <div id="backImageAttachmentItem" class="file-row back-entry attachment-image-item\(backImageAttachmentClass)">
                <span class="attachment-image-title">
                  裏に入れる画像ファイル
                  <span class="attachment-image-title-actions">
                    <button id="backImageCheckButton" class="button image-check-button" type="button" \(hasBackImage ? "" : "disabled")>画像確認</button>
                    <small id="backImageStatus">\(backImageStatus)</small>
                  </span>
                </span>
                <span class="file-control-row">
                  <input id="backImageFileInput" type="file" accept="image/*">
                  <button id="removeBackImageDataInput" class="button danger image-remove-button" type="button" data-remove-attachment \(hasBackImage ? "" : "disabled")>裏面の添付画像を削除</button>
                </span>
              </div>
              <div class="back-entry font-controls">
                <div class="font-control">
                  <div class="font-control-head">
                    <span>裏文字サイズ</span>
                    <span class="font-size-display" data-font-display="textFontSize"></span>
                  </div>
                  <div class="font-step-row">
                    <button class="font-step" type="button" data-font-target="textFontSize" data-font-delta="-2" aria-label="裏文字を小さく"><span>-</span></button>
                    <button class="font-step" type="button" data-font-target="textFontSize" data-font-delta="2" aria-label="裏文字を大きく"><span>+</span></button>
                    <button class="font-auto" type="button" data-font-target="textFontSize" data-font-auto="true">自動</button>
                  </div>
                </div>
                <div class="font-control">
                  <div class="font-control-head">
                    <span>裏画像サイズ</span>
                    <span class="font-size-display" data-image-scale-display></span>
                  </div>
                  <div class="font-step-row">
                    <button class="font-step" type="button" data-image-scale-delta="-0.1" aria-label="裏画像を小さく"><span>-</span></button>
                    <button class="font-step" type="button" data-image-scale-delta="0.1" aria-label="裏画像を大きく"><span>+</span></button>
                    <button class="font-auto" type="button" data-image-scale-auto="true">自動</button>
                  </div>
                </div>
              </div>
              <div class="back-entry position-controls">
                \(renderPositionControl(title: "裏文字位置", xName: "textOffsetX", yName: "textOffsetY"))
                \(renderPositionControl(title: "裏画像位置", xName: "imageCaptionOffsetX", yName: "imageCaptionOffsetY"))
              </div>
              <label class="full explanation-entry">
                解説に入れる内容
                <textarea name="explanationText" placeholder="解説ボタンを押した時に表示する内容">\(activeBalloon.explanationText.htmlEscaped)</textarea>
              </label>
              <label class="full explanation-image-field explanation-entry">
                解説に添付する画像（最大8枚）
                <span class="explanation-image-grid">
                  \(explanationImageControls)
                </span>
              </label>
              <label id="category-editor" class="genre-fields">
                名前カテゴリ
                <span>
                  登録済み大カテゴリから選ぶ
                  <select name="selectedGenreName">
                    \(genreOptions)
                  </select>
                </span>
                <span>
                  選択中の大カテゴリに紐づく中カテゴリから選ぶ
                  <select name="selectedMiddleCategoryName">
                    \(middleCategoryOptions)
                  </select>
                </span>
                <span>
                  選択中の中カテゴリに紐づく小カテゴリから選ぶ
                  <select name="selectedSmallCategoryName">
                    \(smallCategoryOptions)
                  </select>
                </span>
                <span class="category-action-block category-add-block">
                  大カテゴリを追加する
                  <span class="genre-add-row">
                    <input name="newGenreName" value="" placeholder="例: 税金 / 電脳 / アパレル物販">
                    <button id="addGenreButton" type="button">追加</button>
                  </span>
                </span>
                <span class="category-action-block">
                  大カテゴリを修正・削除する
                  <span class="category-manage-row">
                    <select name="manageGenreName">
                      \(genreOptions)
                    </select>
                    <button id="editGenreButton" type="button">修正</button>
                    <button type="submit" formmethod="post" formaction="/delete-genre" onclick="return confirm('本当に削除しますか？');">削除</button>
                  </span>
                </span>
                <span class="category-action-block category-add-block">
                  中カテゴリを紐づける大カテゴリを選んで追加する
                  <span class="middle-category-add-row">
                    <select name="middleCategoryGenreName">
                      \(genreOptions)
                    </select>
                    <input name="newMiddleCategoryName" value="" placeholder="例: バッグ / 家電 / 習慣">
                    <button id="addMiddleCategoryButton" type="button">追加</button>
                  </span>
                </span>
                <span class="category-action-block">
                  中カテゴリを修正・削除する
                  <span class="middle-category-manage-row">
                    <select name="manageMiddleCategoryGenreName">
                      \(genreOptions)
                    </select>
                    <select name="manageMiddleCategoryName">
                      \(middleCategoryOptions)
                    </select>
                    <button id="editMiddleCategoryButton" type="button">修正</button>
                    <button type="submit" formmethod="post" formaction="/delete-middle-category" onclick="return confirm('本当に削除しますか？');">削除</button>
                  </span>
                </span>
                <span class="category-action-block category-add-block">
                  小カテゴリを紐づける大カテゴリ・中カテゴリを選んで追加する
                  <span class="small-category-add-row">
                    <select name="smallCategoryGenreName">
                      \(genreOptions)
                    </select>
                    <select name="smallCategoryMiddleCategoryName">
                      \(middleCategoryOptions)
                    </select>
                    <input name="newSmallCategoryName" value="" placeholder="例: 利益計算 / 仕入れ / 出品">
                    <button id="addSmallCategoryButton" type="button">追加</button>
                  </span>
                </span>
                <span class="category-action-block">
                  小カテゴリを修正・削除する
                  <span class="small-category-manage-row">
                    <select name="manageSmallCategoryGenreName">
                      \(genreOptions)
                    </select>
                    <select name="manageSmallCategoryMiddleCategoryName">
                      \(middleCategoryOptions)
                    </select>
                    <select name="manageSmallCategoryName">
                      \(smallCategoryOptions)
                    </select>
                    <button id="editSmallCategoryButton" type="button">修正</button>
                    <button type="submit" formmethod="post" formaction="/delete-small-category" onclick="return confirm('本当に削除しますか？');">削除</button>
                  </span>
                </span>
                <span id="categoryEditPanelMount">\(categoryEditPanel)</span>
              </label>
            </div>
            <div class="actions">
              <button class="primary" type="submit">\(submitTitle)</button>
              \(resetLink)
            </div>
          </form>
        </section>
        """
    }

    private func renderExplanationImageInputs(for balloon: BalloonProfile) -> String {
        (1...8).map { index in
            let value = balloon.explanationImageDataURLs[safe: index - 1] ?? ""
            return "<input id=\"explanationImageDataURLInput\(index)\" type=\"hidden\" name=\"explanationImageDataURL\(index)\" value=\"\(value.htmlEscaped)\">"
        }.joined(separator: "\n")
    }

    private func renderExplanationImageControls(for balloon: BalloonProfile) -> String {
        (1...8).map { index in
            let hasImage = balloon.explanationImageDataURLs[safe: index - 1]?.nilIfEmpty != nil
            let status = hasImage ? "添付済み" : "未添付"
            let itemClass = hasImage ? "explanation-image-item attached" : "explanation-image-item"
            return """
            <span class="\(itemClass)" id="explanationImageItem\(index)">
              <span class="explanation-image-title">
                画像\(index)
                <span class="explanation-image-title-actions">
                  <button id="explanationImageCheckButton\(index)" class="button image-check-button" type="button" \(hasImage ? "" : "disabled")>画像確認</button>
                  <small id="explanationImageStatus\(index)">\(status)</small>
                </span>
              </span>
              <input id="explanationImageFileInput\(index)" type="file" accept="image/*">
              <button id="removeExplanationImageDataInput\(index)" class="button danger image-remove-button" type="button" data-remove-attachment \(hasImage ? "" : "disabled")>この画像を削除</button>
            </span>
            """
        }.joined(separator: "\n")
    }

    private func renderPositionControl(title: String, xName: String, yName: String) -> String {
        """
        <div class="position-control">
          <div class="font-control-head">
            <span>\(title)</span>
            <span class="font-size-display" data-position-display data-position-x="\(xName)" data-position-y="\(yName)"></span>
          </div>
          <div class="position-pad" aria-label="\(title)">
            <span></span>
            <button class="position-step" type="button" data-position-target="\(yName)" data-position-delta="-0.05" aria-label="\(title)を上へ">↑</button>
            <span></span>
            <button class="position-step" type="button" data-position-target="\(xName)" data-position-delta="-0.05" aria-label="\(title)を左へ">←</button>
            <button class="position-reset" type="button" data-position-reset="true" data-position-x="\(xName)" data-position-y="\(yName)" aria-label="\(title)を中央へ">中央</button>
            <button class="position-step" type="button" data-position-target="\(xName)" data-position-delta="0.05" aria-label="\(title)を右へ">→</button>
            <span></span>
            <button class="position-step" type="button" data-position-target="\(yName)" data-position-delta="0.05" aria-label="\(title)を下へ">↓</button>
            <span></span>
          </div>
        </div>
        """
    }

    private func renderListPanel(
        itemNumberSearch: String?,
        listSort: String?,
        genreFilter: String?,
        middleCategoryFilter: String?,
        smallCategoryFilter: String?,
        favoriteFilter: String?
    ) -> String {
        let operationStatus = settings.isPaused ? "停止中" : "稼働中"
        let enabledCount = settings.enabledBalloons.count
        let searchValue = itemNumberSearch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedSort = normalizedListSort(listSort)
        let selectedGenreFilter = normalizedListFilterValue(genreFilter)
        let selectedMiddleCategoryFilter = normalizedListFilterValue(middleCategoryFilter)
        let selectedSmallCategoryFilter = normalizedListFilterValue(smallCategoryFilter)
        let selectedFavoriteFilter = normalizedFavoriteFilter(favoriteFilter)
        let sortOptions = renderListSortOptions(selectedSort: selectedSort)
        let favoriteOptions = renderFavoriteFilterOptions(selectedFavoriteFilter: selectedFavoriteFilter)
        let genreFilterOptions = renderListGenreFilterOptions(selectedName: selectedGenreFilter)
        let middleCategoryFilterOptions = renderListMiddleCategoryFilterOptions(
            selectedName: selectedMiddleCategoryFilter,
            selectedGenreName: selectedGenreFilter
        )
        let smallCategoryFilterOptions = renderListSmallCategoryFilterOptions(
            selectedName: selectedSmallCategoryFilter,
            selectedGenreName: selectedGenreFilter,
            selectedMiddleCategoryName: selectedMiddleCategoryFilter
        )
        let listReturnPath = listReturnPath(
            itemNumberSearch: searchValue,
            listSort: selectedSort,
            genreFilter: selectedGenreFilter,
            middleCategoryFilter: selectedMiddleCategoryFilter,
            smallCategoryFilter: selectedSmallCategoryFilter,
            favoriteFilter: selectedFavoriteFilter
        )
        let resumeAllButton = settings.balloons.isEmpty
            ? "<span class=\"button disabled-control\">全風船を再開</span>"
            : "<a class=\"button primary\" href=\"\(listActionPath("/resume-all-balloons", returnTo: listReturnPath))\">全風船を再開</a>"
        let stopAllButton = settings.balloons.isEmpty
            ? "<span class=\"button disabled-control\">全風船を停止</span>"
            : "<a class=\"button danger\" href=\"\(listActionPath("/toggle-all-balloons", items: [URLQueryItem(name: "enabled", value: "0")], returnTo: listReturnPath))\">全風船を停止</a>"

        return """
        <section class="panel">
          <div class="panel-heading">
            <div>
              <h2>作成した風船一覧</h2>
              <p class="heading-meta">全体状態: \(operationStatus) / 稼働中の風船: \(enabledCount)件</p>
            </div>
            <div class="actions">
              \(resumeAllButton)
              \(stopAllButton)
            </div>
          </div>
          <form class="list-filter" action="/" method="get">
            <input type="hidden" name="tab" value="list">
            <label class="keyword-filter">
              タイトルキーワード入力欄
              <input name="itemNumberSearch" value="\(searchValue.htmlEscaped)" placeholder="例: 12 / LESPORTSAC / 起きてない">
            </label>
            <label>
              大カテゴリ
              <select name="listGenreFilter">
                \(genreFilterOptions)
              </select>
            </label>
            <label>
              中カテゴリ
              <select name="listMiddleCategoryFilter">
                \(middleCategoryFilterOptions)
              </select>
            </label>
            <label>
              小カテゴリ
              <select name="listSmallCategoryFilter">
                \(smallCategoryFilterOptions)
              </select>
            </label>
            <label>
              並び順
              <select name="listSort">
                \(sortOptions)
              </select>
            </label>
            <label>
              お気に入り
              <select name="listFavoriteFilter">
                \(favoriteOptions)
              </select>
            </label>
            <button type="submit">検索</button>
            <a id="clearListFilters" class="button" href="/?tab=list">クリア</a>
          </form>
          \(renderBalloonList(
            itemNumberSearch: searchValue,
            listSort: selectedSort,
            genreFilter: selectedGenreFilter,
            middleCategoryFilter: selectedMiddleCategoryFilter,
            smallCategoryFilter: selectedSmallCategoryFilter,
            favoriteFilter: selectedFavoriteFilter,
            listReturnPath: listReturnPath
          ))
        </section>
        """
    }

    private func listReturnPath(
        itemNumberSearch: String,
        listSort: String,
        genreFilter: String,
        middleCategoryFilter: String,
        smallCategoryFilter: String,
        favoriteFilter: String
    ) -> String {
        var items = [URLQueryItem(name: "tab", value: "list")]
        if !itemNumberSearch.isEmpty {
            items.append(URLQueryItem(name: "itemNumberSearch", value: itemNumberSearch))
        }
        if !genreFilter.isEmpty {
            items.append(URLQueryItem(name: "listGenreFilter", value: genreFilter))
        }
        if !middleCategoryFilter.isEmpty {
            items.append(URLQueryItem(name: "listMiddleCategoryFilter", value: middleCategoryFilter))
        }
        if !smallCategoryFilter.isEmpty {
            items.append(URLQueryItem(name: "listSmallCategoryFilter", value: smallCategoryFilter))
        }
        if listSort != "category" {
            items.append(URLQueryItem(name: "listSort", value: listSort))
        }
        if !favoriteFilter.isEmpty {
            items.append(URLQueryItem(name: "listFavoriteFilter", value: favoriteFilter))
        }
        return appendingQueryItems(to: "/", items: items)
    }

    private func listActionPath(_ path: String, items: [URLQueryItem] = [], returnTo: String) -> String {
        let basePath = appendingQueryItems(to: path, items: items)
        let separator = basePath.contains("?") ? "&" : "?"
        return "\(basePath)\(separator)returnTo=\(returnTo.urlQueryEscaped)"
    }

    private func normalizedListFilterValue(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func normalizedFavoriteFilter(_ value: String?) -> String {
        value == "favorite" ? "favorite" : ""
    }

    private func normalizedListSort(_ value: String?) -> String {
        switch value ?? "category" {
        case "itemAsc", "itemDesc":
            return value ?? "category"
        default:
            return "category"
        }
    }

    private func renderListSortOptions(selectedSort: String) -> String {
        [
            ("category", "カテゴリ別"),
            ("itemAsc", "品番 昇順"),
            ("itemDesc", "品番 降順")
        ].map { value, label in
            let selected = value == selectedSort ? " selected" : ""
            return "<option value=\"\(value)\"\(selected)>\(label)</option>"
        }.joined(separator: "\n")
    }

    private func renderFavoriteFilterOptions(selectedFavoriteFilter: String) -> String {
        [
            ("", "すべて"),
            ("favorite", "お気に入りのみ")
        ].map { value, label in
            let selected = value == selectedFavoriteFilter ? " selected" : ""
            return "<option value=\"\(value)\"\(selected)>\(label)</option>"
        }.joined(separator: "\n")
    }

    private func renderListGenreFilterOptions(selectedName: String) -> String {
        var genreNames = Set(settings.balloons.map {
            $0.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        })
        genreNames.insert("未分類")

        let options = genreNames.sorted { lhs, rhs in
            if lhs == "未分類" { return true }
            if rhs == "未分類" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }.map { genreName in
            let selected = genreName == selectedName ? " selected" : ""
            return "<option value=\"\(genreName.htmlEscaped)\"\(selected)>\(genreName.htmlEscaped)</option>"
        }.joined(separator: "\n")

        let allSelected = selectedName.isEmpty ? " selected" : ""
        return "<option value=\"\"\(allSelected)>すべて</option>\n\(options)"
    }

    private func renderListMiddleCategoryFilterOptions(selectedName: String, selectedGenreName: String) -> String {
        var categoryPairs = Set(settings.balloons.map { balloon in
            let genreName = balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let middleCategoryName = balloon.middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            return MiddleCategoryPair(genreName: genreName, middleCategoryName: middleCategoryName)
        })
        categoryPairs.insert(MiddleCategoryPair(genreName: "未分類", middleCategoryName: "未指定"))

        let options = categoryPairs.sorted { lhs, rhs in
            if lhs.middleCategoryName == rhs.middleCategoryName {
                return lhs.genreName.localizedStandardCompare(rhs.genreName) == .orderedAscending
            }
            if lhs.middleCategoryName == "未指定" { return true }
            if rhs.middleCategoryName == "未指定" { return false }
            return lhs.middleCategoryName.localizedStandardCompare(rhs.middleCategoryName) == .orderedAscending
        }.map { pair in
            let isVisible = selectedGenreName.isEmpty || pair.genreName == selectedGenreName
            let selected = isVisible && pair.middleCategoryName == selectedName ? " selected" : ""
            let hidden = isVisible ? "" : " hidden disabled"
            return "<option value=\"\(pair.middleCategoryName.htmlEscaped)\" data-genre=\"\(pair.genreName.htmlEscaped)\"\(selected)\(hidden)>\(pair.middleCategoryName.htmlEscaped)</option>"
        }.joined(separator: "\n")

        let hasVisibleSelection = categoryPairs.contains { pair in
            (selectedGenreName.isEmpty || pair.genreName == selectedGenreName) && pair.middleCategoryName == selectedName
        }
        let allSelected = selectedName.isEmpty || !hasVisibleSelection ? " selected" : ""
        return "<option value=\"\"\(allSelected)>すべて</option>\n\(options)"
    }

    private func renderListSmallCategoryFilterOptions(selectedName: String, selectedGenreName: String, selectedMiddleCategoryName: String) -> String {
        var categoryPairs = Set(settings.balloons.map { balloon in
            let genreName = balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let middleCategoryName = balloon.middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            let smallCategoryName = balloon.smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            return SmallCategoryPair(genreName: genreName, middleCategoryName: middleCategoryName, smallCategoryName: smallCategoryName)
        })
        categoryPairs.insert(SmallCategoryPair(genreName: "未分類", middleCategoryName: "未指定", smallCategoryName: "未指定"))

        let options = categoryPairs.sorted { lhs, rhs in
            if lhs.smallCategoryName == rhs.smallCategoryName {
                if lhs.genreName == "未分類" { return true }
                if rhs.genreName == "未分類" { return false }
                return lhs.genreName.localizedStandardCompare(rhs.genreName) == .orderedAscending
            }
            if lhs.smallCategoryName == "未指定" { return true }
            if rhs.smallCategoryName == "未指定" { return false }
            return lhs.smallCategoryName.localizedStandardCompare(rhs.smallCategoryName) == .orderedAscending
        }.map { pair in
            let isVisible = (selectedGenreName.isEmpty || pair.genreName == selectedGenreName)
                && (selectedMiddleCategoryName.isEmpty || pair.middleCategoryName == selectedMiddleCategoryName)
            let selected = isVisible && pair.smallCategoryName == selectedName ? " selected" : ""
            let hidden = isVisible ? "" : " hidden disabled"
            return "<option value=\"\(pair.smallCategoryName.htmlEscaped)\" data-genre=\"\(pair.genreName.htmlEscaped)\" data-middle-category=\"\(pair.middleCategoryName.htmlEscaped)\"\(selected)\(hidden)>\(pair.smallCategoryName.htmlEscaped)</option>"
        }.joined(separator: "\n")

        let hasVisibleSelection = categoryPairs.contains { pair in
            (selectedGenreName.isEmpty || pair.genreName == selectedGenreName)
                && (selectedMiddleCategoryName.isEmpty || pair.middleCategoryName == selectedMiddleCategoryName)
                && pair.smallCategoryName == selectedName
        }
        let allSelected = selectedName.isEmpty || !hasVisibleSelection ? " selected" : ""
        return "<option value=\"\"\(allSelected)>すべて</option>\n\(options)"
    }

    private func messageText(for message: String) -> String {
        switch message {
        case "shown":
            return "表示しました"
        case "paused":
            return "一時停止しました"
        case "resumed":
            return "再開しました"
        case "saved":
            return "保存しました"
        case "deleted":
            return "削除しました"
        case "updated":
            return "更新しました"
        case "allStopped":
            return "全商品を停止しました"
        case "allRestored":
            return "全商品停止前の状態に戻しました"
        case "allResumed":
            return "全風船を再開しました"
        case "genreStopped":
            return "大カテゴリ内の商品を停止しました"
        case "genreRestored":
            return "大カテゴリ内の商品停止を解除しました"
        case "genreResumed":
            return "大カテゴリ内の商品を再開しました"
        case "middleCategoryStopped":
            return "中カテゴリ内の商品を停止しました"
        case "middleCategoryRestored":
            return "中カテゴリ内の商品停止を解除しました"
        case "middleCategoryResumed":
            return "中カテゴリ内の商品を再開しました"
        case "smallCategoryStopped":
            return "小カテゴリ内の商品を停止しました"
        case "smallCategoryRestored":
            return "小カテゴリ内の商品停止を解除しました"
        case "smallCategoryResumed":
            return "小カテゴリ内の商品を再開しました"
        case "launchPositionUpdated":
            return "風船が這い上がる場所と上昇スピードを更新しました"
        case "categoryUpdated":
            return "カテゴリを修正しました"
        case "categoryDeleted":
            return "カテゴリを削除しました"
        default:
            return message.htmlEscaped
        }
    }

    private func renderCategoryEditPanel(
        editGenreName: String?,
        editMiddleCategoryGenreName: String?,
        editMiddleCategoryName: String?,
        editSmallCategoryGenreName: String?,
        editSmallCategoryMiddleCategoryName: String?,
        editSmallCategoryName: String?
    ) -> String {
        if let editGenreName = editGenreName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return """
            <span class="category-edit-panel">
              <strong>大カテゴリ名を修正</strong>
              <p>選択中: \(editGenreName.htmlEscaped)</p>
              <span class="category-edit-actions">
                <input name="renamedGenreName" value="\(editGenreName.htmlEscaped)" placeholder="修正後の大カテゴリ名">
                <button type="submit" formmethod="post" formaction="/rename-genre?targetGenreName=\(editGenreName.urlQueryEscaped)">保存</button>
                <a class="button" href="/?tab=create">キャンセル</a>
              </span>
            </span>
            """
        }

        if let editMiddleCategoryGenreName = editMiddleCategoryGenreName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           let editMiddleCategoryName = editMiddleCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return """
            <span class="category-edit-panel">
              <strong>中カテゴリ名を修正</strong>
              <p>大カテゴリ: \(editMiddleCategoryGenreName.htmlEscaped) / 中カテゴリ: \(editMiddleCategoryName.htmlEscaped)</p>
              <span class="category-edit-actions">
                <input name="renamedMiddleCategoryName" value="\(editMiddleCategoryName.htmlEscaped)" placeholder="修正後の中カテゴリ名">
                <button type="submit" formmethod="post" formaction="/rename-middle-category?targetMiddleCategoryGenreName=\(editMiddleCategoryGenreName.urlQueryEscaped)&targetMiddleCategoryName=\(editMiddleCategoryName.urlQueryEscaped)">保存</button>
                <a class="button" href="/?tab=create">キャンセル</a>
              </span>
            </span>
            """
        }

        if let editSmallCategoryGenreName = editSmallCategoryGenreName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           let editSmallCategoryName = editSmallCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            let editSmallCategoryMiddleCategoryName = editSmallCategoryMiddleCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return """
            <span class="category-edit-panel">
              <strong>小カテゴリ名を修正</strong>
              <p>大カテゴリ: \(editSmallCategoryGenreName.htmlEscaped) / 中カテゴリ: \((editSmallCategoryMiddleCategoryName.nilIfEmpty ?? "未指定").htmlEscaped) / 小カテゴリ: \(editSmallCategoryName.htmlEscaped)</p>
              <span class="category-edit-actions">
                <input name="renamedSmallCategoryName" value="\(editSmallCategoryName.htmlEscaped)" placeholder="修正後の小カテゴリ名">
                <button type="submit" formmethod="post" formaction="/rename-small-category?targetSmallCategoryGenreName=\(editSmallCategoryGenreName.urlQueryEscaped)&targetSmallCategoryMiddleCategoryName=\(editSmallCategoryMiddleCategoryName.urlQueryEscaped)&targetSmallCategoryName=\(editSmallCategoryName.urlQueryEscaped)">保存</button>
                <a class="button" href="/?tab=create">キャンセル</a>
              </span>
            </span>
            """
        }

        return ""
    }

    private func renderGenreOptions(selectedName: String) -> String {
        var genreNames = Set(settings.balloons.map {
            $0.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        })
        genreNames.insert(selectedName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類")
        genreNames.insert("未分類")

        return genreNames.sorted { lhs, rhs in
            if lhs == "未分類" { return true }
            if rhs == "未分類" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }.map { genreName in
            let selected = genreName == selectedName ? " selected" : ""
            return "<option value=\"\(genreName.htmlEscaped)\"\(selected)>\(genreName.htmlEscaped)</option>"
        }.joined(separator: "\n")
    }

    private func renderMiddleCategoryOptions(selectedName: String, selectedGenreName: String) -> String {
        let normalizedSelectedGenreName = selectedGenreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        var categoryPairs = Set(settings.balloons.compactMap { balloon -> MiddleCategoryPair? in
            guard let middleCategoryName = balloon.middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
                return nil
            }
            let genreName = balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            return MiddleCategoryPair(genreName: genreName, middleCategoryName: middleCategoryName)
        })
        if let selectedName = selectedName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            categoryPairs.insert(MiddleCategoryPair(genreName: normalizedSelectedGenreName, middleCategoryName: selectedName))
        }

        let selectedEmpty = selectedName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil ? " selected" : ""
        let options = categoryPairs.sorted {
            if $0.genreName == $1.genreName {
                return $0.middleCategoryName.localizedStandardCompare($1.middleCategoryName) == .orderedAscending
            }
            if $0.genreName == "未分類" { return true }
            if $1.genreName == "未分類" { return false }
            return $0.genreName.localizedStandardCompare($1.genreName) == .orderedAscending
        }.map { pair in
            let selected = pair.genreName == normalizedSelectedGenreName && pair.middleCategoryName == selectedName ? " selected" : ""
            return "<option value=\"\(pair.middleCategoryName.htmlEscaped)\" data-genre=\"\(pair.genreName.htmlEscaped)\"\(selected)>\(pair.middleCategoryName.htmlEscaped)</option>"
        }.joined(separator: "\n")

        return "<option value=\"\"\(selectedEmpty)>未指定</option>\n\(options)"
    }

    private func renderSmallCategoryOptions(selectedName: String, selectedGenreName: String, selectedMiddleCategoryName: String) -> String {
        let normalizedSelectedGenreName = selectedGenreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let normalizedSelectedMiddleCategoryName = selectedMiddleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        var categoryPairs = Set(settings.balloons.compactMap { balloon -> SmallCategoryPair? in
            guard let smallCategoryName = balloon.smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
                return nil
            }
            let genreName = balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let middleCategoryName = balloon.middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            return SmallCategoryPair(genreName: genreName, middleCategoryName: middleCategoryName, smallCategoryName: smallCategoryName)
        })
        if let selectedName = selectedName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            categoryPairs.insert(SmallCategoryPair(genreName: normalizedSelectedGenreName, middleCategoryName: normalizedSelectedMiddleCategoryName, smallCategoryName: selectedName))
        }

        let selectedEmpty = selectedName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil ? " selected" : ""
        let options = categoryPairs.sorted {
            if $0.genreName == $1.genreName, $0.middleCategoryName == $1.middleCategoryName {
                return $0.smallCategoryName.localizedStandardCompare($1.smallCategoryName) == .orderedAscending
            }
            if $0.genreName == $1.genreName {
                return $0.middleCategoryName.localizedStandardCompare($1.middleCategoryName) == .orderedAscending
            }
            if $0.genreName == "未分類" { return true }
            if $1.genreName == "未分類" { return false }
            return $0.genreName.localizedStandardCompare($1.genreName) == .orderedAscending
        }.map { pair in
            let selected = pair.genreName == normalizedSelectedGenreName
                && pair.middleCategoryName == normalizedSelectedMiddleCategoryName
                && pair.smallCategoryName == selectedName ? " selected" : ""
            return "<option value=\"\(pair.smallCategoryName.htmlEscaped)\" data-genre=\"\(pair.genreName.htmlEscaped)\" data-middle-category=\"\(pair.middleCategoryName.htmlEscaped)\"\(selected)>\(pair.smallCategoryName.htmlEscaped)</option>"
        }.joined(separator: "\n")

        return "<option value=\"\"\(selectedEmpty)>未指定</option>\n\(options)"
    }

    private func renderColorOptions(selectedName: String, customBalloonDesignDataURL: String?, customBalloonDesignScale: Double) -> String {
        let colorOptions = OverlaySettings.colorOptions.map { option in
            let checked = option.name == selectedName ? " checked" : ""
            return """
            <label class="swatch" title="\(option.name.htmlEscaped)">
              <input type="radio" name="colorName" value="\(option.name.htmlEscaped)" data-start-hex="\(option.startHex.htmlEscaped)" data-end-hex="\(option.endHex.htmlEscaped)"\(checked)>
              <span style="background: linear-gradient(135deg, \(option.startHex), \(option.endHex));"></span>
            </label>
            """
        }.joined(separator: "\n")

        let customBalloonDesignDataURL = customBalloonDesignDataURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let customChecked = selectedName == OverlaySettings.customBalloonDesignName && !customBalloonDesignDataURL.isEmpty ? " checked" : ""
        let customDisabled = customBalloonDesignDataURL.isEmpty ? " disabled" : ""
        let customThumbnail = customBalloonDesignDataURL.isEmpty
            ? "自作"
            : "<img src=\"\(customBalloonDesignDataURL.htmlEscaped)\" alt=\"自作風船\">"
        let customToolsHidden = customBalloonDesignDataURL.isEmpty ? " hidden" : ""
        let customScalePercent = String(format: "%.0f", customBalloonDesignScale * 100)
        let customOption = """
        <span class="custom-design-slot" title="自作風船デザイン">
          <label class="swatch custom-design-swatch">
            <input id="customBalloonDesignRadio" type="radio" name="colorName" value="\(OverlaySettings.customBalloonDesignName.htmlEscaped)"\(customChecked)\(customDisabled)>
            <span id="customBalloonDesignThumbnail" class="custom-design-thumbnail">\(customThumbnail)</span>
          </label>
          <button id="customBalloonDesignUploadButton" class="custom-design-upload" type="button" title="自作風船画像を登録">+</button>
          <input id="customBalloonDesignFileInput" type="file" accept="image/*">
        </span>
        <span id="customBalloonDesignTools" class="custom-design-tools"\(customToolsHidden)>
          自作風船サイズ
          <button id="customBalloonDesignScaleDownButton" class="custom-design-size-button" type="button" title="自作風船を小さくする">-</button>
          <output id="customBalloonDesignScaleValue" class="custom-design-scale-value">\(customScalePercent)%</output>
          <button id="customBalloonDesignScaleUpButton" class="custom-design-size-button" type="button" title="自作風船を大きくする">+</button>
        </span>
        """

        return "\(colorOptions)\n\(customOption)"
    }

    private func renderPositionOptions(selectedName: String) -> String {
        OverlaySettings.positionOptions.map { option in
            let checked = option.name == selectedName ? " checked" : ""
            return """
            <label class="segment">
              <input type="radio" name="positionName" value="\(option.name.htmlEscaped)"\(checked)>
              <span>\(option.name.htmlEscaped)</span>
            </label>
            """
        }.joined(separator: "\n")
    }

    private func renderSelectPositionOptions(selectedName: String) -> String {
        OverlaySettings.positionOptions.map { option in
            let selected = option.name == selectedName ? " selected" : ""
            return "<option value=\"\(option.name.htmlEscaped)\"\(selected)>\(option.name.htmlEscaped)</option>"
        }.joined(separator: "\n")
    }

    private func renderSizeOptions(selectedName: String) -> String {
        OverlaySettings.sizeOptions.map { option in
            let checked = option.name == selectedName ? " checked" : ""
            return """
            <label class="segment">
              <input type="radio" name="sizeName" value="\(option.name.htmlEscaped)"\(checked)>
              <span>\(option.name.htmlEscaped)</span>
            </label>
            """
        }.joined(separator: "\n")
    }

    private func renderPreviewContent(imageDataURL: String, imageName: String, text: String) -> String {
        if !imageDataURL.isEmpty {
            let caption = text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? imageName.trimmingCharacters(in: .whitespacesAndNewlines)
            let captionHTML = caption.isEmpty ? "" : "<span class=\"preview-content preview-image-caption\">\(caption.htmlEscaped)</span>"
            let captionLineCount = max(1, caption.split(whereSeparator: \.isNewline).count)
            let captionClass = caption.isEmpty
                ? ""
                : " has-caption\(captionLineCount > 2 ? " many-caption-lines" : "")"
            return "<span class=\"preview-image-stack\(captionClass)\">\(captionHTML)<img src=\"\(imageDataURL.htmlEscaped)\" alt=\"\"></span>"
        }
        return text.htmlEscaped
    }

    private func formatFontSize(_ value: Double) -> String {
        value > 0 ? String(format: "%.0f", value) : "0"
    }

    private func formatCustomBalloonDesignScale(_ value: Double) -> String {
        String(format: "%.1f", min(max(value, 0.5), 2.5))
    }

    private func formatImageScale(_ value: Double) -> String {
        String(format: "%.1f", min(max(value, 0.6), 2.0))
    }

    private func formatPositionOffset(_ value: Double) -> String {
        String(format: "%.2f", min(max(value, -0.45), 0.45))
    }

    private func previewScale(for sizeName: String) -> Double {
        OverlaySettings.sizeOptions.first(where: { $0.name == sizeName })?.scale ?? 1.0
    }

    private func previewTextFontSize(for balloon: BalloonProfile, large: Bool) -> String {
        if balloon.textFontSize > 0 {
            return String(format: "%.0f", balloon.textFontSize * (large ? 2.0 : 1.0))
        }
        return large ? "78" : "26"
    }

    private func previewTextFontSize(for balloon: BalloonProfile) -> String {
        if balloon.textFontSize > 0 {
            return String(format: "%.0f", balloon.textFontSize * previewScale(for: balloon.sizeName))
        }
        let scale = previewScale(for: balloon.sizeName)
        let baseSize = scale > 1 ? 39.0 : 26.0
        return String(format: "%.0f", baseSize * scale)
    }

    private func previewImageCaptionFontSize(for balloon: BalloonProfile, large: Bool) -> String {
        if balloon.textFontSize > 0 {
            return String(format: "%.0f", balloon.textFontSize * (large ? 2.0 : 1.0))
        }
        return large ? "24" : "12"
    }

    private func previewImageCaptionFontSize(for balloon: BalloonProfile) -> String {
        if balloon.textFontSize > 0 {
            return String(format: "%.0f", balloon.textFontSize * previewScale(for: balloon.sizeName))
        }
        return String(format: "%.0f", 12 * previewScale(for: balloon.sizeName))
    }

    private func frontDisplayText(for balloon: BalloonProfile) -> String {
        balloon.text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? balloon.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "🎈"
    }

    private func frontTextInputValue(for balloon: BalloonProfile) -> String {
        let text = balloon.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.nilIfEmpty != nil, text != "🎈" {
            return text
        }

        if balloon.imageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil,
           let legacyImageCaption = balloon.imageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return legacyImageCaption
        }

        return text == "🎈" ? "" : text
    }

    private func backTextInputValue(for balloon: BalloonProfile) -> String {
        let text = balloon.backText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.nilIfEmpty != nil {
            return text
        }

        if balloon.backImageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil,
           let legacyImageCaption = balloon.backImageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return legacyImageCaption
        }

        return text
    }

    private func titleText(for balloon: BalloonProfile) -> String {
        balloon.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? frontDisplayText(for: balloon)
    }

    private func categorySummary(for balloon: BalloonProfile) -> String {
        let largeCategory = balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let middleCategory = balloon.middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let smallCategory = balloon.smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let smallCategory {
            return "大カテゴリ \(largeCategory) / 中カテゴリ \(middleCategory ?? "未指定") / 小カテゴリ \(smallCategory)"
        }
        if let middleCategory {
            return "大カテゴリ \(largeCategory) / 中カテゴリ \(middleCategory)"
        }
        return "大カテゴリ \(largeCategory)"
    }

    private func listCategorySummary(for balloon: BalloonProfile) -> String {
        balloon.smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? balloon.middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "未分類"
    }

    private func backSideSummary(for balloon: BalloonProfile) -> String {
        if balloon.backImageDataURL?.isEmpty == false {
            return "添付画像あり"
        }
        if let backImageName = balloon.backImageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return "Assets画像: \(backImageName)"
        }
        if let backText = balloon.backText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return backText
        }
        return "なし"
    }

    private func hasBackSide(_ balloon: BalloonProfile) -> Bool {
        balloon.backText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
            || balloon.backImageName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
            || balloon.backImageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
    }

    private func renderBalloonList(
        itemNumberSearch: String,
        listSort: String,
        genreFilter: String,
        middleCategoryFilter: String,
        smallCategoryFilter: String,
        favoriteFilter: String,
        listReturnPath: String
    ) -> String {
        let balloons = filteredBalloons(
            itemNumberSearch: itemNumberSearch,
            genreFilter: genreFilter,
            middleCategoryFilter: middleCategoryFilter,
            smallCategoryFilter: smallCategoryFilter,
            favoriteFilter: favoriteFilter
        )
        guard !balloons.isEmpty else {
            return itemNumberSearch.isEmpty && genreFilter.isEmpty && middleCategoryFilter.isEmpty && smallCategoryFilter.isEmpty && favoriteFilter.isEmpty
                ? "<p class=\"empty\">まだ風船がありません。</p>"
                : "<p class=\"empty\">条件に一致する風船がありません。</p>"
        }

        if listSort == "itemAsc" || listSort == "itemDesc" {
            return """
            <div class="list">
            \(renderBalloonItemNumberList(balloons: balloons, ascending: listSort == "itemAsc", listReturnPath: listReturnPath))
            </div>
            """
        }

        return """
        <div class="list">
        \(renderBalloonGenreGroups(balloons: balloons, listReturnPath: listReturnPath))
        </div>
        """
    }

    private func filteredBalloons(
        itemNumberSearch: String,
        genreFilter: String,
        middleCategoryFilter: String,
        smallCategoryFilter: String,
        favoriteFilter: String
    ) -> [BalloonProfile] {
        let query = itemNumberSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.localizedLowercase
        let normalizedGenreFilter = genreFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMiddleCategoryFilter = middleCategoryFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSmallCategoryFilter = smallCategoryFilter.trimmingCharacters(in: .whitespacesAndNewlines)

        return settings.balloons.filter { balloon in
            let genreName = balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let middleCategoryName = balloon.middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            let smallCategoryName = balloon.smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            let matchesKeyword = query.isEmpty
                || "\(balloon.itemNumber)".contains(query)
                || balloon.title.localizedLowercase.contains(normalizedQuery)
            let matchesGenre = normalizedGenreFilter.isEmpty || genreName == normalizedGenreFilter
            let matchesMiddleCategory = normalizedMiddleCategoryFilter.isEmpty || middleCategoryName == normalizedMiddleCategoryFilter
            let matchesSmallCategory = normalizedSmallCategoryFilter.isEmpty || smallCategoryName == normalizedSmallCategoryFilter
            let matchesFavorite = favoriteFilter != "favorite" || balloon.isFavorite

            return matchesKeyword && matchesGenre && matchesMiddleCategory && matchesSmallCategory && matchesFavorite
        }
    }

    private func renderBalloonItemNumberList(balloons sourceBalloons: [BalloonProfile], ascending: Bool, listReturnPath: String) -> String {
        let sortedBalloons = sourceBalloons.sorted { lhs, rhs in
            if lhs.itemNumber == rhs.itemNumber {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return ascending ? lhs.itemNumber < rhs.itemNumber : lhs.itemNumber > rhs.itemNumber
        }

        var previousGenreName: String?
        var previousMiddleCategoryName: String?
        var previousSmallCategoryName: String?
        var rows: [String] = []

        sortedBalloons.forEach { balloon in
            let genreName = balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            let middleCategoryName = balloon.middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
            let smallCategoryName = balloon.smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"

            if genreName != previousGenreName {
                rows.append(renderItemNumberGenreHeading(genreName))
                previousGenreName = genreName
                previousMiddleCategoryName = nil
                previousSmallCategoryName = nil
            }
            if middleCategoryName != previousMiddleCategoryName {
                rows.append(renderItemNumberMiddleCategoryHeading(middleCategoryName))
                previousMiddleCategoryName = middleCategoryName
                previousSmallCategoryName = nil
            }
            if smallCategoryName != previousSmallCategoryName {
                rows.append(renderItemNumberSmallCategoryHeading(genreName: genreName, smallCategoryName: smallCategoryName))
                previousSmallCategoryName = smallCategoryName
            }

            rows.append(renderBalloonListItem(balloon, listReturnPath: listReturnPath))
        }

        return rows.joined(separator: "\n")
    }

    private func renderItemNumberGenreHeading(_ genreName: String) -> String {
        """
        <div class="genre-heading item-number-category-heading">
          <h3 class="genre-title-pill">大カテゴリ: \(genreName.htmlEscaped)</h3>
        </div>
        """
    }

    private func renderItemNumberMiddleCategoryHeading(_ middleCategoryName: String) -> String {
        """
        <div class="middle-category-heading item-number-category-heading">
          <h4>中カテゴリ: \(middleCategoryName.htmlEscaped)</h4>
        </div>
        """
    }

    private func renderItemNumberSmallCategoryHeading(genreName: String, smallCategoryName: String) -> String {
        let headingClass = smallCategoryHeadingClass(for: genreName, smallCategoryName: smallCategoryName)
        return """
        <div class="\(headingClass) item-number-category-heading">
          <h4>小カテゴリ: \(smallCategoryName.htmlEscaped)</h4>
        </div>
        """
    }

    private func renderBalloonGenreGroups(balloons sourceBalloons: [BalloonProfile], listReturnPath: String) -> String {
        let groupedBalloons = Dictionary(grouping: sourceBalloons.reversed()) { balloon in
            balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        }
        let genreNames = groupedBalloons.keys.sorted { lhs, rhs in
            if lhs == "未分類" { return false }
            if rhs == "未分類" { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        return genreNames.map { genreName in
            let balloons = groupedBalloons[genreName] ?? []
            let enabledCount = balloons.filter(\.isEnabled).count
            let resumeGenreButton = balloons.isEmpty
                ? "<span class=\"button disabled-control\">風船を再開</span>"
                : "<a class=\"button primary\" href=\"\(listActionPath("/resume-genre-balloons", items: [URLQueryItem(name: "genre", value: genreName)], returnTo: listReturnPath))\">風船を再開</a>"
            let stopGenreButton = balloons.isEmpty
                ? "<span class=\"button disabled-control\">風船を停止</span>"
                : "<a class=\"button danger\" href=\"\(listActionPath("/toggle-genre-balloons", items: [URLQueryItem(name: "genre", value: genreName), URLQueryItem(name: "enabled", value: "0")], returnTo: listReturnPath))\">風船を停止</a>"
            return """
            <section class="genre-group">
              <div class="genre-heading">
                <h3 class="genre-title-pill">大カテゴリ: \(genreName.htmlEscaped)</h3>
                <div class="genre-actions">
                  <span class="genre-count">\(balloons.count)件 / 稼働中 \(enabledCount)件</span>
                  \(resumeGenreButton)
                  \(stopGenreButton)
                </div>
              </div>
              \(renderBalloonMiddleCategoryGroups(balloons: balloons, genreName: genreName, listReturnPath: listReturnPath))
            </section>
            """
        }.joined(separator: "\n")
    }

    private func renderBalloonMiddleCategoryGroups(balloons: [BalloonProfile], genreName: String, listReturnPath: String) -> String {
        let groupedBalloons = Dictionary(grouping: balloons) { balloon in
            balloon.middleCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
        }
        let middleCategoryNames = groupedBalloons.keys.sorted { lhs, rhs in
            if lhs == "未指定" { return false }
            if rhs == "未指定" { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        return middleCategoryNames.map { middleCategoryName in
            let middleCategoryBalloons = groupedBalloons[middleCategoryName] ?? []
            let enabledCount = middleCategoryBalloons.filter(\.isEnabled).count
            let resumeMiddleCategoryButton = "<a class=\"button primary\" href=\"\(listActionPath("/resume-middle-category-balloons", items: [URLQueryItem(name: "genre", value: genreName), URLQueryItem(name: "middleCategory", value: middleCategoryName)], returnTo: listReturnPath))\">風船を再開</a>"
            let stopMiddleCategoryButton = "<a class=\"button danger\" href=\"\(listActionPath("/toggle-middle-category-balloons", items: [URLQueryItem(name: "genre", value: genreName), URLQueryItem(name: "middleCategory", value: middleCategoryName), URLQueryItem(name: "enabled", value: "0")], returnTo: listReturnPath))\">風船を停止</a>"
            return """
            <section class="middle-category-group">
              <div class="middle-category-heading">
                <h4>中カテゴリ: \(middleCategoryName.htmlEscaped)</h4>
                <div class="middle-category-actions">
                  <span class="middle-category-count">\(middleCategoryBalloons.count)件 / 稼働中 \(enabledCount)件</span>
                  \(resumeMiddleCategoryButton)
                  \(stopMiddleCategoryButton)
                </div>
              </div>
              \(renderBalloonSmallCategoryGroups(balloons: middleCategoryBalloons, genreName: genreName, middleCategoryName: middleCategoryName, listReturnPath: listReturnPath))
            </section>
            """
        }.joined(separator: "\n")
    }

    private func renderBalloonSmallCategoryGroups(balloons: [BalloonProfile], genreName: String, middleCategoryName: String, listReturnPath: String) -> String {
        let groupedBalloons = Dictionary(grouping: balloons) { balloon in
            balloon.smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未指定"
        }
        let smallCategoryNames = groupedBalloons.keys.sorted { lhs, rhs in
            if lhs == "未指定" { return false }
            if rhs == "未指定" { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        return smallCategoryNames.map { smallCategoryName in
            let smallCategoryBalloons = groupedBalloons[smallCategoryName] ?? []
            let enabledCount = smallCategoryBalloons.filter(\.isEnabled).count
            let headingClass = smallCategoryHeadingClass(for: genreName, smallCategoryName: smallCategoryName)
            let resumeSmallCategoryButton = smallCategoryBalloons.isEmpty
                ? "<span class=\"button disabled-control\">風船を再開</span>"
                : "<a class=\"button primary\" href=\"\(listActionPath("/resume-small-category-balloons", items: [URLQueryItem(name: "genre", value: genreName), URLQueryItem(name: "middleCategory", value: middleCategoryName), URLQueryItem(name: "smallCategory", value: smallCategoryName)], returnTo: listReturnPath))\">風船を再開</a>"
            let stopSmallCategoryButton = smallCategoryBalloons.isEmpty
                ? "<span class=\"button disabled-control\">風船を停止</span>"
                : "<a class=\"button danger\" href=\"\(listActionPath("/toggle-small-category-balloons", items: [URLQueryItem(name: "genre", value: genreName), URLQueryItem(name: "middleCategory", value: middleCategoryName), URLQueryItem(name: "smallCategory", value: smallCategoryName), URLQueryItem(name: "enabled", value: "0")], returnTo: listReturnPath))\">風船を停止</a>"
            return """
            <section class="small-category-group">
              <div class="\(headingClass)">
                <h4>小カテゴリ: \(smallCategoryName.htmlEscaped)</h4>
                <div class="small-category-actions">
                  <span class="small-category-count">\(smallCategoryBalloons.count)件 / 稼働中 \(enabledCount)件</span>
                  \(resumeSmallCategoryButton)
                  \(stopSmallCategoryButton)
                </div>
              </div>
              \(smallCategoryBalloons.map { renderBalloonListItem($0, listReturnPath: listReturnPath) }.joined(separator: "\n"))
            </section>
            """
        }.joined(separator: "\n")
    }

    private func smallCategoryHeadingClass(for genreName: String, smallCategoryName: String) -> String {
        let normalizedGenreName = genreName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSmallCategoryName = smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalizedGenreName {
        case "せどり" where normalizedSmallCategoryName.contains("レディース"):
            return "small-category-heading resale-ladies"
        case "せどり" where normalizedSmallCategoryName.contains("メンズ"):
            return "small-category-heading resale"
        case "せどり":
            return "small-category-heading resale-other"
        case "マインド" where normalizedSmallCategoryName.contains("Dラボ"):
            return "small-category-heading mind-dlab"
        case "シンプルルール":
            return "small-category-heading simple-rule"
        default:
            return "small-category-heading"
        }
    }

    private func renderBalloonListItem(_ balloon: BalloonProfile, listReturnPath: String) -> String {
        let content = balloon.imageDataURL?.isEmpty == false ? "表: 添付画像" : "表: \(balloon.imageName ?? frontDisplayText(for: balloon))"
        let backMark = hasBackSide(balloon) ? " / 裏あり" : " / 裏なし"
        let activeMark = settings.activeBalloonID == balloon.id ? " / 表示対象" : ""
        let enabledTitle = balloon.isEnabled ? "稼働OFF" : "稼働ON"
        let enabledValue = balloon.isEnabled ? "0" : "1"
        let favoriteTitle = balloon.isFavorite ? "お気に入り解除" : "お気に入り"
        let favoriteValue = balloon.isFavorite ? "0" : "1"
        let favoriteClass = balloon.isFavorite ? "button favorite-button active" : "button favorite-button"
        let favoriteSymbol = balloon.isFavorite ? "⭐️" : "☆"
        let favoriteState = balloon.isFavorite ? "1" : "0"
        let itemClass = balloon.isEnabled ? "item enabled" : "item disabled"
        let statusClass = balloon.isEnabled ? "item-status" : "item-status off"
        let statusTitle = balloon.isEnabled ? "稼働中" : "停止中"
        let runningMark = balloon.isEnabled ? "<span class=\"running-mark\" title=\"稼働中\"></span>" : ""
        let idItem = URLQueryItem(name: "id", value: balloon.id.uuidString)
        let showHref = listActionPath("/show", items: [idItem], returnTo: listReturnPath)
        let editHref = listActionPath("/", items: [
            URLQueryItem(name: "tab", value: "create"),
            URLQueryItem(name: "edit", value: balloon.id.uuidString)
        ], returnTo: listReturnPath)
        let toggleHref = listActionPath("/toggle-balloon", items: [
            idItem,
            URLQueryItem(name: "enabled", value: enabledValue)
        ], returnTo: listReturnPath)
        let favoriteHref = listActionPath("/toggle-favorite", items: [
            idItem,
            URLQueryItem(name: "favorite", value: favoriteValue)
        ], returnTo: listReturnPath)
        let deleteHref = listActionPath("/delete", items: [idItem], returnTo: listReturnPath)
        let showButton = "<a class=\"button primary\" href=\"\(showHref.htmlEscaped)\" data-show-button=\"true\" data-id=\"\(balloon.id.uuidString)\">表示</a>"
        return """
        <div class="\(itemClass)">
          <div class="item-marker">
            <span class="item-number">品番 \(balloon.itemNumber)</span>
            <div class="item-dot" style="background: linear-gradient(135deg, \(balloon.colorStartHex), \(balloon.colorEndHex));"></div>
            \(runningMark)
          </div>
          <div>
            <p class="item-title">\(titleText(for: balloon).htmlEscaped)\(activeMark)<span class="\(statusClass)">\(statusTitle)</span></p>
            <p class="item-meta">\(listCategorySummary(for: balloon).htmlEscaped) / 正解 \(balloon.correctCount) / 不正解 \(balloon.incorrectCount) / \(reviewSummary(for: balloon)) / \(balloon.colorName.htmlEscaped) / \(balloon.positionName.htmlEscaped) / \(balloon.sizeName.htmlEscaped) / \(pauseSummary(for: balloon))\(backMark) / \(content.htmlEscaped)</p>
          </div>
          <div class="actions">
            <a class="button" href="\(toggleHref.htmlEscaped)">\(enabledTitle)</a>
            \(showButton)
            <a class="button" href="\(editHref.htmlEscaped)" data-edit-button="true">編集</a>
            <a class="\(favoriteClass)" href="\(favoriteHref.htmlEscaped)" title="\(favoriteTitle)" data-favorite-button="true" data-id="\(balloon.id.uuidString)" data-favorite="\(favoriteState)">\(favoriteSymbol)</a>
            <a class="button" href="\(deleteHref.htmlEscaped)" onclick="return confirm('本当に削除しますか？');">削除</a>
          </div>
        </div>
        """
    }
}

private func formatDuration(_ value: Double) -> String {
    String(format: "%.1f", value)
}

private func pauseSummary(for balloon: BalloonProfile) -> String {
    balloon.pausesAtMiddle ? "中央停止 \(formatDuration(balloon.middlePauseDuration))秒" : "中央停止なし"
}

private func reviewSummary(for balloon: BalloonProfile) -> String {
    guard let lastReviewedAt = balloon.lastReviewedAt else {
        return "更新未保存"
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yyyy/MM/dd HH:mm"
    return "更新 \(formatter.string(from: lastReviewedAt))"
}

private struct MiddleCategoryPair: Hashable {
    let genreName: String
    let middleCategoryName: String
}

private struct SmallCategoryPair: Hashable {
    let genreName: String
    let middleCategoryName: String
    let smallCategoryName: String
}

private extension Dictionary where Key == String, Value == String {
    func doubleValue(for key: String, fallback: Double) -> Double {
        guard let value = self[key], let double = Double(value) else {
            return fallback
        }
        return double
    }

}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    var urlQueryEscaped: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

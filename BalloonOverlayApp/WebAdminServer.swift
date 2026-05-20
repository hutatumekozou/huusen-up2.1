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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 24_000_000) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
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
                    editSmallCategoryGenreName: path.query["editSmallCategoryGenreName"],
                    editSmallCategoryName: path.query["editSmallCategoryName"],
                    itemNumberSearch: path.query["itemNumberSearch"]
                )
            )
        case "/show":
            if let id = path.query["id"].flatMap(UUID.init(uuidString:)) {
                DispatchQueue.main.async {
                    self.settings.activateBalloon(id: id)
                    self.showNow()
                }
            } else {
                DispatchQueue.main.async {
                    self.settings.activateNextEnabledBalloon()
                    self.showNow()
                }
            }
            return redirect(to: "/?tab=list&message=shown")
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
            return redirect(to: "/?tab=list&message=deleted")
        case "/toggle-balloon":
            if let id = path.query["id"].flatMap(UUID.init(uuidString:)) {
                let isEnabled = path.query["enabled"] == "1"
                DispatchQueue.main.async {
                    self.settings.setBalloonEnabled(id: id, isEnabled: isEnabled)
                    self.settingsChanged()
                }
            }
            return redirect(to: "/?tab=list&message=updated")
        case "/toggle-all-balloons":
            let isEnabled = path.query["enabled"] == "1"
            DispatchQueue.main.async {
                if isEnabled {
                    self.settings.restoreAllStopState()
                } else {
                    self.settings.setAllBalloonsEnabled(false)
                }
                self.settingsChanged()
            }
            return redirect(to: "/?tab=list&message=\(isEnabled ? "allRestored" : "allStopped")")
        case "/toggle-genre-balloons":
            if let genreName = path.query["genre"] {
                let isEnabled = path.query["enabled"] == "1"
                DispatchQueue.main.async {
                    self.settings.setBalloonsEnabled(inGenre: genreName, isEnabled: isEnabled)
                    self.settingsChanged()
                }
                return redirect(to: "/?tab=list&message=\(isEnabled ? "genreRestored" : "genreStopped")")
            }
            return redirect(to: "/?tab=list&message=updated")
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
        case "/edit-small-category":
            let genreName = path.query["manageSmallCategoryGenreName"] ?? ""
            let smallCategoryName = path.query["manageSmallCategoryName"] ?? ""
            return redirect(to: "/?tab=create&editSmallCategoryGenreName=\(genreName.urlQueryEscaped)&editSmallCategoryName=\(smallCategoryName.urlQueryEscaped)#category-editor")
        case "/rename-small-category":
            let genreName = path.query["targetSmallCategoryGenreName"] ?? path.query["manageSmallCategoryGenreName"] ?? ""
            let smallCategoryName = path.query["targetSmallCategoryName"] ?? path.query["manageSmallCategoryName"] ?? ""
            let newSmallCategoryName = path.query["renamedSmallCategoryName"] ?? ""
            DispatchQueue.main.async {
                self.settings.renameSmallCategory(inGenre: genreName, from: smallCategoryName, to: newSmallCategoryName)
                self.settingsChanged()
            }
            return redirect(to: "/?tab=create&message=categoryUpdated")
        case "/delete-small-category":
            let genreName = path.query["manageSmallCategoryGenreName"] ?? ""
            let smallCategoryName = path.query["manageSmallCategoryName"] ?? ""
            DispatchQueue.main.async {
                self.settings.deleteSmallCategory(inGenre: genreName, named: smallCategoryName)
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
        case "/save":
            let query = path.query
            DispatchQueue.main.async {
                let imageDataURL = query["removeImageData"] == "on" ? "" : query["imageDataURL"]
                let backImageDataURL = query["removeBackImageData"] == "on" ? "" : query["backImageDataURL"]
                let explanationImageDataURLs = (1...4).map { index in
                    query["removeExplanationImageData\(index)"] == "on" ? "" : (query["explanationImageDataURL\(index)"] ?? "")
                }
                let newGenreName = (query["newGenreName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let genreName = newGenreName.isEmpty ? (query["selectedGenreName"] ?? "") : newGenreName
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
                        imageName: query["imageName"],
                        imageDataURL: imageDataURL,
                        backText: query["backText"] ?? "",
                        backImageName: query["backImageName"],
                        backImageDataURL: backImageDataURL,
                        genreName: genreName,
                        smallCategoryName: smallCategoryName,
                        colorName: query["colorName"] ?? OverlaySettings.colorOptions[0].name,
                        positionName: query["positionName"] ?? "中央",
                        sizeName: query["sizeName"] ?? "標準",
                        pausesAtMiddle: query["pausesAtMiddle"] == "on",
                        middlePauseDuration: query.doubleValue(for: "middlePauseDuration", fallback: 1.0)
                    )
                } else {
                    self.settings.addBalloon(
                        title: title,
                        text: frontText,
                        explanationText: query["explanationText"] ?? "",
                        explanationImageDataURLs: explanationImageDataURLs,
                        imageName: query["imageName"],
                        imageDataURL: imageDataURL,
                        backText: query["backText"] ?? "",
                        backImageName: query["backImageName"],
                        backImageDataURL: backImageDataURL,
                        genreName: genreName,
                        smallCategoryName: smallCategoryName,
                        colorName: query["colorName"] ?? OverlaySettings.colorOptions[0].name,
                        positionName: query["positionName"] ?? "中央",
                        sizeName: query["sizeName"] ?? "標準",
                        pausesAtMiddle: query["pausesAtMiddle"] == "on",
                        middlePauseDuration: query.doubleValue(for: "middlePauseDuration", fallback: 1.0)
                    )
                }
                self.settingsChanged()
            }
            return redirect(to: "/?tab=list&message=saved")
        default:
            return httpResponse(status: "404 Not Found", body: "Not Found")
        }
    }

    private func requestPath(from request: String) -> (path: String, query: [String: String]) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            return ("/", [:])
        }

        let method = String(parts[0])
        let rawPath = String(parts[1])
        var components = URLComponents()
        components.percentEncodedPath = rawPath.components(separatedBy: "?").first ?? "/"
        if let query = rawPath.components(separatedBy: "?").dropFirst().first {
            components.percentEncodedQuery = query
        }

        var query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
        if method == "POST", let body = request.components(separatedBy: "\r\n\r\n").dropFirst().first {
            parseURLEncodedForm(body).forEach { key, value in
                query[key] = value
            }
        }
        return (components.path.isEmpty ? "/" : components.path, query)
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
        editSmallCategoryGenreName: String?,
        editSmallCategoryName: String?,
        itemNumberSearch: String?
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
        let previewSizeClass = formBalloon.sizeName == "ラージ" ? " large" : ""
        let previewContent = renderPreviewContent(imageDataURL: imageDataURL, imageName: imageName, text: frontDisplayText(for: formBalloon))
        let selectedTab = editingBalloon != nil ? "create" : (tab == "list" ? "list" : "create")
        let status = settings.isPaused ? "一時停止中" : "稼働中"
        let actionPath = settings.isPaused ? "/resume?tab=\(selectedTab)" : "/pause?tab=\(selectedTab)"
        let actionTitle = settings.isPaused ? "再開" : "一時停止"
        let escapedMessage = message.map { "<p class=\"notice\">\(messageText(for: $0))</p>" } ?? ""
        let colorOptions = renderColorOptions(selectedName: formBalloon.colorName)
        let positionOptions = renderPositionOptions(selectedName: formBalloon.positionName)
        let sizeOptions = renderSizeOptions(selectedName: formBalloon.sizeName)
        let createTabClass = selectedTab == "create" ? "tab active" : "tab"
        let listTabClass = selectedTab == "list" ? "tab active" : "tab"
        let tabContent = selectedTab == "list"
            ? renderListPanel(itemNumberSearch: itemNumberSearch)
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
                previewSizeClass: previewSizeClass,
                previewContent: previewContent,
                colorOptions: colorOptions,
                positionOptions: positionOptions,
                sizeOptions: sizeOptions,
                editGenreName: editGenreName,
                editSmallCategoryGenreName: editSmallCategoryGenreName,
                editSmallCategoryName: editSmallCategoryName
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
            .top-field {
              margin-bottom: 18px;
            }
            .preview {
              display: grid;
              grid-template-columns: 210px minmax(0, 1fr);
              gap: 18px;
              align-items: center;
              margin-bottom: 22px;
            }
            .preview-balloon {
              width: 96px;
              height: 120px;
              position: relative;
            }
            .preview-balloon.large {
              width: 192px;
              height: 240px;
            }
            .preview-body {
              width: 96px;
              height: 96px;
              display: grid;
              place-items: center;
              border-radius: 50%;
              background: linear-gradient(135deg, \(formBalloon.colorStartHex), \(formBalloon.colorEndHex));
              color: white;
              font-size: 26px;
              font-weight: 700;
              overflow: hidden;
              box-shadow: 0 8px 18px rgba(0, 0, 0, 0.16);
            }
            .preview-balloon.large .preview-body {
              width: 192px;
              height: 192px;
              font-size: 78px;
            }
            .preview-image-stack {
              display: grid;
              gap: 3px;
              justify-items: center;
              align-content: center;
              width: 86%;
              height: 86%;
            }
            .preview-image-caption {
              max-width: 100%;
              color: white;
              font-size: 12px;
              line-height: 1.1;
              text-align: center;
              overflow: hidden;
              display: -webkit-box;
              -webkit-box-orient: vertical;
              -webkit-line-clamp: 2;
              text-shadow: 0 1px 2px rgba(0, 0, 0, 0.35);
            }
            .preview-body img {
              display: block;
              max-width: 66px;
              max-height: 66px;
              object-fit: contain;
            }
            .preview-balloon.large .preview-body img {
              max-width: 156px;
              max-height: 156px;
            }
            .preview-image-stack.has-caption img {
              max-height: 52px;
            }
            .preview-balloon.large .preview-image-stack.has-caption img {
              max-height: 112px;
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
            .genre-add-row {
              display: grid;
              grid-template-columns: minmax(0, 1fr) auto;
              gap: 8px;
              align-items: center;
            }
            .small-category-add-row {
              display: grid;
              grid-template-columns: minmax(150px, 0.4fr) minmax(0, 1fr) auto;
              gap: 8px;
              align-items: center;
            }
            .genre-add-row button {
              height: 36px;
              padding: 0 14px;
              white-space: nowrap;
            }
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
            .small-category-manage-row {
              display: grid;
              grid-template-columns: minmax(130px, 0.35fr) minmax(130px, 0.35fr) auto auto;
              gap: 8px;
              align-items: center;
            }
            .category-manage-row button {
              height: 36px;
              padding: 0 14px;
              white-space: nowrap;
            }
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
            .explanation-image-title {
              display: flex;
              justify-content: space-between;
              gap: 8px;
              font-weight: 700;
            }
            .explanation-image-title small {
              color: #5f6368;
              font-weight: 600;
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
            .preview-title {
              font-size: 17px;
              font-weight: 700;
              margin: 0 0 8px;
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
              grid-template-columns: repeat(5, 42px);
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
            .segmented {
              display: grid;
              grid-template-columns: repeat(4, minmax(0, 1fr));
              gap: 8px;
            }
            .segmented.two {
              grid-template-columns: repeat(2, minmax(0, 1fr));
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
            .item-meta {
              color: #5f6368;
              font-size: 13px;
              margin: 0;
            }
            .list-filter {
              display: grid;
              grid-template-columns: minmax(180px, 260px) auto minmax(0, 1fr);
              gap: 8px;
              align-items: end;
              margin: 16px 0 14px;
            }
            .list-filter label {
              gap: 6px;
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
            @media (max-width: 620px) {
              header, .grid, .preview, .item, .panel-heading { display: block; }
              .heading-actions { justify-content: flex-start; margin: 12px 0 0; }
              .explanation-image-grid { grid-template-columns: 1fr; }
              label { margin-bottom: 14px; }
              .preview-balloon { margin-bottom: 14px; }
              .item-dot { margin-bottom: 8px; }
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
              <div class="actions">
                <a class="button primary" href="/show">今すぐ表示</a>
                <a class="button" href="\(actionPath)">\(actionTitle)</a>
              </div>
            </header>
            \(escapedMessage)
            <nav class="tabs">
              <a class="\(createTabClass)" href="/?tab=create">風船作成</a>
              <a class="\(listTabClass)" href="/?tab=list">作成した風船一覧</a>
            </nav>
            \(tabContent)
          </main>
          <script>
            const imageFileInput = document.querySelector("#imageFileInput");
            const imageDataURLInput = document.querySelector("#imageDataURLInput");
            const removeImageDataInput = document.querySelector("#removeImageDataInput");
            const backImageFileInput = document.querySelector("#backImageFileInput");
            const backImageDataURLInput = document.querySelector("#backImageDataURLInput");
            const removeBackImageDataInput = document.querySelector("#removeBackImageDataInput");
            const explanationImageSlots = [1, 2, 3, 4].map((index) => ({
              index,
              fileInput: document.querySelector(`#explanationImageFileInput${index}`),
              dataInput: document.querySelector(`#explanationImageDataURLInput${index}`),
              removeInput: document.querySelector(`#removeExplanationImageDataInput${index}`)
            }));
            const previewBody = document.querySelector("#previewBody");
            const previewBalloon = document.querySelector("#previewBalloon");
            const sizeInputs = document.querySelectorAll('input[name="sizeName"]');
            const genreSelect = document.querySelector('select[name="selectedGenreName"]');
            const newGenreInput = document.querySelector('input[name="newGenreName"]');
            const addGenreButton = document.querySelector("#addGenreButton");
            const smallCategorySelect = document.querySelector('select[name="selectedSmallCategoryName"]');
            const smallCategoryGenreSelect = document.querySelector('select[name="smallCategoryGenreName"]');
            const manageSmallCategoryGenreSelect = document.querySelector('select[name="manageSmallCategoryGenreName"]');
            const manageSmallCategorySelect = document.querySelector('select[name="manageSmallCategoryName"]');
            const newSmallCategoryInput = document.querySelector('input[name="newSmallCategoryName"]');
            const addSmallCategoryButton = document.querySelector("#addSmallCategoryButton");
            const resetCreateFormButton = document.querySelector("#resetCreateFormButton");
            const previewTitleMeta = document.querySelector("#previewTitleMeta");
            const previewBackMeta = document.querySelector("#previewBackMeta");
            const previewGenreMeta = document.querySelector("#previewGenreMeta");
            const previewSpeedMeta = document.querySelector("#previewSpeedMeta");
            const previewPositionMeta = document.querySelector("#previewPositionMeta");
            const previewSizeMeta = document.querySelector("#previewSizeMeta");
            const previewPauseMeta = document.querySelector("#previewPauseMeta");

            function renderPreviewImage(dataURL) {
              if (!previewBody) return;

              const captionText = document.querySelector('input[name="imageName"]')?.value.trim() || "";
              previewBody.innerHTML = "";
              const stack = document.createElement("span");
              stack.className = captionText ? "preview-image-stack has-caption" : "preview-image-stack";

              if (captionText) {
                const caption = document.createElement("span");
                caption.className = "preview-image-caption";
                caption.textContent = captionText;
                stack.append(caption);
              }

              const image = document.createElement("img");
              image.src = dataURL;
              image.alt = "";
              stack.append(image);
              previewBody.append(stack);
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

            imageFileInput?.addEventListener("change", async () => {
              const file = imageFileInput.files?.[0];
              if (!file || !imageDataURLInput || !previewBody) return;

              try {
                const dataURL = await fitImageToBalloon(file);
                imageDataURLInput.value = dataURL;
                if (removeImageDataInput) removeImageDataInput.checked = false;
                renderPreviewImage(dataURL);
              } catch {
                window.alert("画像を読み込めませんでした。別の画像を選んでください。");
              }
            });

            removeImageDataInput?.addEventListener("change", () => {
              if (!removeImageDataInput.checked || !imageDataURLInput || !previewBody) return;
              imageDataURLInput.value = "";
              imageFileInput.value = "";
              previewBody.textContent = document.querySelector('input[name="imageName"]')?.value || document.querySelector('input[name="text"]')?.value || "🎈";
            });

            document.querySelector('input[name="imageName"]')?.addEventListener("input", () => {
              if (!imageDataURLInput?.value) return;
              renderPreviewImage(imageDataURLInput.value);
            });

            backImageFileInput?.addEventListener("change", async () => {
              const file = backImageFileInput.files?.[0];
              if (!file || !backImageDataURLInput) return;

              try {
                const dataURL = await fitImageToBalloon(file);
                backImageDataURLInput.value = dataURL;
                if (removeBackImageDataInput) removeBackImageDataInput.checked = false;
              } catch {
                window.alert("裏面画像を読み込めませんでした。別の画像を選んでください。");
              }
            });

            removeBackImageDataInput?.addEventListener("change", () => {
              if (!removeBackImageDataInput.checked || !backImageDataURLInput) return;
              backImageDataURLInput.value = "";
              backImageFileInput.value = "";
            });

            explanationImageSlots.forEach(({ index, fileInput, dataInput, removeInput }) => {
              fileInput?.addEventListener("change", async () => {
                const file = fileInput.files?.[0];
                if (!file || !dataInput) return;

                try {
                  dataInput.value = await fitImageToBalloon(file, 1000, 0.9);
                  if (removeInput) removeInput.checked = false;
                } catch {
                  window.alert(`解説画像${index}を読み込めませんでした。別の画像を選んでください。`);
                }
              });

              removeInput?.addEventListener("change", () => {
                if (!removeInput.checked || !dataInput) return;
                dataInput.value = "";
                if (fileInput) fileInput.value = "";
              });
            });

            sizeInputs.forEach((input) => {
              input.addEventListener("change", () => {
                previewBalloon?.classList.toggle("large", input.value === "ラージ" && input.checked);
              });
            });

            function selectedLargeCategory() {
              return newGenreInput?.value.trim() || genreSelect?.value || "未分類";
            }

            function selectedSmallCategoryGenre() {
              return smallCategoryGenreSelect?.value || selectedLargeCategory();
            }

            function updateSmallCategoryOptions() {
              if (!smallCategorySelect) return;
              const largeCategory = selectedLargeCategory();
              let hasSelectedVisibleOption = false;

              Array.from(smallCategorySelect.options).forEach((option) => {
                const optionGenre = option.dataset.genre || "";
                const isDefaultOption = option.value === "";
                const isVisible = isDefaultOption || optionGenre === largeCategory;
                option.hidden = !isVisible;
                option.disabled = !isVisible;
                if (isVisible && option.selected) {
                  hasSelectedVisibleOption = true;
                }
              });

              if (!hasSelectedVisibleOption) {
                smallCategorySelect.value = "";
              }
            }

            function updateManageSmallCategoryOptions() {
              if (!manageSmallCategorySelect || !manageSmallCategoryGenreSelect) return;
              const largeCategory = manageSmallCategoryGenreSelect.value || "未分類";
              let hasSelectedVisibleOption = false;

              Array.from(manageSmallCategorySelect.options).forEach((option) => {
                const optionGenre = option.dataset.genre || "";
                const isDefaultOption = option.value === "";
                const isVisible = isDefaultOption || optionGenre === largeCategory;
                option.hidden = !isVisible;
                option.disabled = !isVisible;
                if (isVisible && option.selected) {
                  hasSelectedVisibleOption = true;
                }
              });

              if (!hasSelectedVisibleOption) {
                manageSmallCategorySelect.value = "";
              }
            }

            genreSelect?.addEventListener("change", () => {
              if (smallCategoryGenreSelect) {
                smallCategoryGenreSelect.value = selectedLargeCategory();
              }
              updateSmallCategoryOptions();
            });
            newGenreInput?.addEventListener("input", updateSmallCategoryOptions);
            manageSmallCategoryGenreSelect?.addEventListener("change", updateManageSmallCategoryOptions);
            updateSmallCategoryOptions();
            updateManageSmallCategoryOptions();

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
              if (smallCategoryGenreSelect && !Array.from(smallCategoryGenreSelect.options).some((option) => option.value === genreName)) {
                const option = document.createElement("option");
                option.value = genreName;
                option.textContent = genreName;
                option.selected = true;
                smallCategoryGenreSelect.append(option);
              } else if (smallCategoryGenreSelect) {
                smallCategoryGenreSelect.value = genreName;
              }
              if (manageSmallCategoryGenreSelect && !Array.from(manageSmallCategoryGenreSelect.options).some((option) => option.value === genreName)) {
                const option = document.createElement("option");
                option.value = genreName;
                option.textContent = genreName;
                manageSmallCategoryGenreSelect.append(option);
              }
              newGenreInput.value = "";
              updateSmallCategoryOptions();
              updateManageSmallCategoryOptions();
            });

            addSmallCategoryButton?.addEventListener("click", () => {
              const smallCategoryName = newSmallCategoryInput?.value.trim();
              if (!smallCategoryName || !smallCategorySelect || !newSmallCategoryInput) return;
              const largeCategory = selectedSmallCategoryGenre();

              const existingOption = Array.from(smallCategorySelect.options).find((option) => option.value === smallCategoryName && (option.dataset.genre || "") === largeCategory);
              if (existingOption) {
                smallCategorySelect.value = smallCategoryName;
              } else {
                const option = document.createElement("option");
                option.value = smallCategoryName;
                option.textContent = smallCategoryName;
                option.dataset.genre = largeCategory;
                option.selected = true;
                smallCategorySelect.append(option);
              }
              if (manageSmallCategorySelect && !Array.from(manageSmallCategorySelect.options).some((option) => option.value === smallCategoryName && (option.dataset.genre || "") === largeCategory)) {
                const option = document.createElement("option");
                option.value = smallCategoryName;
                option.textContent = smallCategoryName;
                option.dataset.genre = largeCategory;
                manageSmallCategorySelect.append(option);
              }
              if (genreSelect) {
                genreSelect.value = largeCategory;
              }
              if (smallCategoryGenreSelect) {
                smallCategoryGenreSelect.value = largeCategory;
              }
              newSmallCategoryInput.value = "";
              updateSmallCategoryOptions();
              updateManageSmallCategoryOptions();
            });

            resetCreateFormButton?.addEventListener("click", () => {
              const form = resetCreateFormButton.closest("form");
              if (!form) return;

              form.querySelector('input[name="title"]').value = "";
              form.querySelector('input[name="text"]').value = "";
              form.querySelector('input[name="backText"]').value = "";
              form.querySelector('textarea[name="explanationText"]').value = "";
              form.querySelector('input[name="imageName"]').value = "";
              form.querySelector('input[name="backImageName"]').value = "";
              form.querySelector('input[name="intervalMinutes"]').value = "1.0";
              form.querySelector('input[name="climbSpeed"]').value = "300";
              form.querySelector('input[name="randomIntervalMinSeconds"]').value = "5";
              form.querySelector('input[name="randomIntervalMaxSeconds"]').value = "600";
              form.querySelector('input[name="middlePauseDuration"]').value = "10";
              form.querySelector('input[name="pausesAtMiddle"]').checked = true;

              const defaultColor = form.querySelector('input[name="colorName"][value="レッド"]') || form.querySelector('input[name="colorName"]');
              if (defaultColor) defaultColor.checked = true;
              const defaultPosition = form.querySelector('input[name="positionName"][value="中央"]') || form.querySelector('input[name="positionName"]');
              if (defaultPosition) defaultPosition.checked = true;
              const defaultSize = form.querySelector('input[name="sizeName"][value="ラージ"]') || form.querySelector('input[name="sizeName"]');
              if (defaultSize) defaultSize.checked = true;

              if (genreSelect) genreSelect.value = "未分類";
              if (newGenreInput) newGenreInput.value = "";
              if (smallCategoryGenreSelect) smallCategoryGenreSelect.value = "未分類";
              if (smallCategorySelect) smallCategorySelect.value = "";
              if (manageSmallCategoryGenreSelect) manageSmallCategoryGenreSelect.value = "未分類";
              if (manageSmallCategorySelect) manageSmallCategorySelect.value = "";
              if (newSmallCategoryInput) newSmallCategoryInput.value = "";
              updateSmallCategoryOptions();
              updateManageSmallCategoryOptions();
              if (imageFileInput) imageFileInput.value = "";
              if (imageDataURLInput) imageDataURLInput.value = "";
              if (removeImageDataInput) removeImageDataInput.checked = false;
              if (backImageFileInput) backImageFileInput.value = "";
              if (backImageDataURLInput) backImageDataURLInput.value = "";
              if (removeBackImageDataInput) removeBackImageDataInput.checked = false;
              explanationImageSlots.forEach(({ fileInput, dataInput, removeInput }) => {
                if (fileInput) fileInput.value = "";
                if (dataInput) dataInput.value = "";
                if (removeInput) removeInput.checked = false;
              });
              previewBalloon?.classList.add("large");
              if (previewBody) previewBody.textContent = "🎈";
              if (previewTitleMeta) previewTitleMeta.textContent = "表面: ";
              if (previewBackMeta) previewBackMeta.textContent = "裏面: なし";
              if (previewGenreMeta) previewGenreMeta.textContent = "名前カテゴリ: 大カテゴリ 未分類";
              if (previewSpeedMeta) previewSpeedMeta.textContent = "上昇スピード: 300 px/秒";
              if (previewPositionMeta) previewPositionMeta.textContent = "上昇位置: 中央";
              if (previewSizeMeta) previewSizeMeta.textContent = "サイズ: ラージ";
              if (previewPauseMeta) previewPauseMeta.textContent = "中央停止: 10秒";
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
        previewSizeClass: String,
        previewContent: String,
        colorOptions: String,
        positionOptions: String,
        sizeOptions: String,
        editGenreName: String?,
        editSmallCategoryGenreName: String?,
        editSmallCategoryName: String?
    ) -> String {
        let hiddenIDInput = editingID.map { "<input type=\"hidden\" name=\"id\" value=\"\($0.uuidString)\">" } ?? ""
        let submitTitle = editingID == nil ? "保存" : "更新"
        let panelTitle = editingID == nil ? "風船作成" : "風船編集"
        let titleValue = editingID == nil ? "" : activeBalloon.title.htmlEscaped
        let textValue = editingID == nil ? "" : activeBalloon.text.htmlEscaped
        let resetLink = editingID == nil ? "" : "<a class=\"button\" href=\"/?tab=create\">新規作成に戻す</a>"
        let genreOptions = renderGenreOptions(selectedName: activeBalloon.genreName)
        let smallCategoryOptions = renderSmallCategoryOptions(selectedName: activeBalloon.smallCategoryName, selectedGenreName: activeBalloon.genreName)
        let explanationImageInputs = renderExplanationImageInputs(for: activeBalloon)
        let explanationImageControls = renderExplanationImageControls(for: activeBalloon)
        let categoryEditPanel = renderCategoryEditPanel(
            editGenreName: editGenreName,
            editSmallCategoryGenreName: editSmallCategoryGenreName,
            editSmallCategoryName: editSmallCategoryName
        )

        return """
        <section class="panel">
          <form action="/save" method="post">
            \(hiddenIDInput)
            <input id="imageDataURLInput" type="hidden" name="imageDataURL" value="\(imageDataURL.htmlEscaped)">
            <input id="backImageDataURLInput" type="hidden" name="backImageDataURL" value="\(backImageDataURL.htmlEscaped)">
            \(explanationImageInputs)
            <div class="panel-heading">
              <h2>\(panelTitle)</h2>
              <span class="heading-actions">
                <button id="resetCreateFormButton" type="button">入力中の内容をリセット</button>
              </span>
            </div>
            <label class="top-field">
              タイトル
              <input name="title" value="\(titleValue)" placeholder="例: 商品名 / 問題名 / メモの名前">
            </label>
            <div class="preview">
              <div class="preview-balloon\(previewSizeClass)" id="previewBalloon">
                <div class="preview-body" id="previewBody">\(previewContent)</div>
                <div class="preview-knot"></div>
              </div>
              <div>
                <p class="preview-title">登録中の風船</p>
                <p class="preview-meta" id="previewTitleMeta">表面: \(frontDisplayText(for: activeBalloon).htmlEscaped)</p>
                <p class="preview-meta" id="previewBackMeta">裏面: \(backSideSummary(for: activeBalloon).htmlEscaped)</p>
                <p class="preview-meta" id="previewGenreMeta">名前カテゴリ: \(categorySummary(for: activeBalloon).htmlEscaped)</p>
                <p class="preview-meta" id="previewSpeedMeta">上昇スピード: \(climbSpeed) px/秒</p>
                <p class="preview-meta" id="previewPositionMeta">上昇位置: \(activeBalloon.positionName.htmlEscaped)</p>
                <p class="preview-meta" id="previewSizeMeta">サイズ: \(activeBalloon.sizeName.htmlEscaped)</p>
                <p class="preview-meta" id="previewPauseMeta">中央停止: \(activeBalloon.pausesAtMiddle ? "\(formatDuration(activeBalloon.middlePauseDuration))秒" : "なし")</p>
              </div>
            </div>
            <div class="grid">
              <label class="front-entry">
                表に入れる文字
                <input name="text" value="\(textValue)" placeholder="例: しばし待たれよ / 水を飲む / これいくらで売れた?">
              </label>
              <label class="front-entry">
                表画像の上に出す文字
                <input name="imageName" value="\(imageName.htmlEscaped)" placeholder="画像を入れた時に上に表示">
              </label>
              <label class="file-row front-entry">
                表に入れる画像ファイル
                <span class="file-control-row">
                  <input id="imageFileInput" type="file" accept="image/*">
                  <span class="clearline">
                    <input id="removeImageDataInput" name="removeImageData" type="checkbox">
                    表面の添付画像を削除
                  </span>
                </span>
                <p class="file-hint">表面に出す画像です。選んだ画像は自動で縮小して保存します。</p>
              </label>
              <span class="grid-spacer"></span>
              <label class="back-entry">
                裏に入れる文字
                <input name="backText" value="\(activeBalloon.backText.htmlEscaped)" placeholder="例: 答え / 解説の要点 / 裏面メモ">
              </label>
              <label class="back-entry">
                裏画像の上に出す文字
                <input name="backImageName" value="\(backImageName.htmlEscaped)" placeholder="画像を入れた時に上に表示">
              </label>
              <label class="file-row back-entry">
                裏に入れる画像ファイル
                <span class="file-control-row">
                  <input id="backImageFileInput" type="file" accept="image/*">
                  <span class="clearline">
                    <input id="removeBackImageDataInput" name="removeBackImageData" type="checkbox">
                    裏面の添付画像を削除
                  </span>
                </span>
                <p class="file-hint">裏面に出す画像です。裏面の文字より画像が優先されます。</p>
              </label>
              <label class="full explanation-entry">
                解説に入れる内容
                <textarea name="explanationText" placeholder="解説ボタンを押した時に表示する内容">\(activeBalloon.explanationText.htmlEscaped)</textarea>
              </label>
              <label class="full explanation-image-field explanation-entry">
                解説に添付する画像（最大4枚）
                <span class="explanation-image-grid">
                  \(explanationImageControls)
                </span>
                <p class="file-hint">解説の本文の下に表示します。選んだ画像は自動で縮小して保存します。</p>
              </label>
              <label class="row-start">
                表示間隔（分）
                <input name="intervalMinutes" type="number" min="0.1" step="0.1" value="\(intervalMinutes)">
              </label>
              <label>
                上昇スピード（px/秒）
                <input name="climbSpeed" type="number" min="40" max="900" step="10" value="\(climbSpeed)">
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
                  選択中の大カテゴリに紐づく小カテゴリから選ぶ
                  <select name="selectedSmallCategoryName">
                    \(smallCategoryOptions)
                  </select>
                </span>
                <span class="category-action-block">
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
                    <button type="submit" formmethod="post" formaction="/edit-genre">修正</button>
                    <button type="submit" formmethod="post" formaction="/delete-genre" onclick="return confirm('本当に削除しますか？');">削除</button>
                  </span>
                </span>
                <span class="category-action-block">
                  小カテゴリを紐づける大カテゴリを選んで追加する
                  <span class="small-category-add-row">
                    <select name="smallCategoryGenreName">
                      \(genreOptions)
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
                    <select name="manageSmallCategoryName">
                      \(smallCategoryOptions)
                    </select>
                    <button type="submit" formmethod="post" formaction="/edit-small-category">修正</button>
                    <button type="submit" formmethod="post" formaction="/delete-small-category" onclick="return confirm('本当に削除しますか？');">削除</button>
                  </span>
                </span>
                \(categoryEditPanel)
              </label>
              <label class="full">
                風船カラー
                <div class="swatches">
                  \(colorOptions)
                </div>
              </label>
              <label class="full">
                風船が這い上がる場所
                <div class="segmented">
                  \(positionOptions)
                </div>
              </label>
              <label>
                ランダム時の最小秒
                <input name="randomIntervalMinSeconds" type="number" min="1" step="1" value="\(randomIntervalMinSeconds)">
              </label>
              <label>
                ランダム時の最大秒
                <input name="randomIntervalMaxSeconds" type="number" min="1" step="1" value="\(randomIntervalMaxSeconds)">
              </label>
              <label class="full">
                風船サイズ
                <div class="segmented two">
                  \(sizeOptions)
                </div>
              </label>
              <label>
                高さ中央で一旦停止
                <span class="checkline">
                  <input name="pausesAtMiddle" type="checkbox" \(activeBalloon.pausesAtMiddle ? "checked" : "")>
                  停止する
                </span>
              </label>
              <label>
                停止時間（秒）
                <input name="middlePauseDuration" type="number" min="0.1" max="30" step="0.1" value="\(formatDuration(activeBalloon.middlePauseDuration))">
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
        (1...4).map { index in
            let value = balloon.explanationImageDataURLs[safe: index - 1] ?? ""
            return "<input id=\"explanationImageDataURLInput\(index)\" type=\"hidden\" name=\"explanationImageDataURL\(index)\" value=\"\(value.htmlEscaped)\">"
        }.joined(separator: "\n")
    }

    private func renderExplanationImageControls(for balloon: BalloonProfile) -> String {
        (1...4).map { index in
            let hasImage = balloon.explanationImageDataURLs[safe: index - 1]?.nilIfEmpty != nil
            let status = hasImage ? "添付済み" : "未添付"
            return """
            <span class="explanation-image-item">
              <span class="explanation-image-title">画像\(index) <small>\(status)</small></span>
              <input id="explanationImageFileInput\(index)" type="file" accept="image/*">
              <span class="clearline">
                <input id="removeExplanationImageDataInput\(index)" name="removeExplanationImageData\(index)" type="checkbox">
                この画像を削除
              </span>
            </span>
            """
        }.joined(separator: "\n")
    }

    private func renderListPanel(itemNumberSearch: String?) -> String {
        let operationStatus = settings.isPaused ? "停止中" : "稼働中"
        let enabledCount = settings.enabledBalloons.count
        let searchValue = itemNumberSearch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let startAllButton = settings.canRestoreAllStopState
            ? "<a class=\"button primary\" href=\"/toggle-all-balloons?enabled=1\">全商品停止を解除</a>"
            : "<span class=\"button disabled-control\">全商品停止を解除</span>"
        let stopAllButton = enabledCount > 0
            ? "<a class=\"button danger\" href=\"/toggle-all-balloons?enabled=0\">全商品を停止</a>"
            : "<span class=\"button disabled-control\">全商品を停止</span>"

        return """
        <section class="panel">
          <div class="panel-heading">
            <div>
              <h2>作成した風船一覧</h2>
              <p class="heading-meta">全体状態: \(operationStatus) / 稼働中の風船: \(enabledCount)件</p>
            </div>
            <div class="actions">
              \(startAllButton)
              \(stopAllButton)
            </div>
          </div>
          <form class="list-filter" action="/" method="get">
            <input type="hidden" name="tab" value="list">
            <label>
              品番で検索
              <input name="itemNumberSearch" value="\(searchValue.htmlEscaped)" placeholder="例: 12">
            </label>
            <button type="submit">検索</button>
            <a class="button" href="/?tab=list">クリア</a>
          </form>
          \(renderBalloonList(itemNumberSearch: searchValue))
        </section>
        """
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
        case "genreStopped":
            return "大カテゴリ内の商品を停止しました"
        case "genreRestored":
            return "大カテゴリ内の商品停止を解除しました"
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
        editSmallCategoryGenreName: String?,
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

        if let editSmallCategoryGenreName = editSmallCategoryGenreName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           let editSmallCategoryName = editSmallCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return """
            <span class="category-edit-panel">
              <strong>小カテゴリ名を修正</strong>
              <p>大カテゴリ: \(editSmallCategoryGenreName.htmlEscaped) / 小カテゴリ: \(editSmallCategoryName.htmlEscaped)</p>
              <span class="category-edit-actions">
                <input name="renamedSmallCategoryName" value="\(editSmallCategoryName.htmlEscaped)" placeholder="修正後の小カテゴリ名">
                <button type="submit" formmethod="post" formaction="/rename-small-category?targetSmallCategoryGenreName=\(editSmallCategoryGenreName.urlQueryEscaped)&targetSmallCategoryName=\(editSmallCategoryName.urlQueryEscaped)">保存</button>
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

    private func renderSmallCategoryOptions(selectedName: String, selectedGenreName: String) -> String {
        let normalizedSelectedGenreName = selectedGenreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        var categoryPairs = Set(settings.balloons.compactMap { balloon -> SmallCategoryPair? in
            guard let smallCategoryName = balloon.smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
                return nil
            }
            let genreName = balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
            return SmallCategoryPair(genreName: genreName, smallCategoryName: smallCategoryName)
        })
        if let selectedName = selectedName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            categoryPairs.insert(SmallCategoryPair(genreName: normalizedSelectedGenreName, smallCategoryName: selectedName))
        }

        let selectedEmpty = selectedName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil ? " selected" : ""
        let options = categoryPairs.sorted {
            if $0.genreName == $1.genreName {
                return $0.smallCategoryName.localizedStandardCompare($1.smallCategoryName) == .orderedAscending
            }
            if $0.genreName == "未分類" { return true }
            if $1.genreName == "未分類" { return false }
            return $0.genreName.localizedStandardCompare($1.genreName) == .orderedAscending
        }.map { pair in
            let selected = pair.genreName == normalizedSelectedGenreName && pair.smallCategoryName == selectedName ? " selected" : ""
            return "<option value=\"\(pair.smallCategoryName.htmlEscaped)\" data-genre=\"\(pair.genreName.htmlEscaped)\"\(selected)>\(pair.smallCategoryName.htmlEscaped)</option>"
        }.joined(separator: "\n")

        return "<option value=\"\"\(selectedEmpty)>未指定</option>\n\(options)"
    }

    private func renderColorOptions(selectedName: String) -> String {
        OverlaySettings.colorOptions.map { option in
            let checked = option.name == selectedName ? " checked" : ""
            return """
            <label class="swatch" title="\(option.name.htmlEscaped)">
              <input type="radio" name="colorName" value="\(option.name.htmlEscaped)"\(checked)>
              <span style="background: linear-gradient(135deg, \(option.startHex), \(option.endHex));"></span>
            </label>
            """
        }.joined(separator: "\n")
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
            let caption = imageName.trimmingCharacters(in: .whitespacesAndNewlines)
            let captionHTML = caption.isEmpty ? "" : "<span class=\"preview-image-caption\">\(caption.htmlEscaped)</span>"
            let captionClass = caption.isEmpty ? "" : " has-caption"
            return "<span class=\"preview-image-stack\(captionClass)\">\(captionHTML)<img src=\"\(imageDataURL.htmlEscaped)\" alt=\"\"></span>"
        }
        return (imageName.isEmpty ? text : imageName).htmlEscaped
    }

    private func frontDisplayText(for balloon: BalloonProfile) -> String {
        balloon.text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? balloon.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "🎈"
    }

    private func titleText(for balloon: BalloonProfile) -> String {
        balloon.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? frontDisplayText(for: balloon)
    }

    private func categorySummary(for balloon: BalloonProfile) -> String {
        let largeCategory = balloon.genreName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分類"
        let smallCategory = balloon.smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let smallCategory {
            return "大カテゴリ \(largeCategory) / 小カテゴリ \(smallCategory)"
        }
        return "大カテゴリ \(largeCategory)"
    }

    private func listCategorySummary(for balloon: BalloonProfile) -> String {
        balloon.smallCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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

    private func renderBalloonList(itemNumberSearch: String) -> String {
        let balloons = filteredBalloons(itemNumberSearch: itemNumberSearch)
        guard !balloons.isEmpty else {
            return itemNumberSearch.isEmpty
                ? "<p class=\"empty\">まだ風船がありません。</p>"
                : "<p class=\"empty\">該当する品番の風船がありません。</p>"
        }

        return """
        <div class="list">
        \(renderBalloonGenreGroups(balloons: balloons))
        </div>
        """
    }

    private func filteredBalloons(itemNumberSearch: String) -> [BalloonProfile] {
        let query = itemNumberSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return settings.balloons }

        return settings.balloons.filter { balloon in
            "\(balloon.itemNumber)".contains(query)
        }
    }

    private func renderBalloonGenreGroups(balloons sourceBalloons: [BalloonProfile]) -> String {
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
            let disabledCount = balloons.count - enabledCount
            let encodedGenreName = genreName.urlQueryEscaped
            let startGenreButton = disabledCount > 0
                ? "<a class=\"button primary\" href=\"/toggle-genre-balloons?genre=\(encodedGenreName)&enabled=1\">全商品停止を解除</a>"
                : "<span class=\"button disabled-control\">全商品停止を解除</span>"
            let stopGenreButton = enabledCount > 0
                ? "<a class=\"button danger\" href=\"/toggle-genre-balloons?genre=\(encodedGenreName)&enabled=0\">全商品を停止</a>"
                : "<span class=\"button disabled-control\">全商品を停止</span>"
            return """
            <section class="genre-group">
              <div class="genre-heading">
                <h3>大カテゴリ: \(genreName.htmlEscaped)</h3>
                <div class="genre-actions">
                  <span class="genre-count">\(balloons.count)件 / 稼働中 \(enabledCount)件</span>
                  \(startGenreButton)
                  \(stopGenreButton)
                </div>
              </div>
              \(balloons.map(renderBalloonListItem).joined(separator: "\n"))
            </section>
            """
        }.joined(separator: "\n")
    }

    private func renderBalloonListItem(_ balloon: BalloonProfile) -> String {
        let content = balloon.imageDataURL?.isEmpty == false ? "表: 添付画像" : "表: \(balloon.imageName ?? frontDisplayText(for: balloon))"
        let backMark = hasBackSide(balloon) ? " / 裏あり" : " / 裏なし"
        let activeMark = settings.activeBalloonID == balloon.id ? " / 表示対象" : ""
        let enabledTitle = balloon.isEnabled ? "稼働OFF" : "稼働ON"
        let enabledValue = balloon.isEnabled ? "0" : "1"
        let itemClass = balloon.isEnabled ? "item enabled" : "item disabled"
        let statusClass = balloon.isEnabled ? "item-status" : "item-status off"
        let statusTitle = balloon.isEnabled ? "稼働中" : "停止中"
        let runningMark = balloon.isEnabled ? "<span class=\"running-mark\" title=\"稼働中\"></span>" : ""
        let showButton = balloon.isEnabled
            ? "<a class=\"button primary\" href=\"/show?id=\(balloon.id.uuidString)\">表示</a>"
            : "<span class=\"button disabled-control\">表示</span>"
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
            <a class="button" href="/toggle-balloon?id=\(balloon.id.uuidString)&enabled=\(enabledValue)">\(enabledTitle)</a>
            \(showButton)
            <a class="button" href="/?tab=create&edit=\(balloon.id.uuidString)">編集</a>
            <a class="button" href="/delete?id=\(balloon.id.uuidString)" onclick="return confirm('本当に削除しますか？');">削除</a>
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

private struct SmallCategoryPair: Hashable {
    let genreName: String
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
        allowed.remove(charactersIn: "&=+")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

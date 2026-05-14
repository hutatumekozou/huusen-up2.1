import Foundation
import Network

final class WebAdminServer {
    private let settings: OverlaySettings
    private let port: NWEndpoint.Port
    private let showNow: () -> Void
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
        settingsChanged: @escaping () -> Void,
        pauseChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.port = NWEndpoint.Port(rawValue: port)!
        self.showNow = showNow
        self.settingsChanged = settingsChanged
        self.pauseChanged = pauseChanged
    }

    func start() {
        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("Web admin server failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let response = self.response(for: request)
            connection.send(content: response, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for request: String) -> Data {
        let path = requestPath(from: request)

        switch path.path {
        case "/":
            return httpResponse(
                status: "200 OK",
                body: renderPage(message: path.query["message"], tab: path.query["tab"], editID: path.query["edit"])
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
                self.settings.updateGlobalSettings(
                    intervalMinutes: query.doubleValue(for: "intervalMinutes", fallback: self.settings.displayInterval / 60),
                    climbSpeed: query.doubleValue(for: "climbSpeed", fallback: self.settings.climbSpeed)
                )

                if let id = query["id"].flatMap(UUID.init(uuidString:)) {
                    self.settings.updateBalloon(
                        id: id,
                        title: query["title"] ?? "",
                        text: query["balloonText"] ?? "",
                        imageName: query["imageName"],
                        colorName: query["colorName"] ?? OverlaySettings.colorOptions[0].name,
                        positionName: query["positionName"] ?? "中央",
                        pausesAtMiddle: query["pausesAtMiddle"] == "on",
                        middlePauseDuration: query.doubleValue(for: "middlePauseDuration", fallback: 1.0)
                    )
                } else {
                    self.settings.addBalloon(
                        title: query["title"] ?? "",
                        text: query["balloonText"] ?? "",
                        imageName: query["imageName"],
                        colorName: query["colorName"] ?? OverlaySettings.colorOptions[0].name,
                        positionName: query["positionName"] ?? "中央",
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

        let rawPath = String(parts[1])
        var components = URLComponents()
        components.percentEncodedPath = rawPath.components(separatedBy: "?").first ?? "/"
        if let query = rawPath.components(separatedBy: "?").dropFirst().first {
            components.percentEncodedQuery = query
        }

        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
        return (components.path.isEmpty ? "/" : components.path, query)
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

    private func renderPage(message: String?, tab: String?, editID: String?) -> String {
        let intervalMinutes = String(format: "%.1f", settings.displayInterval / 60)
        let climbSpeed = String(format: "%.0f", settings.climbSpeed)
        let activeBalloon = settings.activeBalloon
        let editingID = editID.flatMap(UUID.init(uuidString:))
        let editingBalloon = editingID.flatMap { id in settings.balloons.first(where: { $0.id == id }) }
        let formBalloon = editingBalloon ?? activeBalloon
        let imageName = formBalloon.imageName ?? ""
        let previewText = imageName.isEmpty ? formBalloon.text : imageName
        let selectedTab = editingBalloon != nil ? "create" : (tab == "list" ? "list" : "create")
        let status = settings.isPaused ? "一時停止中" : "稼働中"
        let actionPath = settings.isPaused ? "/resume?tab=\(selectedTab)" : "/pause?tab=\(selectedTab)"
        let actionTitle = settings.isPaused ? "再開" : "一時停止"
        let escapedMessage = message.map { "<p class=\"notice\">\(messageText(for: $0))</p>" } ?? ""
        let colorOptions = renderColorOptions(selectedName: formBalloon.colorName)
        let positionOptions = renderPositionOptions(selectedName: formBalloon.positionName)
        let createTabClass = selectedTab == "create" ? "tab active" : "tab"
        let listTabClass = selectedTab == "list" ? "tab active" : "tab"
        let tabContent = selectedTab == "list"
            ? renderListPanel()
            : renderCreatePanel(
                intervalMinutes: intervalMinutes,
                climbSpeed: climbSpeed,
                activeBalloon: formBalloon,
                editingID: editingBalloon?.id,
                imageName: imageName,
                previewText: previewText,
                colorOptions: colorOptions,
                positionOptions: positionOptions
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
            .preview {
              display: grid;
              grid-template-columns: 110px minmax(0, 1fr);
              gap: 18px;
              align-items: center;
              margin-bottom: 22px;
            }
            .preview-balloon {
              width: 96px;
              height: 120px;
              position: relative;
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
            .preview-knot {
              width: 0;
              height: 0;
              border-left: 9px solid transparent;
              border-right: 9px solid transparent;
              border-top: 15px solid \(formBalloon.colorEndHex);
              margin: -3px auto 0;
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
            input {
              height: 36px;
              border: 1px solid #c7cbd1;
              border-radius: 6px;
              padding: 0 10px;
              font-size: 15px;
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
              gap: 10px;
              margin-top: 14px;
            }
            .item {
              display: grid;
              grid-template-columns: 36px minmax(0, 1fr) auto;
              gap: 12px;
              align-items: center;
              border: 1px solid #e0e3e8;
              border-radius: 8px;
              padding: 10px;
            }
            .item.disabled {
              background: #f8f9fb;
            }
            .item-dot {
              width: 30px;
              height: 30px;
              border-radius: 50%;
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
              background: #e9f2ff;
              color: #184f99;
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
        </body>
        </html>
        """
    }

    private func renderCreatePanel(
        intervalMinutes: String,
        climbSpeed: String,
        activeBalloon: BalloonProfile,
        editingID: UUID?,
        imageName: String,
        previewText: String,
        colorOptions: String,
        positionOptions: String
    ) -> String {
        let hiddenIDInput = editingID.map { "<input type=\"hidden\" name=\"id\" value=\"\($0.uuidString)\">" } ?? ""
        let submitTitle = editingID == nil ? "保存" : "更新"
        let panelTitle = editingID == nil ? "風船作成" : "風船編集"
        let titleValue = editingID == nil ? "" : activeBalloon.title.htmlEscaped
        let resetLink = editingID == nil ? "" : "<a class=\"button\" href=\"/?tab=create\">新規作成に戻す</a>"

        return """
        <section class="panel">
          <form action="/save" method="get">
            \(hiddenIDInput)
            <h2>\(panelTitle)</h2>
            <div class="preview">
              <div class="preview-balloon">
                <div class="preview-body">\(previewText.htmlEscaped)</div>
                <div class="preview-knot"></div>
              </div>
              <div>
                <p class="preview-title">登録中の風船</p>
                <p class="preview-meta">タイトル: \(activeBalloon.title.htmlEscaped)</p>
                <p class="preview-meta">上昇スピード: \(climbSpeed) px/秒</p>
                <p class="preview-meta">上昇位置: \(activeBalloon.positionName.htmlEscaped)</p>
                <p class="preview-meta">中央停止: \(activeBalloon.pausesAtMiddle ? "\(formatDuration(activeBalloon.middlePauseDuration))秒" : "なし")</p>
              </div>
            </div>
            <div class="grid">
              <label class="full">
                タイトル（何の風船かのメモ）
                <input name="title" value="\(titleValue)" placeholder="例: 休憩リマインダー / 水を飲む / 応援メッセージ">
              </label>
              <label>
                表示間隔（分）
                <input name="intervalMinutes" type="number" min="0.1" step="0.1" value="\(intervalMinutes)">
              </label>
              <label>
                上昇スピード（px/秒）
                <input name="climbSpeed" type="number" min="40" max="900" step="10" value="\(climbSpeed)">
              </label>
              <label>
                風船に入れる文字
                <input name="balloonText" value="\(activeBalloon.text.htmlEscaped)" placeholder="例: 🎈 / がんばれ / OK">
              </label>
              <label>
                風船に入れる画像名（Assets）
                <input name="imageName" value="\(imageName.htmlEscaped)" placeholder="未指定なら絵文字">
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

    private func renderListPanel() -> String {
        let operationStatus = settings.isPaused ? "停止中" : "稼働中"
        let enabledCount = settings.enabledBalloons.count

        return """
        <section class="panel">
          <div class="panel-heading">
            <div>
              <h2>作成した風船一覧</h2>
              <p class="heading-meta">全体状態: \(operationStatus) / 稼働中の風船: \(enabledCount)件</p>
            </div>
          </div>
          \(renderBalloonList())
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
        default:
            return message.htmlEscaped
        }
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

    private func renderBalloonList() -> String {
        guard !settings.balloons.isEmpty else {
            return "<p class=\"empty\">まだ風船がありません。</p>"
        }

        return """
        <div class="list">
        \(settings.balloons.reversed().map(renderBalloonListItem).joined(separator: "\n"))
        </div>
        """
    }

    private func renderBalloonListItem(_ balloon: BalloonProfile) -> String {
        let content = balloon.imageName ?? balloon.text
        let activeMark = settings.activeBalloonID == balloon.id ? " / 表示対象" : ""
        let enabledTitle = balloon.isEnabled ? "稼働OFF" : "稼働ON"
        let enabledValue = balloon.isEnabled ? "0" : "1"
        let itemClass = balloon.isEnabled ? "item" : "item disabled"
        let statusClass = balloon.isEnabled ? "item-status" : "item-status off"
        let statusTitle = balloon.isEnabled ? "稼働中" : "停止中"
        let showButton = balloon.isEnabled
            ? "<a class=\"button primary\" href=\"/show?id=\(balloon.id.uuidString)\">表示</a>"
            : "<span class=\"button disabled-control\">表示</span>"
        return """
        <div class="\(itemClass)">
          <div class="item-dot" style="background: linear-gradient(135deg, \(balloon.colorStartHex), \(balloon.colorEndHex));"></div>
          <div>
            <p class="item-title">\(balloon.title.htmlEscaped)\(activeMark)<span class="\(statusClass)">\(statusTitle)</span></p>
            <p class="item-meta">\(balloon.colorName.htmlEscaped) / \(balloon.positionName.htmlEscaped) / \(pauseSummary(for: balloon)) / \(content.htmlEscaped)</p>
          </div>
          <div class="actions">
            <a class="button" href="/toggle-balloon?id=\(balloon.id.uuidString)&enabled=\(enabledValue)">\(enabledTitle)</a>
            \(showButton)
            <a class="button" href="/?tab=create&edit=\(balloon.id.uuidString)">編集</a>
            <a class="button" href="/delete?id=\(balloon.id.uuidString)">削除</a>
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

private extension Dictionary where Key == String, Value == String {
    func doubleValue(for key: String, fallback: Double) -> Double {
        guard let value = self[key], let double = Double(value) else {
            return fallback
        }
        return double
    }

}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

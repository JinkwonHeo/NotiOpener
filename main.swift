import Cocoa
import Carbon

let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NotiOpener.log")

func log(_ msg: String) {
    let line = "\(Date()): \(msg)\n"
    if let handle = try? FileHandle(forWritingTo: logFile) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFile.path, contents: line.data(using: .utf8))
    }
}

// MARK: - AXUIElement 헬퍼

func axChildren(of element: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
          let children = ref as? [AXUIElement] else { return [] }
    return children
}

func axRole(of element: AXUIElement) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success else { return nil }
    return ref as? String
}

func axSubrole(of element: AXUIElement) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &ref) == .success else { return nil }
    return ref as? String
}

func axPosition(of element: AXUIElement) -> CGPoint? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success else { return nil }
    var point = CGPoint.zero
    AXValueGetValue(ref as! AXValue, .cgPoint, &point)
    return point
}

func axSize(of element: AXUIElement) -> CGSize? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success else { return nil }
    var size = CGSize.zero
    AXValueGetValue(ref as! AXValue, .cgSize, &size)
    return size
}

func axActionNames(of element: AXUIElement) -> [String] {
    var ref: CFArray?
    guard AXUIElementCopyActionNames(element, &ref) == .success, let names = ref as? [String] else { return [] }
    return names
}

func axActionDescription(of element: AXUIElement, action: String) -> String {
    var ref: CFString?
    guard AXUIElementCopyActionDescription(element, action as CFString, &ref) == .success else { return "" }
    return ref! as String
}

func axPerformAction(_ action: String, on element: AXUIElement) -> Bool {
    return AXUIElementPerformAction(element, action as CFString) == .success
}

// MARK: - 알림 센터 접근

struct NotifInfo {
    let element: AXUIElement
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

func getNotificationCenterApp() -> AXUIElement? {
    let workspace = NSWorkspace.shared
    for app in workspace.runningApplications {
        if app.bundleIdentifier == "com.apple.notificationcenterui" {
            return AXUIElementCreateApplication(app.processIdentifier)
        }
    }
    return nil
}

func findAlertElements(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 8) -> [NotifInfo] {
    if depth > maxDepth { return [] }
    var results: [NotifInfo] = []

    if axSubrole(of: element) == "AXNotificationCenterAlert" || axSubrole(of: element) == "AXNotificationCenterBanner" {
        if let pos = axPosition(of: element), let size = axSize(of: element), size.width > 0 {
            results.append(NotifInfo(element: element, x: Double(pos.x), y: Double(pos.y), width: Double(size.width), height: Double(size.height)))
            return results
        }
    }

    // AXPress가 있고 적절한 크기의 그룹도 알림일 수 있음
    if depth >= 3, axRole(of: element) == "AXGroup" {
        let actions = axActionNames(of: element)
        let hasClickable = actions.contains("AXPress") || actions.contains { action in
            let desc = axActionDescription(of: element, action: action)
            return desc.contains("보기") || desc.contains("세부사항")
        }
        if hasClickable, let pos = axPosition(of: element), let size = axSize(of: element),
           size.width > 100, size.height > 30 {
            results.append(NotifInfo(element: element, x: Double(pos.x), y: Double(pos.y), width: Double(size.width), height: Double(size.height)))
            return results
        }
    }

    for child in axChildren(of: element) {
        results.append(contentsOf: findAlertElements(child, depth: depth + 1, maxDepth: maxDepth))
    }
    return results
}

func findNotifications() -> [NotifInfo] {
    guard let ncApp = getNotificationCenterApp() else { return [] }

    var results: [NotifInfo] = []
    let windows = axChildren(of: ncApp)
    for window in windows {
        results.append(contentsOf: findAlertElements(window))
    }
    return results
}

func axTitle(of element: AXUIElement) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success else { return nil }
    return ref as? String
}

func axDescription(of element: AXUIElement) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &ref) == .success else { return nil }
    return ref as? String
}

// MARK: - 알림 내용 읽기 (AXDescription 파싱)

struct NotifContent {
    let appName: String
    let title: String
    let subtitle: String
    let body: String
}

func axDescriptionValue(of element: AXUIElement) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &ref) == .success else { return nil }
    return ref as? String
}

func parseNotifContent(_ element: AXUIElement) -> NotifContent? {
    guard let desc = axDescriptionValue(of: element), !desc.isEmpty else { return nil }
    // desc 형식: "앱이름, 제목, 서브타이틀, 내용, 스택" (쉼표 구분)
    let parts = desc.components(separatedBy: ", ")
    guard parts.count >= 2 else { return nil }
    let appName = parts[0]
    let title = parts[1]
    let subtitle = parts.count >= 3 ? parts[2] : ""
    let body = parts.count >= 4 ? parts[3] : ""
    return NotifContent(appName: appName, title: title, subtitle: subtitle, body: body)
}

func readAllNotifContents() -> [(NotifInfo, NotifContent)] {
    let notifs = findNotifications()
    var results: [(NotifInfo, NotifContent)] = []
    for notif in notifs {
        if let content = parseNotifContent(notif.element) {
            results.append((notif, content))
        }
    }
    return results
}

func findShowLessButton(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 8) -> AXUIElement? {
    if depth > maxDepth { return nil }

    if axRole(of: element) == "AXButton" {
        let title = axTitle(of: element) ?? ""
        let desc = axDescription(of: element) ?? ""
        if title.contains("간략히 보기") || desc.contains("간략히 보기")
            || title.contains("Show Less") || desc.contains("Show Less") {
            return element
        }
    }

    for child in axChildren(of: element) {
        if let found = findShowLessButton(child, depth: depth + 1, maxDepth: maxDepth) {
            return found
        }
    }
    return nil
}

func findClearableElements(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 8) -> [AXUIElement] {
    if depth > maxDepth { return [] }
    var results: [AXUIElement] = []

    let subrole = axSubrole(of: element) ?? ""
    let actions = axActionNames(of: element)

    // AlertStack or individual alert with Clear All action
    if subrole == "AXNotificationCenterAlertStack" || subrole == "AXNotificationCenterAlert" || subrole == "AXNotificationCenterBanner" {
        let hasClear = actions.contains { $0.contains("Clear") || $0.contains("Close") || $0.contains("지우기") || $0.contains("닫기") }
        if hasClear {
            results.append(element)
            return results
        }
    }

    for child in axChildren(of: element) {
        results.append(contentsOf: findClearableElements(child, depth: depth + 1, maxDepth: maxDepth))
    }
    return results
}

func clearAllNotifications() {
    let state = NavState.shared
    state.reset()

    guard let ncApp = getNotificationCenterApp() else {
        log("지우기: NotificationCenter 없음")
        return
    }

    var cleared = 0
    for window in axChildren(of: ncApp) {
        let elements = findClearableElements(window)
        for el in elements {
            let actions = axActionNames(of: el)
            for action in actions {
                if action.contains("Clear") || action.contains("Close") || action.contains("지우기") || action.contains("닫기") {
                    if axPerformAction(action, on: el) {
                        cleared += 1
                        log("액션 실행: \(action)")
                    }
                }
            }
        }
    }
    log("알림 지우기: \(cleared)개 처리")
}

func collapseNotifications() {
    let state = NavState.shared
    state.reset()

    guard let ncApp = getNotificationCenterApp() else {
        log("접기: NotificationCenter 없음")
        return
    }

    for window in axChildren(of: ncApp) {
        if let button = findShowLessButton(window) {
            let result = axPerformAction("AXPress", on: button)
            log("간략히 보기 클릭: \(result)")
            return
        }
    }
    log("간략히 보기 버튼 없음")
}

func clickNotification(_ notif: NotifInfo) -> String {
    // AXPress 직접 시도
    if axPerformAction("AXPress", on: notif.element) {
        return "axpress"
    }

    // fallback: AppleScript 위치 기반 클릭
    let script = """
    tell application "System Events"
        tell process "NotificationCenter"
            tell window 1
                try
                    tell group 1
                        tell group 1
                            tell scroll area 1
                                set allGroups to every group
                                repeat with g in allGroups
                                    try
                                        set {xPos, yPos} to position of g
                                        if xPos = \(Int(notif.x)) and yPos = \(Int(notif.y)) then
                                            click g
                                            return "clicked_direct"
                                        end if
                                    end try
                                    set innerGroups to every group of g
                                    repeat with ig in innerGroups
                                        try
                                            set {xPos, yPos} to position of ig
                                            if xPos = \(Int(notif.x)) and yPos = \(Int(notif.y)) then
                                                click ig
                                                return "clicked_inner"
                                            end if
                                        end try
                                    end repeat
                                end repeat
                            end tell
                        end tell
                    end tell
                end try
                return "not_found"
            end tell
        end tell
    end tell
    """
    var error: NSDictionary?
    guard let appleScript = NSAppleScript(source: script) else { return "script_error" }
    let result = appleScript.executeAndReturnError(&error)
    return result.stringValue ?? "nil"
}

// MARK: - 하이라이트 오버레이

class HighlightOverlay {
    static let shared = HighlightOverlay()
    var window: NSWindow?

    func show(at rect: NSRect) {
        if window == nil {
            let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.contentView = BorderView(frame: .zero)
            window = w
        }
        window?.setFrame(rect, display: true)
        window?.contentView?.frame = NSRect(origin: .zero, size: rect.size)
        window?.contentView?.needsDisplay = true
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }
}

class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedRed: 0.2, green: 0.5, blue: 1.0, alpha: 0.15).setFill()
        bounds.fill()
        NSColor(calibratedRed: 0.2, green: 0.5, blue: 1.0, alpha: 0.8).setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        path.lineWidth = 3
        path.stroke()
    }
}

// MARK: - 미리보기 오버레이

class PreviewOverlay {
    static let shared = PreviewOverlay()
    var windows: [NSWindow] = []
    var hideTimer: Timer?

    func show(contents: [(NotifInfo, NotifContent)]) {
        hide()
        guard !contents.isEmpty else { return }
        guard let mainScreen = NSScreen.screens.first else { return }
        let mainHeight = mainScreen.frame.height
        let font = NSFont.systemFont(ofSize: 11, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxTextWidth: CGFloat = 300
        let padding: CGFloat = 8

        for (notif, content) in contents {
            var text = "[\(content.appName)] \(content.title)"
            if !content.subtitle.isEmpty { text += "\n\(content.subtitle)" }
            if !content.body.isEmpty { text += "\n\(content.body)" }

            let textSize = (text as NSString).boundingRect(
                with: NSSize(width: maxTextWidth, height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            ).size

            let winWidth = min(textSize.width + padding * 2, maxTextWidth + padding * 2)
            let winHeight = textSize.height + padding * 2

            // 각 배너의 왼쪽에 세로 중앙 맞춤 배치
            let flippedY = mainHeight - notif.y - notif.height
            let originX = notif.x - winWidth - 8
            let originY = flippedY + (notif.height - winHeight) / 2

            let rect = NSRect(x: originX, y: originY, width: winWidth, height: winHeight)

            let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = true

            let bgView = PreviewBackgroundView(frame: NSRect(origin: .zero, size: rect.size))
            w.contentView = bgView

            let label = NSTextField(wrappingLabelWithString: text)
            label.font = font
            label.textColor = .white
            label.backgroundColor = .clear
            label.isBezeled = false
            label.isEditable = false
            label.frame = NSRect(x: padding, y: padding, width: winWidth - padding * 2, height: winHeight - padding * 2)
            bgView.addSubview(label)

            w.orderFront(nil)
            windows.append(w)
        }

        // 설정된 시간 후 자동 사라짐
        let duration = PreviewOverlay.loadDuration()
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hide()
        }

        log("미리보기 표시: \(contents.count)개 알림")
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
    }

    static func loadDuration() -> TimeInterval {
        let ud = UserDefaults.standard
        let val = ud.double(forKey: "preview_duration")
        return val > 0 ? val : 3.0
    }

    static func saveDuration(_ duration: TimeInterval) {
        UserDefaults.standard.set(duration, forKey: "preview_duration")
    }
}

class PreviewBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.1, alpha: 0.85).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.4, alpha: 0.6).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

// MARK: - 네비게이션 상태

class NavState {
    static let shared = NavState()
    var isNavigating = false
    var currentIndex = 0
    var notifications: [NotifInfo] = []

    func reset() {
        isNavigating = false
        currentIndex = 0
        notifications = []
        DispatchQueue.main.async { HighlightOverlay.shared.hide() }
    }
}

func convertToScreenRect(_ notif: NotifInfo) -> NSRect {
    // AX 좌표: 메인 스크린 top-left가 (0,0), Y는 아래로 증가
    // NSWindow 좌표: 메인 스크린 bottom-left가 (0,0), Y는 위로 증가
    // 변환: flippedY = mainScreenHeight - axY - height
    guard let mainScreen = NSScreen.screens.first else { return .zero }
    let mainHeight = mainScreen.frame.height
    let flippedY = mainHeight - notif.y - notif.height
    return NSRect(x: notif.x, y: flippedY, width: notif.width, height: notif.height)
}

func showHighlight(for notif: NotifInfo) {
    let rect = convertToScreenRect(notif).insetBy(dx: -3, dy: -3)
    HighlightOverlay.shared.show(at: rect)
}

// MARK: - 단축키 설정

struct HotKeyConfig {
    var modifier: UInt32
    var keyCode: UInt32

    static let defaultModifier = UInt32(controlKey)
    static let defaultKeyCode = UInt32(kVK_Return)

    static func load(prefix: String = "hotkey") -> HotKeyConfig {
        let ud = UserDefaults.standard
        if ud.object(forKey: "\(prefix)_modifier") != nil {
            return HotKeyConfig(
                modifier: UInt32(ud.integer(forKey: "\(prefix)_modifier")),
                keyCode: UInt32(ud.integer(forKey: "\(prefix)_keyCode"))
            )
        }
        if prefix == "collapse_hotkey" {
            return HotKeyConfig(modifier: UInt32(controlKey), keyCode: UInt32(kVK_ANSI_Backslash))
        }
        if prefix == "clear_hotkey" {
            return HotKeyConfig(modifier: UInt32(controlKey), keyCode: UInt32(kVK_Delete))
        }
        if prefix == "preview_hotkey" {
            return HotKeyConfig(modifier: UInt32(controlKey), keyCode: UInt32(kVK_ANSI_P))
        }
        return HotKeyConfig(modifier: defaultModifier, keyCode: defaultKeyCode)
    }

    func save(prefix: String = "hotkey") {
        let ud = UserDefaults.standard
        ud.set(Int(modifier), forKey: "\(prefix)_modifier")
        ud.set(Int(keyCode), forKey: "\(prefix)_keyCode")
    }

    func displayString() -> String {
        var parts = ""
        if modifier & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifier & UInt32(optionKey) != 0 { parts += "⌥" }
        if modifier & UInt32(shiftKey) != 0 { parts += "⇧" }
        if modifier & UInt32(cmdKey) != 0 { parts += "⌘" }
        parts += keyCodeToString(keyCode)
        return parts
    }

    /// NSEvent modifier flags → Carbon modifier 변환
    static func carbonModifier(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// Carbon modifier → NSEvent.ModifierFlags 변환
    func cocoaModifierFlags() -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifier & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifier & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifier & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifier & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }
}

func keyCodeToString(_ keyCode: UInt32) -> String {
    switch Int(keyCode) {
    case kVK_Return: return "Return"
    case kVK_Space: return "Space"
    case kVK_Delete: return "Delete"
    case kVK_ForwardDelete: return "⌦"
    case kVK_Escape: return "Esc"
    case kVK_Tab: return "Tab"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_Home: return "Home"
    case kVK_End: return "End"
    case kVK_PageUp: return "PageUp"
    case kVK_PageDown: return "PageDown"
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    case kVK_ANSI_A: return "A"
    case kVK_ANSI_B: return "B"
    case kVK_ANSI_C: return "C"
    case kVK_ANSI_D: return "D"
    case kVK_ANSI_E: return "E"
    case kVK_ANSI_F: return "F"
    case kVK_ANSI_G: return "G"
    case kVK_ANSI_H: return "H"
    case kVK_ANSI_I: return "I"
    case kVK_ANSI_J: return "J"
    case kVK_ANSI_K: return "K"
    case kVK_ANSI_L: return "L"
    case kVK_ANSI_M: return "M"
    case kVK_ANSI_N: return "N"
    case kVK_ANSI_O: return "O"
    case kVK_ANSI_P: return "P"
    case kVK_ANSI_Q: return "Q"
    case kVK_ANSI_R: return "R"
    case kVK_ANSI_S: return "S"
    case kVK_ANSI_T: return "T"
    case kVK_ANSI_U: return "U"
    case kVK_ANSI_V: return "V"
    case kVK_ANSI_W: return "W"
    case kVK_ANSI_X: return "X"
    case kVK_ANSI_Y: return "Y"
    case kVK_ANSI_Z: return "Z"
    case kVK_ANSI_0: return "0"
    case kVK_ANSI_1: return "1"
    case kVK_ANSI_2: return "2"
    case kVK_ANSI_3: return "3"
    case kVK_ANSI_4: return "4"
    case kVK_ANSI_5: return "5"
    case kVK_ANSI_6: return "6"
    case kVK_ANSI_7: return "7"
    case kVK_ANSI_8: return "8"
    case kVK_ANSI_9: return "9"
    case kVK_ANSI_Minus: return "-"
    case kVK_ANSI_Equal: return "="
    case kVK_ANSI_LeftBracket: return "["
    case kVK_ANSI_RightBracket: return "]"
    case kVK_ANSI_Backslash: return "\\"
    case kVK_ANSI_Semicolon: return ";"
    case kVK_ANSI_Quote: return "'"
    case kVK_ANSI_Comma: return ","
    case kVK_ANSI_Period: return "."
    case kVK_ANSI_Slash: return "/"
    case kVK_ANSI_Grave: return "`"
    default: return "Key(\(keyCode))"
    }
}

// MARK: - 이벤트 처리

func handleCtrlEnter() {
    let state = NavState.shared

    if !state.isNavigating {
        let notifs = findNotifications()
        log("Ctrl+Enter - 알림 수: \(notifs.count)")

        if notifs.isEmpty {
            log("알림 없음")
            return
        }

        if notifs.count == 1 {
            let result = clickNotification(notifs[0])
            log("단일 알림: \(result)")

            if result == "detail" || result == "axpress" {
                // 펼쳐졌을 수 있음
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let newNotifs = findNotifications()
                    if newNotifs.count > 1 {
                        state.isNavigating = true
                        state.notifications = newNotifs
                        state.currentIndex = 0
                        showHighlight(for: newNotifs[0])
                        log("펼쳐짐 → 네비게이션 (\(newNotifs.count)개)")
                    }
                }
            }
            return
        }

        state.isNavigating = true
        state.notifications = notifs
        state.currentIndex = 0
        showHighlight(for: notifs[0])
        log("네비게이션 시작 (\(notifs.count)개)")
    } else {
        let notifs = findNotifications()
        if notifs.isEmpty { state.reset(); return }
        state.notifications = notifs
        state.currentIndex = (state.currentIndex + 1) % notifs.count
        showHighlight(for: notifs[state.currentIndex])
        log("다음: \(state.currentIndex + 1)/\(notifs.count)")
    }
}

func handlePreview() {
    let contents = readAllNotifContents()
    if contents.isEmpty {
        log("미리보기: 알림 없음 또는 내용 없음")
        return
    }
    PreviewOverlay.shared.show(contents: contents)
}

func selectCurrentNotification() {
    let state = NavState.shared
    guard state.isNavigating, state.currentIndex < state.notifications.count else {
        state.reset()
        return
    }
    HighlightOverlay.shared.hide()
    let result = clickNotification(state.notifications[state.currentIndex])
    log("선택: \(state.currentIndex + 1), result=\(result)")
    state.reset()
}

// MARK: - App Delegate

// MARK: - 단축키 변경 팝업 윈도우

class ShortcutCaptureWindow: NSWindow {
    var capturedConfig: HotKeyConfig?
    var onApply: ((HotKeyConfig) -> Void)?
    var localKeyMonitor: Any?
    var shortcutLabel: NSTextField!
    var applyButton: NSButton!

    init() {
        let width: CGFloat = 320
        let height: CGFloat = 160
        let screen = NSScreen.main!
        let x = (screen.frame.width - width) / 2
        let y = (screen.frame.height - height) / 2
        let rect = NSRect(x: x, y: y, width: width, height: height)

        super.init(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.title = "단축키 변경"
        self.level = .floating
        self.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        self.contentView = contentView

        let guideLabel = NSTextField(labelWithString: "새 단축키를 입력하세요")
        guideLabel.font = NSFont.systemFont(ofSize: 14)
        guideLabel.alignment = .center
        guideLabel.frame = NSRect(x: 20, y: height - 50, width: width - 40, height: 24)
        contentView.addSubview(guideLabel)

        shortcutLabel = NSTextField(labelWithString: "키 조합 대기 중...")
        shortcutLabel.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
        shortcutLabel.alignment = .center
        shortcutLabel.frame = NSRect(x: 20, y: height - 90, width: width - 40, height: 30)
        contentView.addSubview(shortcutLabel)

        applyButton = NSButton(title: "적용", target: nil, action: nil)
        applyButton.bezelStyle = .rounded
        applyButton.frame = NSRect(x: width / 2 - 100, y: 15, width: 90, height: 32)
        applyButton.target = self
        applyButton.action = #selector(applyClicked)
        applyButton.isEnabled = false
        applyButton.keyEquivalent = "\r"
        contentView.addSubview(applyButton)

        let cancelButton = NSButton(title: "취소", target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: width / 2 + 10, y: 15, width: 90, height: 32)
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)
    }

    func startCapture() {
        capturedConfig = nil
        shortcutLabel.stringValue = "키 조합 대기 중..."
        applyButton.isEnabled = false

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbonMod = HotKeyConfig.carbonModifier(from: flags)

            if carbonMod == 0 {
                return nil
            }

            let config = HotKeyConfig(modifier: carbonMod, keyCode: UInt32(event.keyCode))
            self.capturedConfig = config
            self.shortcutLabel.stringValue = config.displayString()
            self.applyButton.isEnabled = true
            return nil
        }
    }

    func stopCapture() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    @objc func applyClicked() {
        stopCapture()
        if let config = capturedConfig {
            onApply?(config)
        }
        close()
    }

    @objc func cancelClicked() {
        stopCapture()
        close()
    }

    override func close() {
        stopCapture()
        super.close()
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var collapseHotKeyRef: EventHotKeyRef?
    var clearHotKeyRef: EventHotKeyRef?
    var previewHotKeyRef: EventHotKeyRef?
    var hotKeyConfig = HotKeyConfig.load()
    var collapseHotKeyConfig = HotKeyConfig.load(prefix: "collapse_hotkey")
    var clearHotKeyConfig = HotKeyConfig.load(prefix: "clear_hotkey")
    var previewHotKeyConfig = HotKeyConfig.load(prefix: "preview_hotkey")
    var currentShortcutItem: NSMenuItem!
    var collapseShortcutItem: NSMenuItem!
    var clearShortcutItem: NSMenuItem!
    var previewShortcutItem: NSMenuItem!
    var previewDurationItem: NSMenuItem!
    var captureWindow: ShortcutCaptureWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button { button.title = "🔔" }

        let menu = NSMenu()
        currentShortcutItem = NSMenuItem(title: "열기 단축키: \(hotKeyConfig.displayString())", action: nil, keyEquivalent: "")
        menu.addItem(currentShortcutItem)
        let changeItem = NSMenuItem(title: "열기 단축키 변경...", action: #selector(openShortcutWindow), keyEquivalent: "")
        changeItem.target = self
        menu.addItem(changeItem)
        menu.addItem(NSMenuItem.separator())
        collapseShortcutItem = NSMenuItem(title: "접기 단축키: \(collapseHotKeyConfig.displayString())", action: nil, keyEquivalent: "")
        menu.addItem(collapseShortcutItem)
        let changeCollapseItem = NSMenuItem(title: "접기 단축키 변경...", action: #selector(openCollapseShortcutWindow), keyEquivalent: "")
        changeCollapseItem.target = self
        menu.addItem(changeCollapseItem)
        menu.addItem(NSMenuItem.separator())
        clearShortcutItem = NSMenuItem(title: "지우기 단축키: \(clearHotKeyConfig.displayString())", action: nil, keyEquivalent: "")
        menu.addItem(clearShortcutItem)
        let changeClearItem = NSMenuItem(title: "지우기 단축키 변경...", action: #selector(openClearShortcutWindow), keyEquivalent: "")
        changeClearItem.target = self
        menu.addItem(changeClearItem)
        menu.addItem(NSMenuItem.separator())
        previewShortcutItem = NSMenuItem(title: "미리보기 단축키: \(previewHotKeyConfig.displayString())", action: nil, keyEquivalent: "")
        menu.addItem(previewShortcutItem)
        let changePreviewItem = NSMenuItem(title: "미리보기 단축키 변경...", action: #selector(openPreviewShortcutWindow), keyEquivalent: "")
        changePreviewItem.target = self
        menu.addItem(changePreviewItem)
        let dur = PreviewOverlay.loadDuration()
        previewDurationItem = NSMenuItem(title: "미리보기 표시시간: \(String(format: "%.1f", dur))초", action: nil, keyEquivalent: "")
        menu.addItem(previewDurationItem)
        let changeDurationItem = NSMenuItem(title: "미리보기 표시시간 변경...", action: #selector(openDurationWindow), keyEquivalent: "")
        changeDurationItem.target = self
        menu.addItem(changeDurationItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        log("접근성 권한: \(AXIsProcessTrustedWithOptions(options))")

        registerHotKey()
        registerCollapseHotKey()
        registerClearHotKey()
        registerPreviewHotKey()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event!, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async {
                if hotKeyID.id == 1 {
                    handleCtrlEnter()
                } else if hotKeyID.id == 2 {
                    collapseNotifications()
                } else if hotKeyID.id == 3 {
                    clearAllNotifications()
                } else if hotKeyID.id == 4 {
                    handlePreview()
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            let state = NavState.shared
            if state.isNavigating {
                let requiredFlags = self.hotKeyConfig.cocoaModifierFlags()
                let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if !currentFlags.contains(requiredFlags) {
                    DispatchQueue.main.async { selectCurrentNotification() }
                }
            }
        }

        log("앱 시작 완료")
    }

    func registerHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E434C4B), id: 1)
        RegisterEventHotKey(hotKeyConfig.keyCode, hotKeyConfig.modifier, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        log("열기 HotKey 등록: \(hotKeyConfig.displayString())")
    }

    func registerCollapseHotKey() {
        if let ref = collapseHotKeyRef {
            UnregisterEventHotKey(ref)
            collapseHotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E434C4B), id: 2)
        RegisterEventHotKey(collapseHotKeyConfig.keyCode, collapseHotKeyConfig.modifier, hotKeyID, GetApplicationEventTarget(), 0, &collapseHotKeyRef)
        log("접기 HotKey 등록: \(collapseHotKeyConfig.displayString())")
    }

    func registerClearHotKey() {
        if let ref = clearHotKeyRef {
            UnregisterEventHotKey(ref)
            clearHotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E434C4B), id: 3)
        RegisterEventHotKey(clearHotKeyConfig.keyCode, clearHotKeyConfig.modifier, hotKeyID, GetApplicationEventTarget(), 0, &clearHotKeyRef)
        log("지우기 HotKey 등록: \(clearHotKeyConfig.displayString())")
    }

    func registerPreviewHotKey() {
        if let ref = previewHotKeyRef {
            UnregisterEventHotKey(ref)
            previewHotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E434C4B), id: 4)
        RegisterEventHotKey(previewHotKeyConfig.keyCode, previewHotKeyConfig.modifier, hotKeyID, GetApplicationEventTarget(), 0, &previewHotKeyRef)
        log("미리보기 HotKey 등록: \(previewHotKeyConfig.displayString())")
    }

    @objc func openDurationWindow() {
        NSApp.setActivationPolicy(.regular)

        let width: CGFloat = 280
        let height: CGFloat = 140
        let screen = NSScreen.main!
        let x = (screen.frame.width - width) / 2
        let y = (screen.frame.height - height) / 2
        let rect = NSRect(x: x, y: y, width: width, height: height)

        let win = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "미리보기 표시시간"
        win.level = .floating
        win.isReleasedWhenClosed = false

        let cv = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        win.contentView = cv

        let label = NSTextField(labelWithString: "표시시간 (초)")
        label.font = NSFont.systemFont(ofSize: 14)
        label.frame = NSRect(x: 20, y: height - 45, width: 120, height: 24)
        cv.addSubview(label)

        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = 30
        stepper.increment = 0.5
        stepper.doubleValue = PreviewOverlay.loadDuration()
        stepper.frame = NSRect(x: width - 50, y: height - 80, width: 20, height: 24)
        cv.addSubview(stepper)

        let valueLabel = NSTextField(labelWithString: String(format: "%.1f", stepper.doubleValue))
        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
        valueLabel.alignment = .center
        valueLabel.frame = NSRect(x: 60, y: height - 85, width: width - 130, height: 30)
        cv.addSubview(valueLabel)

        stepper.target = self
        stepper.tag = 999
        objc_setAssociatedObject(stepper, "valueLabel", valueLabel, .OBJC_ASSOCIATION_RETAIN)
        stepper.action = #selector(stepperChanged(_:))

        let applyBtn = NSButton(title: "적용", target: self, action: #selector(applyDuration(_:)))
        applyBtn.bezelStyle = .rounded
        applyBtn.frame = NSRect(x: width / 2 - 100, y: 15, width: 90, height: 32)
        applyBtn.keyEquivalent = "\r"
        objc_setAssociatedObject(applyBtn, "stepper", stepper, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(applyBtn, "window", win, .OBJC_ASSOCIATION_RETAIN)
        cv.addSubview(applyBtn)

        let cancelBtn = NSButton(title: "취소", target: self, action: #selector(cancelDuration(_:)))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.frame = NSRect(x: width / 2 + 10, y: 15, width: 90, height: 32)
        cancelBtn.keyEquivalent = "\u{1b}"
        objc_setAssociatedObject(cancelBtn, "window", win, .OBJC_ASSOCIATION_RETAIN)
        cv.addSubview(cancelBtn)

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func stepperChanged(_ sender: NSStepper) {
        if let label = objc_getAssociatedObject(sender, "valueLabel") as? NSTextField {
            label.stringValue = String(format: "%.1f", sender.doubleValue)
        }
    }

    @objc func applyDuration(_ sender: NSButton) {
        if let stepper = objc_getAssociatedObject(sender, "stepper") as? NSStepper {
            let duration = stepper.doubleValue
            PreviewOverlay.saveDuration(duration)
            previewDurationItem.title = "미리보기 표시시간: \(String(format: "%.1f", duration))초"
            log("미리보기 표시시간 변경: \(duration)초")
        }
        if let win = objc_getAssociatedObject(sender, "window") as? NSWindow {
            win.close()
        }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func cancelDuration(_ sender: NSButton) {
        if let win = objc_getAssociatedObject(sender, "window") as? NSWindow {
            win.close()
        }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func openPreviewShortcutWindow() {
        NSApp.setActivationPolicy(.regular)

        let window = ShortcutCaptureWindow()
        window.title = "미리보기 단축키 변경"
        window.onApply = { [weak self] config in
            guard let self = self else { return }
            self.previewHotKeyConfig = config
            self.previewHotKeyConfig.save(prefix: "preview_hotkey")
            self.registerPreviewHotKey()
            self.previewShortcutItem.title = "미리보기 단축키: \(self.previewHotKeyConfig.displayString())"
            log("미리보기 단축키 변경: \(self.previewHotKeyConfig.displayString())")
            NSApp.setActivationPolicy(.accessory)
        }
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.startCapture()
        NSApp.activate(ignoringOtherApps: true)
        captureWindow = window
    }

    @objc func openShortcutWindow() {
        NSApp.setActivationPolicy(.regular)

        let window = ShortcutCaptureWindow()
        window.title = "열기 단축키 변경"
        window.onApply = { [weak self] config in
            guard let self = self else { return }
            self.hotKeyConfig = config
            self.hotKeyConfig.save()
            self.registerHotKey()
            self.currentShortcutItem.title = "열기 단축키: \(self.hotKeyConfig.displayString())"
            log("열기 단축키 변경: \(self.hotKeyConfig.displayString())")
            NSApp.setActivationPolicy(.accessory)
        }
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.startCapture()
        NSApp.activate(ignoringOtherApps: true)
        captureWindow = window
    }

    @objc func openClearShortcutWindow() {
        NSApp.setActivationPolicy(.regular)

        let window = ShortcutCaptureWindow()
        window.title = "지우기 단축키 변경"
        window.onApply = { [weak self] config in
            guard let self = self else { return }
            self.clearHotKeyConfig = config
            self.clearHotKeyConfig.save(prefix: "clear_hotkey")
            self.registerClearHotKey()
            self.clearShortcutItem.title = "지우기 단축키: \(self.clearHotKeyConfig.displayString())"
            log("지우기 단축키 변경: \(self.clearHotKeyConfig.displayString())")
            NSApp.setActivationPolicy(.accessory)
        }
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.startCapture()
        NSApp.activate(ignoringOtherApps: true)
        captureWindow = window
    }

    @objc func openCollapseShortcutWindow() {
        NSApp.setActivationPolicy(.regular)

        let window = ShortcutCaptureWindow()
        window.title = "접기 단축키 변경"
        window.onApply = { [weak self] config in
            guard let self = self else { return }
            self.collapseHotKeyConfig = config
            self.collapseHotKeyConfig.save(prefix: "collapse_hotkey")
            self.registerCollapseHotKey()
            self.collapseShortcutItem.title = "접기 단축키: \(self.collapseHotKeyConfig.displayString())"
            log("접기 단축키 변경: \(self.collapseHotKeyConfig.displayString())")
            NSApp.setActivationPolicy(.accessory)
        }
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.startCapture()
        NSApp.activate(ignoringOtherApps: true)
        captureWindow = window
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        captureWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

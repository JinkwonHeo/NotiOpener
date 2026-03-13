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

    static func load() -> HotKeyConfig {
        let ud = UserDefaults.standard
        if ud.object(forKey: "hotkey_modifier") != nil {
            return HotKeyConfig(
                modifier: UInt32(ud.integer(forKey: "hotkey_modifier")),
                keyCode: UInt32(ud.integer(forKey: "hotkey_keyCode"))
            )
        }
        return HotKeyConfig(modifier: defaultModifier, keyCode: defaultKeyCode)
    }

    func save() {
        let ud = UserDefaults.standard
        ud.set(Int(modifier), forKey: "hotkey_modifier")
        ud.set(Int(keyCode), forKey: "hotkey_keyCode")
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
    var hotKeyConfig = HotKeyConfig.load()
    var currentShortcutItem: NSMenuItem!
    var captureWindow: ShortcutCaptureWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button { button.title = "🔔" }

        let menu = NSMenu()
        currentShortcutItem = NSMenuItem(title: "현재 단축키: \(hotKeyConfig.displayString())", action: nil, keyEquivalent: "")
        menu.addItem(currentShortcutItem)
        let changeItem = NSMenuItem(title: "단축키 변경...", action: #selector(openShortcutWindow), keyEquivalent: "")
        changeItem.target = self
        menu.addItem(changeItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        log("접근성 권한: \(AXIsProcessTrustedWithOptions(options))")

        registerHotKey()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            DispatchQueue.main.async { handleCtrlEnter() }
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
        log("HotKey 등록: \(hotKeyConfig.displayString())")
    }

    @objc func openShortcutWindow() {
        NSApp.setActivationPolicy(.regular)

        let window = ShortcutCaptureWindow()
        window.onApply = { [weak self] config in
            guard let self = self else { return }
            self.hotKeyConfig = config
            self.hotKeyConfig.save()
            self.registerHotKey()
            self.currentShortcutItem.title = "현재 단축키: \(self.hotKeyConfig.displayString())"
            log("단축키 변경: \(self.hotKeyConfig.displayString())")
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

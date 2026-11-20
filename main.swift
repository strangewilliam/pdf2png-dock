import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

private let supportedExtensions = Set(["pdf", "png", "jpg", "jpeg", "tif", "tiff", "bmp"])

/// 找一个装了 PyMuPDF(fitz) 与 Pillow 的 Python。
/// 可用环境变量 PDF2PNG_PYTHON 指定；否则按常见路径探测。
private func findPython() -> String? {
    let fm = FileManager.default
    if let custom = ProcessInfo.processInfo.environment["PDF2PNG_PYTHON"],
       fm.isExecutableFile(atPath: custom) {
        return custom
    }
    let candidates = [
        "/opt/anaconda3/bin/python",
        "/opt/anaconda3/bin/python3",
        "/usr/local/bin/python3",
        "/opt/homebrew/bin/python3",
        "/usr/bin/python3",
    ]
    for path in candidates where fm.isExecutableFile(atPath: path) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["-c", "import fitz, PIL"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            continue
        }
        if task.terminationStatus == 0 { return path }
    }
    return nil
}

/// 优先用 App 内置的脚本；可用环境变量 PDF2PNG_SCRIPT 覆盖；最后兼容 ~/bin/pdf2png.py。
private func findScript() -> String? {
    let fm = FileManager.default
    if let custom = ProcessInfo.processInfo.environment["PDF2PNG_SCRIPT"],
       fm.fileExists(atPath: custom) {
        return custom
    }
    if let bundled = Bundle.main.url(forResource: "pdf2png", withExtension: "py") {
        return bundled.path
    }
    let legacy = NSHomeDirectory() + "/bin/pdf2png.py"
    return fm.fileExists(atPath: legacy) ? legacy : nil
}

// MARK: - 菜单栏图标上的拖放接收视图
final class MenuBarDropView: NSView {
    weak var owner: MenuBarApp?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func mouseDown(with event: NSEvent) {
        owner?.showMenu()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        owner?.setHighlight(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        owner?.setHighlight(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        owner?.setHighlight(false)
        let pasteboard = sender.draggingPasteboard
        var urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        if urls.isEmpty, let raw = pasteboard.string(forType: .fileURL), let url = URL(string: raw) {
            urls = [url]
        }
        guard !urls.isEmpty else { return false }
        owner?.process(urls)
        return true
    }
}

// MARK: - 主程序
final class MenuBarApp: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var dropView: MenuBarDropView!
    private var autoStartItem: NSMenuItem!
    private var pythonPath: String?
    private var scriptPath: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        pythonPath = findPython()
        scriptPath = findScript()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: "PDF2PNG")
        button.toolTip = "PDF2PNG · 拖入 PDF/图片转换，或点击打开菜单"

        dropView = MenuBarDropView(frame: button.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.owner = self
        button.addSubview(dropView)

        buildMenu()
    }

    private func buildMenu() {
        menu = NSMenu()

        let open = NSMenuItem(title: "选择 PDF 或图片…", action: #selector(chooseFiles), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        menu.addItem(NSMenuItem.separator())

        autoStartItem = NSMenuItem(title: "登录时启动", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartItem.target = self
        menu.addItem(autoStartItem)

        let help = NSMenuItem(title: "使用说明", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "退出 PDF2PNG", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        refreshAutoStartTitle()
    }

    fileprivate func showMenu() {
        refreshAutoStartTitle()
        statusItem.popUpMenu(menu)
    }

    fileprivate func setHighlight(_ on: Bool) {
        statusItem.button?.contentTintColor = on ? .controlAccentColor : nil
    }

    // MARK: 处理文件
    fileprivate func process(_ urls: [URL]) {
        let valid = urls.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
        guard !valid.isEmpty else {
            notify(title: "PDF2PNG", body: "没有可处理的文件，支持 PDF / PNG / JPG / TIFF / BMP")
            return
        }
        guard let python = pythonPath, let script = scriptPath else {
            notify(title: "PDF2PNG 依赖缺失", body: "需要 Python 3 及 PyMuPDF、Pillow；详见 README")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: python)
        task.arguments = [script] + valid.map { $0.path }
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            notify(title: "PDF2PNG 启动失败", body: error.localizedDescription)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            let savedCount = output.split(separator: "\n").filter { $0.hasPrefix("保存:") }.count
            let ok = task.terminationStatus == 0 && output.contains("__DONE__")

            DispatchQueue.main.async {
                if ok {
                    self?.notify(title: "PDF2PNG 完成", body: "已生成 \(savedCount) 张去白边 PNG，保存在桌面")
                } else {
                    self?.notify(title: "PDF2PNG 处理出错", body: String(output.prefix(200)))
                }
            }
        }
    }

    @objc private func chooseFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择 PDF 或图片"
        panel.message = "可一次选择多个文件"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.pdf, .png, .jpeg, .tiff, .bmp].compactMap { $0 }
        } else {
            panel.allowedFileTypes = Array(supportedExtensions)
        }
        panel.begin { [weak self] result in
            if result == .OK { self?.process(panel.urls) }
        }
    }

    @objc private func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "PDF2PNG 菜单栏小组件"
        alert.informativeText = "把 PDF 或图片拖到顶部菜单栏的 PDF2PNG 图标上，即可转换为 PNG 并自动去白边，结果保存在桌面。\n\nPDF 的每一页会生成一张 PNG；也可以点击图标选择多个文件批量处理。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: 登录时启动（LaunchAgent）
    private var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.local.pdf2pngdock.plist")
    }

    private func isAutoStartEnabled() -> Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    private func refreshAutoStartTitle() {
        autoStartItem?.title = isAutoStartEnabled() ? "✓ 登录时启动" : "登录时启动"
    }

    @objc private func toggleAutoStart() {
        let fm = FileManager.default
        if fm.fileExists(atPath: agentURL.path) {
            try? fm.removeItem(at: agentURL)
            _ = runLaunchctl("unload", agentURL.path)
        } else {
            let executable = Bundle.main.executablePath ?? (CommandLine.arguments.first ?? "")
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>com.local.pdf2pngdock</string>
              <key>ProgramArguments</key><array><string>\(executable)</string></array>
              <key>RunAtLoad</key><true/>
              <key>KeepAlive</key><false/>
            </dict></plist>
            """
            do {
                try fm.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try xml.write(to: agentURL, atomically: true, encoding: .utf8)
                _ = runLaunchctl("load", agentURL.path)
            } catch {
                notify(title: "设置开机启动失败", body: error.localizedDescription)
            }
        }
        refreshAutoStartTitle()
    }

    private func runLaunchctl(_ command: String, _ path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [command, path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return error.localizedDescription
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: 通知
    fileprivate func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 12.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}

let app = NSApplication.shared
let delegate = MenuBarApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 不显示 Dock 图标与主菜单，只在菜单栏
app.run()

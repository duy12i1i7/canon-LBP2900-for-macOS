// LBP2900Progress — a tiny macOS menu-bar app that shows live print progress
// for the Canon LBP2900 print queue.
//
// Why this exists: Apple's own "Printing N of M" widget is frozen at "1" for
// non-AirPrint / host-based CUPS printers (it polls the printer over IPP, which
// a raw USB CAPT device can't answer). The CUPS job counter the driver updates
// *is* correct, so this app reads that and shows it in the menu bar instead.
//
// Build:  swiftc -O LBP2900Progress.swift -o LBP2900Progress
// Runs as an accessory (no Dock icon). Quit from its menu.

import Cocoa

let QUEUE = "Canon_LBP2900"
let POLL_SECONDS = 1.5

final class ProgressWatcher: NSObject {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statusLine = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
    var timer: Timer?
    let testFile: String

    override init() {
        // Write the IPP query once to a temp file.
        testFile = NSTemporaryDirectory() + "lbp2900-progress.test"
        let ipp = """
        { OPERATION Get-Jobs
          GROUP operation-attributes-tag
          ATTR charset attributes-charset utf-8
          ATTR naturalLanguage attributes-natural-language en
          ATTR uri printer-uri $uri
          ATTR keyword which-jobs not-completed
          ATTR keyword requested-attributes job-id,job-name,job-media-sheets-completed,job-impressions
        }
        """
        try? ipp.write(toFile: testFile, atomically: true, encoding: .utf8)
        super.init()

        statusItem.button?.title = "🖨"
        let menu = NSMenu()
        let header = NSMenuItem(title: "Canon LBP2900", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(statusLine)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        timer = Timer.scheduledTimer(timeInterval: POLL_SECONDS, target: self,
                                     selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        poll()
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    // Returns (jobName, current, total) — current/total may be nil.
    func query() -> (String?, Int?, Int?)? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ipptool")
        task.arguments = ["-tv", "ipp://localhost/printers/\(QUEUE)", testFile]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return nil }

        var haveJob = false
        var name: String? = nil
        var current: Int? = nil
        var total: Int? = nil
        for line in out.split(separator: "\n") {
            // Only lines like:  attr (type) = value
            guard let eq = line.range(of: " = ") else { continue }
            let value = String(line[eq.upperBound...])
            if line.contains("job-id (integer)") { haveJob = true }
            else if line.contains("job-name (name") { name = value }
            else if line.contains("job-media-sheets-completed (integer)") { current = Int(value) }
            else if line.contains("job-impressions (integer)") { total = Int(value) }
        }
        return haveJob ? (name, current, total) : nil
    }

    @objc func poll() {
        DispatchQueue.global(qos: .background).async {
            let r = self.query()
            DispatchQueue.main.async { self.render(r) }
        }
    }

    func render(_ r: (String?, Int?, Int?)?) {
        guard let (name, current, total) = r else {
            statusItem.button?.title = "🖨"
            statusLine.title = "Idle — no active job"
            return
        }
        let cur = current ?? 0
        var title: String
        var line: String
        if cur == 0 {
            title = "🖨 …"
            line = "Preparing…"
        } else if let t = total, cur <= t {
            title = "🖨 \(cur)/\(t)"
            line = "Printing page \(cur) of \(t)"
        } else {
            title = "🖨 \(cur)"
            line = "Printing page \(cur)"
        }
        if let n = name, !n.isEmpty { line += " — \(n)" }
        statusItem.button?.title = title
        statusLine.title = line
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
let watcher = ProgressWatcher()
app.run()

// Timer: the sample island plugin, and the template for writing one.
//
// A plugin is a folder with a plugin.json and a program. The app runs the program in that folder and reads
// what to show from its stdout, one JSON object per line; taps come back on its stdin the same way. It quits
// when its stdin closes (the app quit, or you switched its tab off).
//
//   island -> plugin   {"type":"action","id":"..."}     a row or button with that id was tapped
//                      {"type":"visible","tab":true}    its tab opened (false: closed)
//   plugin -> island   compact, list, buttons, popup, clear (see PluginMessage in the app)
//
// Build: swiftc -O main.swift -o timer
import Foundation

/// Writes one message. stdout is a pipe, so flush every line or the island sees nothing
func send(_ message: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
    data.append(UInt8(ascii: "\n"))
    FileHandle.standardOutput.write(data)
}

let presets = [5, 15, 25]

var total: TimeInterval = 0
var endDate: Date?
/// Time left while paused
var pausedRemaining: TimeInterval?

var remaining: TimeInterval {
    if let pausedRemaining { return pausedRemaining }
    guard let endDate else { return 0 }
    return max(0, endDate.timeIntervalSinceNow)
}

func clock(_ seconds: TimeInterval) -> String {
    let whole = Int(seconds.rounded(.up))
    return String(format: "%02d:%02d", whole / 60, whole % 60)
}

func showTab() {
    let running = endDate != nil || pausedRemaining != nil
    send(["type": "list", "rows": presets.map { minutes in
        ["id": "start-\(minutes)", "title": "\(minutes) min", "subtitle": minutes == 25 ? "Pomodoro" : "Countdown",
         "symbol": "play.circle"]
    }])
    if !running {
        send(["type": "clear", "target": "buttons"])
    } else if pausedRemaining != nil {
        send(["type": "buttons", "buttons": [["id": "resume", "title": "Resume", "symbol": "play.fill"],
                                             ["id": "stop", "title": "Stop", "symbol": "stop.fill"]]])
    } else {
        send(["type": "buttons", "buttons": [["id": "pause", "title": "Pause", "symbol": "pause.fill"],
                                             ["id": "stop", "title": "Stop", "symbol": "stop.fill"]]])
    }
}

func showCompact() {
    guard endDate != nil || pausedRemaining != nil, total > 0 else {
        send(["type": "clear", "target": "compact"])
        return
    }
    send(["type": "compact", "symbol": pausedRemaining == nil ? "timer" : "pause.fill",
          "text": clock(remaining), "progress": remaining / total])
}

func stop() {
    endDate = nil
    pausedRemaining = nil
    showCompact()
    showTab()
}

func handle(_ line: String) {
    guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          object["type"] as? String == "action", let id = object["id"] as? String else { return }
    switch id {
    case "pause":
        pausedRemaining = remaining
        endDate = nil
    case "resume":
        if let pausedRemaining { endDate = Date().addingTimeInterval(pausedRemaining) }
        pausedRemaining = nil
    case "stop":
        stop()
        return
    default:
        guard id.hasPrefix("start-"), let minutes = Int(id.dropFirst("start-".count)) else { return }
        total = TimeInterval(minutes * 60)
        endDate = Date().addingTimeInterval(total)
        pausedRemaining = nil
    }
    showCompact()
    showTab()
}

// Taps arrive on stdin; reading blocks, so it gets its own thread. End of input: the app wants us gone
Thread.detachNewThread {
    while let line = readLine() {
        DispatchQueue.main.async { handle(line) }
    }
    exit(0)
}

// The countdown, once a second
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    guard endDate != nil else { return }
    if remaining <= 0 {
        send(["type": "popup", "symbol": "bell.fill", "text": "Time's up", "seconds": 4])
        stop()
    } else {
        showCompact()
    }
}

showTab()
RunLoop.main.run()

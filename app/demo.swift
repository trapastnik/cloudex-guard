// Демо-режим для записи GIF и скриншотов: настоящее приложение, но с выдуманными чатами.
// Запуск: CLOUDEX_DEMO=1 (см. app/demo.sh). Что меняется:
// - данные берутся из временной папки, которую приложение само заполняет при старте;
// - интерфейс на английском (CLOUDEX_DEMO_LANG=ru — на русском);
// - не трогаются настройки, мод, автозапуск и папка данных настоящего приложения.

import AppKit

let isDemo = ProcessInfo.processInfo.environment["CLOUDEX_DEMO"] == "1"

enum Demo {
  static let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cloudex-guard-demo")
  static let country = "US"

  // (название, группа, процент, токены, минут назад, состояние для «Ждут вас»)
  static let chats: [(String, String, Int, Int, Double, String?)] = [
    ("payments migration", "backend", 84, 168_000, 25, nil),
    ("api: OAuth refactor", "backend", 64, 128_000, 2, "asking"),
    ("landing page copy", "site", 47, 94_000, 6, "done"),
    ("release notes v2", "docs", 31, 62_000, 130, nil),
    ("flaky e2e tests", "qa", 22, 44_000, 40, nil),
    ("db index tuning", "backend", 12, 24_000, 190, nil),
  ]

  static func populate() {
    let fm = FileManager.default
    try? fm.removeItem(at: dir)
    for sub in ["status", "alive", "requests"] {
      try? fm.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
    }
    let now = Date().timeIntervalSince1970 * 1000
    for (index, chat) in chats.enumerated() {
      let id = "local_demo-\(index)"
      let updated = now - chat.4 * 60_000
      let row: [String: Any] = [
        "id": id, "title": chat.0, "group": chat.1, "cwd": "/demo",
        "tokens": chat.3, "window": 200_000, "percent": chat.2, "updatedAt": updated,
      ]
      write(row, to: dir.appendingPathComponent("\(id).json"))
      try? String(Int(now)).write(to: dir.appendingPathComponent("alive/\(id)"), atomically: true, encoding: .utf8)
      if let state = chat.5 {
        write(["state": state, "at": updated], to: dir.appendingPathComponent("status/\(id).json"))
      }
    }
    let iso = ISO8601DateFormatter()
    let limits: [String: Any] = ["rateLimits": [
      ["kind": "five_hour", "percentUsed": 47, "resetsAt": iso.string(from: Date().addingTimeInterval(2 * 3600 + 10 * 60))],
      ["kind": "seven_day", "percentUsed": 23, "resetsAt": iso.string(from: Date().addingTimeInterval(3 * 86400))],
    ], "updatedAt": now]
    write(limits, to: dir.appendingPathComponent("_limits.json"))
  }

  private static func write(_ object: [String: Any], to url: URL) {
    if let data = try? JSONSerialization.data(withJSONObject: object) { try? data.write(to: url) }
  }
}

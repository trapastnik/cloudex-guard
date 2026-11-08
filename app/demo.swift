// Демо-режим для записи GIF и скриншотов: настоящее приложение, но с выдуманными чатами.
// Запуск: CLOUDEX_DEMO=1 (см. app/demo.sh). Что меняется:
// - данные берутся из временной папки, которую приложение само заполняет при старте;
// - интерфейс на английском (CLOUDEX_DEMO_LANG=ru — на русском);
// - сеть не проверяется и ничего не замораживается; в меню вместо адреса — пример из диапазона
//   для документации (203.0.113.0/24, RFC 5737), это не чей-то настоящий адрес;
// - не трогаются настройки, мод, автозапуск и папка данных настоящего приложения.

import AppKit

let isDemo = ProcessInfo.processInfo.environment["CLOUDEX_DEMO"] == "1"

enum Demo {
  static let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cloudex-guard-demo")
  static let country = "US"
  static let ip = "203.0.113.24"

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

  // Сценарий «сеть» для записи стража: demo.sh net пишет сюда ok / jump и переключает фазу по Enter.
  // Это только отображение: настоящие программы демо не замораживает.
  static let phaseFile = dir.appendingPathComponent("net-phase")
  static let jumpCountry = "BR"
  static let jumpIP = "198.51.100.7"
  static let guardedApps = [("Claude", "com.anthropic.claudefordesktop"), ("ChatGPT", "com.openai.chat")]

  static var isJumped: Bool {
    (try? String(contentsOf: phaseFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == "jump"
  }

  // Начало заголовка в строке меню — как у настоящего стража: флаг или красное «❄︎BR».
  static func networkTitle() -> NSAttributedString {
    if isJumped {
      return NSAttributedString(string: "❄︎\(jumpCountry) ", attributes: [
        .foregroundColor: NSColor.systemRed, .font: NSFont.boldSystemFont(ofSize: 13),
      ])
    }
    return NSAttributedString(string: flag(country) + " ")
  }

  // Сетевая часть меню в демо: те же строки, что у настоящего стража, но без действий.
  static func addNetworkSection(to menu: NSMenu) {
    let jumped = isJumped
    let text = NSMutableAttributedString(string: "\(flag(jumped ? jumpCountry : country)) \(jumped ? jumpCountry : country)  ", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
    text.append(NSAttributedString(string: jumped ? jumpIP : ip, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]))
    text.append(NSAttributedString(string: "   0 " + t("min", "мин"), attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.menuFont(ofSize: 12)]))
    menu.addItem(plain(text))
    if jumped {
      let names = guardedApps.map(\.0).sorted().joined(separator: ", ")
      let line = "❄︎ " + t("Paused: ", "Заморожено: ") + names + t(" — resumes when your address is allowed again", " — отпущу, когда адрес станет разрешённым")
      menu.addItem(plain(NSAttributedString(string: line, attributes: [.foregroundColor: NSColor.systemRed])))
      menu.addItem(plain(NSAttributedString(string: t("Resume and leave alone for 15 minutes", "Разморозить и не трогать 15 минут"))))
    }
    let protection = NSMenuItem(title: t("Network guard", "Защита"), action: nil, keyEquivalent: "")
    protection.submenu = protectionMenu()
    menu.addItem(protection)
    menu.addItem(plain(NSAttributedString(string: t("How others see us…", "Как нас видят…"))))
    menu.addItem(.separator())
  }

  // Подменю «Защита» как у настоящего приложения: программы и разрешённые страны с галочками.
  static func protectionMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(checked(t("Pause apps on a wrong network", "Заморозка включена"), true))
    menu.addItem(.separator())
    menu.addItem(header(t("Apps — paused together with everything they started", "Программы — замораживаются вместе со всем, что запустили")))
    for (name, bundleID) in guardedApps {
      let item = checked(name, true)
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        item.image = NSWorkspace.shared.icon(forFile: url.path)
        item.image?.size = NSSize(width: 16, height: 16)
      }
      menu.addItem(item)
    }
    menu.addItem(.separator())
    menu.addItem(header(t("Allowed countries — apps run only from these", "Разрешённые страны — с них программы работают")))
    menu.addItem(checked("\(flag(jumpCountry)) \(jumpCountry)", false))
    menu.addItem(checked("\(flag(country)) \(country)", true))
    menu.addItem(.separator())
    menu.addItem(checked(t("Pause guard for 15 minutes", "Пауза на 15 минут"), false))
    return menu
  }

  private static func plain(_ text: NSAttributedString) -> NSMenuItem {
    let item = NSMenuItem(title: text.string, action: nil, keyEquivalent: "")
    item.attributedTitle = text
    item.isEnabled = true
    return item
  }

  private static func checked(_ title: String, _ on: Bool) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.state = on ? .on : .off
    item.isEnabled = true
    return item
  }

  private static func header(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }
}

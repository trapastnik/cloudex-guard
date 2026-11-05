// Раздел «Сеть» в меню ContextMeter: адрес и страна, заморозка, настройки защиты.

import AppKit

extension App {
  // Начало заголовка в строке меню: флаг страны; ⚠︎ — адрес не разрешён; ❄︎ — программы заморожены.
  func networkTitle() -> NSAttributedString {
    let guardian = NetGuard.shared
    let country = guardian.shownCountry ?? "?"
    if !guardian.frozen.isEmpty {
      return NSAttributedString(string: "❄︎\(country) ", attributes: [
        .foregroundColor: NSColor.systemRed, .font: NSFont.boldSystemFont(ofSize: 13),
      ])
    }
    if guardian.overall == .bad {
      return NSAttributedString(string: "⚠︎\(country) ", attributes: [.foregroundColor: NSColor.systemOrange])
    }
    guard let shown = guardian.shownCountry else { return NSAttributedString(string: "") }
    return NSAttributedString(string: flag(shown) + " ")
  }

  func addNetworkSection(to menu: NSMenu) {
    let guardian = NetGuard.shared
    let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let gray = NSColor.secondaryLabelColor

    // Адрес: как видит Claude, и общий, если он другой.
    let status = NSMutableAttributedString()
    if let claude = guardian.views["claude.ai"] {
      status.append(NSAttributedString(string: "\(flag(claude.country)) \(claude.country)  ", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]))
      status.append(NSAttributedString(string: claude.ip, attributes: [.font: mono]))
    } else if let general = guardian.general {
      status.append(NSAttributedString(string: "\(flag(general.country)) \(general.country)  ", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]))
      status.append(NSAttributedString(string: general.ip, attributes: [.font: mono]))
    } else {
      status.append(NSAttributedString(string: guardian.isChecking ? "Проверяю адрес…" : "Адрес не определён — нет связи?"))
    }
    if let at = guardian.checkedAt {
      status.append(NSAttributedString(string: "   \(ago(at))", attributes: [.foregroundColor: gray, .font: NSFont.menuFont(ofSize: 12)]))
    }
    menu.addItem(info(status))

    // Раздельная маршрутизация и IPv6 — отдельной строкой, только когда есть что сказать.
    var notes: [String] = []
    if let claude = guardian.views["claude.ai"], let general = guardian.general, general.country != claude.country {
      notes.append("сервисы IP видят \(flag(general.country)) \(general.country) — VPN ведёт трафик разными путями")
    }
    if let disagreement = guardian.disagreement { notes.append("второй сервис назвал другой адрес: \(disagreement)") }
    if let v6 = guardian.v6 { notes.append("IPv6: \(flag(v6.country)) \(v6.country) \(v6.ip)") }
    for note in notes {
      menu.addItem(info(NSAttributedString(string: "   " + note, attributes: [.foregroundColor: gray, .font: NSFont.menuFont(ofSize: 12)])))
    }

    if !guardian.frozen.isEmpty {
      let line = "❄︎ Заморожено: \(guardian.frozenApps.joined(separator: ", ")) — отпущу, когда адрес станет разрешённым"
      menu.addItem(info(NSAttributedString(string: line, attributes: [.foregroundColor: NSColor.systemRed])))
      menu.addItem(action("Разморозить и не трогать 15 минут", #selector(pause15)))
    } else if guardian.allowed.isEmpty || guardian.guarded.isEmpty {
      menu.addItem(info(NSAttributedString(string: "Заморозка выключена: выберите страны и программы в «Защите»",
                                           attributes: [.foregroundColor: gray, .font: NSFont.menuFont(ofSize: 12)])))
    } else if let until = guardian.pausedUntil, until > Date() {
      menu.addItem(info(NSAttributedString(string: "Защита на паузе до \(Self.clock(until))", attributes: [.foregroundColor: NSColor.systemOrange])))
    }

    let protection = NSMenuItem(title: "Защита", action: nil, keyEquivalent: "")
    protection.submenu = protectionMenu()
    menu.addItem(protection)
    menu.addItem(action("Проверить адрес сейчас", #selector(checkNow)))
    menu.addItem(action("Как нас видят…", #selector(showLeaks)))
    menu.addItem(.separator())
  }

  func protectionMenu() -> NSMenu {
    let guardian = NetGuard.shared
    let menu = NSMenu()
    menu.autoenablesItems = false

    let enabled = action("Заморозка включена", #selector(toggleEnabled))
    enabled.state = guardian.isEnabled ? .on : .off
    menu.addItem(enabled)

    menu.addItem(.separator())
    menu.addItem(header("Программы — замораживаются вместе со всем, что запустили"))
    let guarded = guardian.guarded
    var offered = Guarded.installed()
    for app in guarded where !offered.contains(where: { $0.path == app.path }) { offered.append(app) }
    for app in offered {
      let item = action(app.name, #selector(toggleApp(_:)))
      item.representedObject = app
      item.state = guarded.contains(where: { $0.path == app.path }) ? .on : .off
      item.image = NSWorkspace.shared.icon(forFile: app.path)
      item.image?.size = NSSize(width: 16, height: 16)
      menu.addItem(item)
    }
    menu.addItem(action("Добавить программу…", #selector(addApp)))

    menu.addItem(.separator())
    menu.addItem(header("Разрешённые страны — с них программы работают"))
    var countries = guardian.allowed
    if let shown = guardian.shownCountry { countries.insert(shown) }
    for view in guardian.views.values { countries.insert(view.country) }
    if let general = guardian.general { countries.insert(general.country) }
    for country in countries.sorted() {
      let item = action("\(flag(country)) \(country)", #selector(toggleCountry(_:)))
      item.representedObject = country
      item.state = guardian.allowed.contains(country) ? .on : .off
      menu.addItem(item)
    }

    menu.addItem(.separator())
    if let until = guardian.pausedUntil, until > Date() {
      menu.addItem(action("Снять паузу (сейчас до \(Self.clock(until)))", #selector(unpause)))
    } else {
      menu.addItem(action("Пауза на 15 минут", #selector(pause15)))
      menu.addItem(action("Пауза на 1 час", #selector(pause60)))
    }
    return menu
  }

  private func info(_ text: NSAttributedString) -> NSMenuItem {
    let item = NSMenuItem(title: text.string, action: nil, keyEquivalent: "")
    item.attributedTitle = text
    item.isEnabled = true
    return item
  }

  private func header(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
    item.target = self
    item.isEnabled = true
    return item
  }

  static func clock(_ date: Date) -> String {
    let format = DateFormatter()
    format.dateFormat = "HH:mm"
    return format.string(from: date)
  }

  @objc func toggleEnabled() { NetGuard.shared.isEnabled.toggle() }

  @objc func toggleApp(_ sender: NSMenuItem) {
    guard let app = sender.representedObject as? Guarded else { return }
    var list = NetGuard.shared.guarded
    if let index = list.firstIndex(where: { $0.path == app.path }) { list.remove(at: index) } else { list.append(app) }
    NetGuard.shared.guarded = list
  }

  @objc func addApp() {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.prompt = "Защищать"
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    var list = NetGuard.shared.guarded
    if !list.contains(where: { $0.path == url.path }) { list.append(Guarded(name: name, path: url.path, probe: nil)) }
    NetGuard.shared.guarded = list
  }

  @objc func toggleCountry(_ sender: NSMenuItem) {
    guard let country = sender.representedObject as? String else { return }
    var allowed = NetGuard.shared.allowed
    if allowed.contains(country) { allowed.remove(country) } else { allowed.insert(country) }
    NetGuard.shared.allowed = allowed
  }

  @objc func pause15() { NetGuard.shared.pausedUntil = Date().addingTimeInterval(15 * 60) }
  @objc func pause60() { NetGuard.shared.pausedUntil = Date().addingTimeInterval(60 * 60) }
  @objc func unpause() { NetGuard.shared.pausedUntil = nil }
  @objc func checkNow() { NetGuard.shared.check() }
  @objc func showLeaks() { LeakWindow.show() }
}

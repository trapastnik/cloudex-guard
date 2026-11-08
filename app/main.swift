// Cloudex Guard — строка меню с заполнением контекста всех чатов Claude.
// Данные пишет мод ~/.claude/mods/cloudex-guard: по файлу на чат в ~/.claude/cloudex-guard.
// Приложение не ходит в сеть. Страж сети с 1.2 — отдельное приложение Cloudex Shield.

import AppKit

let dataDir = isDemo ? Demo.dir : FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(".claude/cloudex-guard")
// Обновление идёт по событию от macOS, когда мод пишет файл; таймер — редкая подстраховка.
let fallbackSeconds = 60.0
// Чаты, не отвечавшие дольше, уходят в подменю «Давно не активные»; ещё дольше — скрыты.
let requestsDir = dataDir.appendingPathComponent("requests")
// Запущенный чат обновляет alive/<адрес> раз в минуту; старше этого — чат спит.
let aliveDir = dataDir.appendingPathComponent("alive")
let aliveSeconds = 150.0
// Текст просьбы — тот же, что мод отправляет сам (CLEANUP_TEXT в register.tsx).
let cleanupText = t(
  "Your context is getting large. When you can, please save everything in detail to the project docs, write a detailed handoff and a short text I can paste back into this chat after clearing it — after that we will clear this chat.",
  "У тебя достаточно большой контекст, когда сможешь, пожалуйста сохрани все подробно в документации напиши подробный Handoff и короткий текст, который я вставлю в этот же чат после очистки, после чего будем тебя чистить.")

func isAlive(_ id: String) -> Bool {
  guard let text = try? String(contentsOf: aliveDir.appendingPathComponent(id), encoding: .utf8),
        let beat = Double(text) else { return false }
  return Date().timeIntervalSince1970 - beat / 1000 < aliveSeconds
}
let staleDays = 3.0
let recentCount = 10
let hiddenDays = 30.0
// Файл чата, молчащего дольше, удаляется при запуске приложения (вместе со служебными отметками).
let chatDays = 60.0

struct Chat: Decodable {
  let id: String
  let title: String
  let group: String?
  let link: String?
  let tokens: Int
  let window: Int
  let percent: Int
  let updatedAt: Double

  var updated: Date {
    Date(timeIntervalSince1970: updatedAt > 1e12 ? updatedAt / 1000 : updatedAt)
  }
}

// Процент из чужого файла: NaN или огромное число не должны ронять приложение.
func whole(_ value: Double) -> Int {
  value.isFinite ? Int(min(max(value, 0), 1000).rounded()) : 0
}

func color(_ percent: Int) -> NSColor {
  switch percent {
  case ..<40: return .systemGreen
  case ..<60: return .systemYellow
  case ..<80: return .systemOrange
  default: return .systemRed
  }
}

func short(_ n: Int) -> String {
  n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000)
    : n >= 1000 ? "\(Int((Double(n) / 1000).rounded()))k" : "\(n)"
}

func ago(_ date: Date) -> String {
  let minutes = Int(-date.timeIntervalSinceNow / 60)
  if minutes < 60 { return "\(max(minutes, 0)) " + t("min", "мин") }
  if minutes < 60 * 24 { return "\(minutes / 60) " + t("h", "ч") }
  return "\(minutes / 60 / 24) " + t("d", "дн")
}

func dot(_ percent: Int, size: CGFloat) -> NSAttributedString {
  NSAttributedString(string: "● ", attributes: [
    .foregroundColor: color(percent),
    .font: NSFont.systemFont(ofSize: size),
  ])
}

struct Limit: Decodable {
  let kind: String
  let percentUsed: Double
  let resetsAt: String?

  var name: String {
    switch kind {
    case "five_hour": return t("5 h", "5 ч")
    case "seven_day": return t("Week", "Неделя")
    case "spend_limit": return t("Spend", "Расход")
    default:
      // seven_day_fable → «Неделя Fable» и подобные окна по моделям.
      let model = kind.replacingOccurrences(of: "seven_day_", with: "").capitalized
      return kind.hasPrefix("seven_day_") ? t("Wk ", "Нед. ") + model : kind
    }
  }

  // Короткая метка для строки меню, где каждая точка на счету: «5ч», «Н», «Н·F».
  var tag: String {
    switch kind {
    case "five_hour": return t("5h", "5ч")
    case "seven_day": return t("W", "Н")
    case "spend_limit": return "$"
    default: return kind.hasPrefix("seven_day_") ? t("W·", "Н·") + kind.dropFirst(10).prefix(1).uppercased() : kind
    }
  }

  var resets: Date? {
    guard let resetsAt else { return nil }
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return parser.date(from: resetsAt) ?? ISO8601DateFormatter().date(from: resetsAt)
  }
}

struct Limits: Decodable {
  let rateLimits: [Limit]
}

func loadLimits() -> [Limit] {
  let file = dataDir.appendingPathComponent("_limits.json")
  return (try? JSONDecoder().decode(Limits.self, from: Data(contentsOf: file)))?.rateLimits ?? []
}

// Через сколько сброс: «2 ч 58 мин» в пределах суток, дальше — день недели и время.
func until(_ date: Date?) -> String {
  guard let date else { return "" }
  let minutes = Int(date.timeIntervalSinceNow / 60)
  if minutes <= 0 { return t("reset", "сброшен") }
  if minutes < 60 * 24 { return minutes < 60 ? "\(minutes) " + t("min", "мин") : "\(minutes / 60) \(t("h", "ч")) \(minutes % 60) \(t("min", "мин"))" }
  let format = DateFormatter()
  format.locale = Locale(identifier: isRussian ? "ru_RU" : "en_US")
  format.dateFormat = "EE HH:mm"
  return format.string(from: date)
}

// Полоска из 10 делений: «▰▰▰▱▱▱▱▱▱▱».
func bar(_ percent: Double) -> String {
  let filled = min(10, whole(percent / 10))
  return String(repeating: "▰", count: filled) + String(repeating: "▱", count: 10 - filled)
}

// «Ждут вас»: ✋ — чат стоит, пока вы не дадите разрешение или не ответите на вопрос;
// 💬 — чат закончил ход в последний час, а вы ему ещё не написали. Пишет мод: status/<адрес>.json.
enum Waiting { case asking, ready }

let statusDir = dataDir.appendingPathComponent("status")

func waiting(_ chat: Chat) -> Waiting? {
  guard let data = try? Data(contentsOf: statusDir.appendingPathComponent("\(chat.id).json")),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let state = object["state"] as? String, let at = object["at"] as? Double else { return nil }
  let age = Date().timeIntervalSince1970 - at / 1000
  if state == "asking" && age < 12 * 3600 && isAlive(chat.id) { return .asking }  // закрытый чат ничего не ждёт
  if state == "done" && age < 3600 { return .ready }
  return nil
}

func loadChats() -> [Chat] {
  let files = (try? FileManager.default.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil)) ?? []
  return files
    .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("local_") }
    .compactMap { try? JSONDecoder().decode(Chat.self, from: Data(contentsOf: $0)) }
    .filter { -$0.updated.timeIntervalSinceNow < hiddenDays * 86400 }
    .sorted { $0.percent > $1.percent }
}

final class RowView: NSView {
  let chat: Chat
  let isPending: Bool
  let cleanButton = NSButton()
  var hover = false { didSet { needsDisplay = true } }

  init(chat: Chat, text: NSAttributedString, isPending: Bool) {
    self.chat = chat
    self.isPending = isPending
    super.init(frame: .zero)
    let label = NSTextField(labelWithAttributedString: text)
    label.lineBreakMode = .byTruncatingMiddle
    cleanButton.isBordered = false
    cleanButton.title = isPending ? "⏳" : "🧹"
    cleanButton.toolTip = isPending
      ? t("Request is waiting: the chat is asleep. Click to open it with the text on your clipboard", "Просьба ждёт: чат спит. Нажмите — откроется чат, текст будет в буфере обмена")
      : t("Ask the chat to save docs and a handoff before you clear it", "Попросить чат сохранить документацию и handoff перед очисткой")
    cleanButton.target = self
    cleanButton.action = #selector(askCleanup)
    let stack = NSStackView(views: [label, cleanButton])
    stack.orientation = .horizontal
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 3, left: 14, bottom: 3, right: 10)
    stack.translatesAutoresizingMaskIntoConstraints = false
    label.setContentHuggingPriority(.defaultLow, for: .horizontal)
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      widthAnchor.constraint(lessThanOrEqualToConstant: 640),
    ])
    frame.size = fittingSize
  }

  required init?(coder: NSCoder) { nil }

  override func updateTrackingAreas() {
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
  }

  override func mouseEntered(with event: NSEvent) { hover = true }
  override func mouseExited(with event: NSEvent) { hover = false }

  override func draw(_ dirtyRect: NSRect) {
    guard hover else { return }
    NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
  }

  static func open(_ chat: Chat) {
    if let link = chat.link, let url = URL(string: link) { NSWorkspace.shared.open(url) }
  }

  // Спящий чат открытием не будится: открываем его и кладём текст в буфер обмена.
  static func pasteIntoSleeping(_ chat: Chat) {
    try? FileManager.default.removeItem(at: requestsDir.appendingPathComponent("\(chat.id).json"))
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(cleanupText, forType: .string)
    open(chat)
    let alert = NSAlert()
    alert.messageText = t("“\(chat.title)” is asleep", "Чат «\(chat.title)» спит")
    alert.informativeText = t("It is open now and the request is on your clipboard — paste it into the chat (⌘V) and press Enter.", "Он открыт, текст просьбы в буфере обмена — вставьте его в чат (⌘V) и нажмите Enter.")
    alert.addButton(withTitle: t("OK", "Понятно"))
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
    open(chat)
  }

  // Клик по строке (не по кнопке) открывает чат.
  override func mouseUp(with event: NSEvent) {
    enclosingMenuItem?.menu?.cancelTracking()
    RowView.open(chat)
  }

  @objc func askCleanup() {
    enclosingMenuItem?.menu?.cancelTracking()
    let chat = self.chat
    let isPending = self.isPending
    DispatchQueue.main.async {
      let isAwake = isAlive(chat.id)
      if isPending {
        if isAwake { RowView.open(chat) } else { RowView.pasteIntoSleeping(chat) }
        return
      }
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = t("Prepare “\(chat.title)” for clearing?", "Подготовить «\(chat.title)» к очистке?")
      alert.informativeText = isAwake
        ? t("The chat will be asked to save everything to the docs, write a detailed handoff and a short text to paste back after clearing. The message is sent when the chat is free.", "Чат получит просьбу сохранить всё в документации, написать подробный handoff и короткий текст для вставки после очистки. Сообщение уйдёт, когда чат освободится.")
        : t("The chat is asleep and won’t get the request by itself. It will open with the text on your clipboard — just paste (⌘V) and press Enter.", "Чат спит, сам он просьбу не получит. Чат откроется, а текст просьбы окажется в буфере обмена — останется вставить (⌘V) и нажать Enter.")
      alert.addButton(withTitle: isAwake ? t("Send", "Отправить") : t("Open and copy", "Открыть и скопировать"))
      alert.addButton(withTitle: t("Cancel", "Отмена"))
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      guard isAwake else {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cleanupText, forType: .string)
        RowView.open(chat)
        return
      }
      try? FileManager.default.createDirectory(at: requestsDir, withIntermediateDirectories: true)
      let body: [String: Any] = ["createdAt": Int(Date().timeIntervalSince1970 * 1000), "text": cleanupText]
      if let data = try? JSONSerialization.data(withJSONObject: body) {
        try? data.write(to: requestsDir.appendingPathComponent("\(chat.id).json"))
      }
    }
  }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
  let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  var stream: FSEventStreamRef?

  func applicationDidFinishLaunching(_ note: Notification) {
    if isDemo { Demo.populate() }
    item.autosaveName = isDemo ? "Cloudex Guard Demo" : "Cloudex Guard"
    item.menu = NSMenu()
    item.menu?.delegate = self
    // Строки лимитов без действия должны выглядеть обычными, а не серыми.
    item.menu?.autoenablesItems = false
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    refresh()
    watch()
    let timer = Timer(timeInterval: fallbackSeconds, repeats: true) { [weak self] _ in self?.refresh() }
    timer.tolerance = fallbackSeconds / 2
    RunLoop.main.add(timer, forMode: .common)
    pruneOldFiles()
    if !isDemo { Setup.onLaunch(); ShieldNotice.onLaunch() }  // демо не ставит мод и автозапуск
  }

  // Старые файлы: просьбы 🧹 старше суток, отметки и состояния чатов, молчащих больше 30 дней,
  // и сами файлы чатов, молчащих больше 60 дней (из меню они пропадают раньше — через 30).
  func pruneOldFiles() {
    let now = Date()
    let chats = (try? FileManager.default.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    for file in chats where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
      let changed = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
      if now.timeIntervalSince(changed) > chatDays * 86400 { try? FileManager.default.removeItem(at: file) }
    }
    for (folder, days) in [(requestsDir, 1.0), (aliveDir, 30.0), (statusDir, 30.0)] {
      let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
      for file in files {
        let changed = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
        if now.timeIntervalSince(changed) > days * 86400 { try? FileManager.default.removeItem(at: file) }
      }
    }
  }

  // Ждёт событий папки данных без опроса (FSEvents, с изменениями файлов на месте);
  // записи за секунду система сводит в одно событие.
  func watch() {
    var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
    let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
      guard let info else { return }
      // Отметки «чат запущен» приходят каждую минуту и на строку меню не влияют.
      let changed = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
      if !changed.isEmpty && changed.allSatisfy({ $0.contains("/alive/") }) { return }
      Unmanaged<App>.fromOpaque(info).takeUnretainedValue().refresh()
    }
    let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
    guard let created = FSEventStreamCreate(nil, callback, &context, [dataDir.path] as CFArray,
                                            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else { return }
    FSEventStreamSetDispatchQueue(created, .main)
    FSEventStreamStart(created)
    stream = created
  }

  // Заголовок в строке меню: цвет и процент самого заполненного активного чата, и сколько красных.
  func refresh() {
    let active = loadChats().filter { -$0.updated.timeIntervalSinceNow < staleDays * 86400 }
    let title = NSMutableAttributedString()
    if let top = active.first {
      title.append(dot(top.percent, size: 13))
      title.append(NSAttributedString(string: "\(top.percent)%"))
      let red = active.filter { $0.percent >= 80 }.count
      if red > 1 { title.append(NSAttributedString(string: " ·\(red)")) }
      let asking = loadChats().filter { waiting($0) == .asking }.count
      if asking > 0 {
        title.append(NSAttributedString(string: " ✋\(asking)", attributes: [.foregroundColor: NSColor.systemOrange]))
      }
    } else {
      title.append(NSAttributedString(string: "◌ ctx"))
    }
    // Лимит в строке меню — только когда он близок к концу.
    if let hot = loadLimits().filter({ $0.percentUsed >= 80 }).max(by: { $0.percentUsed < $1.percentUsed }) {
      title.append(NSAttributedString(string: " \(hot.tag)\(whole(hot.percentUsed))", attributes: [
        .foregroundColor: color(whole(hot.percentUsed)),
      ]))
    }
    item.button?.attributedTitle = title
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let chats = loadChats()
    let active = chats.filter { -$0.updated.timeIntervalSinceNow < staleDays * 86400 }
    let stale = chats.filter { -$0.updated.timeIntervalSinceNow >= staleDays * 86400 }

    if !isDemo && !Setup.isConnected && Setup.modSource != nil {
      menu.addItem(withTitle: t("Connect to Claude Code…", "Подключить к Claude Code…"), action: #selector(connect), keyEquivalent: "").target = self
      menu.addItem(.separator())
    }
    let limits = loadLimits()
    for limit in limits { menu.addItem(limitRow(limit)) }
    if !limits.isEmpty { menu.addItem(.separator()) }

    // Сначала те, кто ждёт решения, потом — у кого готов ответ, свежие выше.
    let asking = chats.filter { waiting($0) == .asking }
    let ready = chats.filter { waiting($0) == .ready }
    let waitingChats: [Chat] = (asking + ready.sorted { $0.updatedAt > $1.updatedAt })
    if !waitingChats.isEmpty {
      let header = NSMenuItem(title: t("Waiting for you", "Ждут вас"), action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
      for chat in waitingChats { menu.addItem(row(chat)) }
      menu.addItem(.separator())
    }

    if chats.isEmpty {
      menu.addItem(NSMenuItem(title: t("No data yet — any chat reply will create it", "Пока нет данных — ответ в любом чате их создаст"), action: nil, keyEquivalent: ""))
    }
    if !chats.isEmpty {
      // Подменю по времени последнего ответа, а основной список — по заполненности.
      let recent = NSMenu()
      recent.autoenablesItems = false
      for chat in chats.sorted(by: { $0.updated > $1.updated }).prefix(recentCount) { recent.addItem(row(chat)) }
      let holder = NSMenuItem(title: t("Recent \(min(recentCount, chats.count)) chats", "Последние \(min(recentCount, chats.count)) чатов"), action: nil, keyEquivalent: "")
      holder.submenu = recent
      menu.addItem(holder)
      menu.addItem(.separator())
    }
    for chat in active { menu.addItem(row(chat)) }
    if !stale.isEmpty {
      let sub = NSMenu()
      for chat in stale { sub.addItem(row(chat)) }
      let holder = NSMenuItem(title: t("Inactive (\(stale.count))", "Давно не активные (\(stale.count))"), action: nil, keyEquivalent: "")
      holder.submenu = sub
      menu.addItem(.separator())
      menu.addItem(holder)
    }
    menu.addItem(.separator())
    menu.addItem(withTitle: t("Open data folder", "Открыть папку данных"), action: #selector(openDir), keyEquivalent: "").target = self
    menu.addItem(withTitle: t("Also from us: Cloudex Shield — pause apps when your VPN drops ↗", "Ещё от нас: Cloudex Shield — пауза программ, когда VPN отвалился ↗"),
                 action: #selector(openShield), keyEquivalent: "").target = self
    menu.addItem(withTitle: t("Support Cloudex Guard ♥", "Поддержать Cloudex Guard ♥"), action: #selector(support), keyEquivalent: "").target = self
    menu.addItem(withTitle: t("Quit Cloudex Guard", "Выйти из Cloudex Guard"), action: #selector(quit), keyEquivalent: "q").target = self
  }

  // «5 ч      ▰▱▱▱▱▱▱▱▱▱   5%  2 ч 58 мин»
  func limitRow(_ limit: Limit) -> NSMenuItem {
    let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let percent = whole(limit.percentUsed)
    let text = NSMutableAttributedString()
    text.append(NSAttributedString(string: limit.name.padding(toLength: 10, withPad: " ", startingAt: 0), attributes: [.font: mono]))
    text.append(NSAttributedString(string: bar(limit.percentUsed), attributes: [.font: mono, .foregroundColor: color(percent)]))
    text.append(NSAttributedString(string: String(format: " %3d%%", percent), attributes: [.font: mono]))
    text.append(NSAttributedString(string: "  " + until(limit.resets), attributes: [
      .font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
    ]))
    let menuItem = NSMenuItem(title: limit.name, action: nil, keyEquivalent: "")
    menuItem.attributedTitle = text
    menuItem.isEnabled = true
    return menuItem
  }

  // Строка чата: клик по тексту открывает чат, 🧹 просит его подготовиться к очистке.
  func row(_ chat: Chat) -> NSMenuItem {
    let text = NSMutableAttributedString()
    switch waiting(chat) {
    case .asking: text.append(NSAttributedString(string: "✋ "))
    case .ready: text.append(NSAttributedString(string: "💬 "))
    case nil: break
    }
    text.append(dot(chat.percent, size: 14))
    text.append(NSAttributedString(string: String(format: "%3d%%  ", chat.percent), attributes: [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
    ]))
    text.append(NSAttributedString(string: chat.title, attributes: [.font: NSFont.menuFont(ofSize: 14)]))
    let details = [chat.group, "\(short(chat.tokens)) / \(short(chat.window))", ago(chat.updated)]
      .compactMap { $0 }.joined(separator: " · ")
    text.append(NSAttributedString(string: "   " + details, attributes: [
      .foregroundColor: NSColor.secondaryLabelColor,
      .font: NSFont.menuFont(ofSize: 12),
    ]))
    let menuItem = NSMenuItem()
    menuItem.view = RowView(chat: chat, text: text, isPending: isPending(chat.id))
    return menuItem
  }

  func isPending(_ id: String) -> Bool {
    let request = requestsDir.appendingPathComponent("\(id).json")
    let ack = requestsDir.appendingPathComponent("\(id).ack")
    guard let data = try? Data(contentsOf: request),
          let createdAt = (try? JSONSerialization.jsonObject(with: data) as? [String: Double])?["createdAt"]
    else { return false }
    let done = (try? String(contentsOf: ack, encoding: .utf8)).flatMap { Double($0) } ?? 0
    let age = Date().timeIntervalSince1970 - createdAt / 1000
    return createdAt > done && age < 600  // мод не выполняет просьбы старше 10 минут
  }

  @objc func connect() { Setup.ask() }

  @objc func openShield() {
    if let url = URL(string: shieldURL) { NSWorkspace.shared.open(url) }
  }

  @objc func support() {
    if let url = URL(string: supportURL) { NSWorkspace.shared.open(url) }
  }

  @objc func openDir() {
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    NSWorkspace.shared.open(dataDir)
  }

  @objc func quit() { NSApp.terminate(nil) }
}

// Место значка по умолчанию — правее, ближе к часам: левые значки при переполненной
// строке меню уходят под вырез экрана и пропадают. Перетаскивание с ⌘ macOS запоминает
// под тем же ключом, и тогда эта настройка его не трогает.
let supportURL = "https://github.com/trapastnik/cloudex-guard#support"
let shieldURL = "https://medfab-dev.tech/cloudex-shield/"
let positionKey = "NSStatusItem Preferred Position Cloudex Guard"
if UserDefaults.standard.object(forKey: positionKey) == nil {
  UserDefaults.standard.set(260.0, forKey: positionKey)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

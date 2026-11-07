// Подключение к Claude Code из самого приложения — для установки из DMG без терминала.
// Мод лежит внутри бандла (Contents/Resources/mod). С согласия пользователя приложение
// копирует его в ~/.claude/mods/cloudex-guard, дописывает путь в env-блок ~/.claude/settings.json
// (исходник сохраняется рядом, остальное в файле не трогается) и включает запуск при входе.

import AppKit

enum Setup {
  static let home = FileManager.default.homeDirectoryForCurrentUser
  static let modDest = home.appendingPathComponent(".claude/mods/cloudex-guard")
  static let settings = home.appendingPathComponent(".claude/settings.json")
  static let agentLabel = "io.github.trapastnik.cloudex-guard"
  static let agent = home.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
  static var modSource: URL? { Bundle.main.resourceURL?.appendingPathComponent("mod") }

  // Подключено: мод на месте и его путь есть в настройках Claude Code.
  static var isConnected: Bool {
    guard FileManager.default.fileExists(atPath: modDest.appendingPathComponent("hooks/register.tsx").path),
          let data = try? Data(contentsOf: settings),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let env = object["env"] as? [String: Any],
          let dirs = env["CLAUDE_CODE_PLUGIN_DIRS"] as? String else { return false }
    return dirs.split(separator: ":").contains { String($0) == modDest.path }
  }

  static func version(of mod: URL) -> String? {
    guard let data = try? Data(contentsOf: mod.appendingPathComponent(".claude-plugin/plugin.json")),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return object["version"] as? String
  }

  // При запуске: подключённый мод обновляется вместе с приложением; неподключённое — предлагаем.
  static func onLaunch() {
    if isConnected {
      if let source = modSource, version(of: source) != version(of: modDest) { try? copyMod() }
      return
    }
    guard modSource != nil, UserDefaults.standard.object(forKey: "setupDeclined") == nil else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ask() }
  }

  static func ask() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = t("Connect Cloudex Guard to Claude Code?", "Подключить Cloudex Guard к Claude Code?")
    alert.informativeText = t(
      "Cloudex Guard will install its small mod into ~/.claude/mods/cloudex-guard, add it to ~/.claude/settings.json (the original is saved next to it as settings.json.before-cloudex-guard; nothing else in the file changes) and start at login. Then restart the Claude app.",
      "Cloudex Guard поставит свой небольшой мод в ~/.claude/mods/cloudex-guard, добавит его в ~/.claude/settings.json (исходный файл сохранится рядом как settings.json.before-cloudex-guard, остальное в нём не изменится) и будет запускаться при входе. Затем перезапустите Claude.")
    alert.addButton(withTitle: t("Connect", "Подключить"))
    alert.addButton(withTitle: t("Not now", "Не сейчас"))
    guard alert.runModal() == .alertFirstButtonReturn else {
      UserDefaults.standard.set(true, forKey: "setupDeclined")
      return
    }
    let done = NSAlert()
    do {
      try connect()
      done.messageText = t("Connected", "Подключено")
      done.informativeText = t("Restart the Claude app. Each chat appears in the menu after its next reply.",
                               "Перезапустите приложение Claude. Каждый чат появится в меню после своего следующего ответа.")
    } catch {
      done.alertStyle = .warning
      done.messageText = t("Couldn’t connect", "Подключить не удалось")
      done.informativeText = error.localizedDescription
    }
    done.runModal()
  }

  static func connect() throws {
    try copyMod()
    let manager = FileManager.default
    let backup = settings.deletingLastPathComponent().appendingPathComponent("settings.json.before-cloudex-guard")
    if manager.fileExists(atPath: settings.path) && !manager.fileExists(atPath: backup.path) {
      try manager.copyItem(at: settings, to: backup)
    }
    let result = try mergeSettings()
    if result == "invalid" {
      throw NSError(domain: "CloudexGuard", code: 1, userInfo: [NSLocalizedDescriptionKey: t(
        "~/.claude/settings.json isn’t valid JSON, so it was left alone. Fix it and try again from the menu.",
        "~/.claude/settings.json — некорректный JSON, его не трогали. Исправьте файл и повторите из меню.")])
    }
    try enableLoginStart()
  }

  static func copyMod() throws {
    guard let source = modSource else { return }
    let manager = FileManager.default
    try manager.createDirectory(at: modDest.deletingLastPathComponent(), withIntermediateDirectories: true)
    let staging = modDest.deletingLastPathComponent().appendingPathComponent(".cloudex-guard-new")
    try? manager.removeItem(at: staging)
    try manager.copyItem(at: source, to: staging)
    if manager.fileExists(atPath: modDest.path) { try manager.removeItem(at: modDest) }
    try manager.moveItem(at: staging, to: modDest)
  }

  // Правка JSON через JavaScript for Automation: он есть в каждой macOS и сохраняет порядок ключей.
  // Пути ранних версий проекта (context-meter, claudex, cloudex) убираются, чтобы мод не загрузился дважды.
  static func mergeSettings() throws -> String {
    let script = #"""
    function run(argv) {
      const [path, mod] = argv
      ObjC.import('Foundation')
      let data = {}
      if ($.NSFileManager.defaultManager.fileExistsAtPath(path)) {
        const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null).js
        try { data = text.trim() === '' ? {} : JSON.parse(text) } catch (e) { return 'invalid' }
      }
      data.env = data.env || {}
      const legacy = /\/\.claude\/mods\/(context-meter|claudex|cloudex)$/
      const dirs = (data.env.CLAUDE_CODE_PLUGIN_DIRS || '').split(':').filter(d => d !== '' && d !== mod && !legacy.test(d))
      dirs.push(mod)
      data.env.CLAUDE_CODE_PLUGIN_DIRS = dirs.join(':')
      data.env.CLAUDE_CODE_PLUGIN_DIR_WATCH = '1'
      $(JSON.stringify(data, null, 2) + '\n').writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)
      return 'changed'
    }
    """#
    try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-l", "JavaScript", "-e", script, settings.path, modDest.path]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()
    return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // Запуск при входе: агент вызывает /usr/bin/open — как двойной клик — и раз в минуту поднимает
  // упавшее приложение, чтобы оно отпустило замороженные программы.
  static func enableLoginStart() throws {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key><string>\(agentLabel)</string>
      <key>ProgramArguments</key>
      <array><string>/usr/bin/open</string><string>-g</string><string>\(Bundle.main.bundlePath)</string></array>
      <key>RunAtLoad</key><true/>
      <key>StartInterval</key><integer>60</integer>
    </dict>
    </plist>
    """
    try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
    try plist.write(to: agent, atomically: true, encoding: .utf8)
    let uid = getuid()
    for arguments in [["bootout", "gui/\(uid)/\(agentLabel)"], ["bootstrap", "gui/\(uid)", agent.path]] {
      let launchctl = Process()
      launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
      launchctl.arguments = arguments
      launchctl.standardError = FileHandle.nullDevice
      try? launchctl.run()
      launchctl.waitUntilExit()
    }
  }
}

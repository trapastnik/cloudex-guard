// Страж сети: внешний IP и страна, заморозка выбранных программ, когда адрес не тот.
// Идеи взяты из Kordon (github.com/ef1m03/kordon, открытая GPL-версия): IP подтверждают
// два сервиса, ИИ-сервис спрашивается сам (видно раздельную маршрутизацию VPN), заморозка —
// SIGSTOP всего дерева процессов, при возвращении адреса — SIGCONT. Код свой.

import AppKit
import Network

// MARK: - Сетевые запросы

enum Net {
  // Новая сессия на каждую проверку: переиспользованное соединение остаётся на старом
  // маршруте и после переключения VPN показывает прежний адрес.
  static func session(direct: Bool = false) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 6
    config.timeoutIntervalForResource = 8
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.httpMaximumConnectionsPerHost = 1
    if direct {
      // Мимо системного прокси — так ходят терминал, git, Claude Code.
      config.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPEnable as String: 0,
        kCFNetworkProxiesHTTPSEnable as String: 0,
        kCFNetworkProxiesSOCKSEnable as String: 0,
      ]
    }
    return URLSession(configuration: config)
  }

  static func text(_ url: String, in session: URLSession) async -> String? {
    guard let url = URL(string: url) else { return nil }
    var request = URLRequest(url: url)
    request.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")  // сервисы отвечают curl простым текстом
    request.setValue("close", forHTTPHeaderField: "Connection")
    guard let (data, response) = try? await session.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    return String(decoding: data.prefix(4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // Адрес из сервиса вида «только IP»; nil, если ответ не похож на адрес нужного семейства.
  static func ip(_ url: String, v6: Bool, in session: URLSession) async -> String? {
    guard let answer = await text(url, in: session) else { return nil }
    let isV6 = answer.contains(":")
    let looksLikeIP = answer.allSatisfy { $0.isHexDigit || $0 == "." || $0 == ":" }
    return looksLikeIP && isV6 == v6 && !answer.isEmpty ? answer : nil
  }

  // Cloudflare /cdn-cgi/trace: адрес и страна так, как их видит этот сайт.
  static func trace(_ host: String, in session: URLSession) async -> View? {
    guard let answer = await text("https://\(host)/cdn-cgi/trace", in: session) else { return nil }
    var fields: [String: String] = [:]
    for line in answer.split(separator: "\n") {
      let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
      if pair.count == 2 { fields[pair[0]] = pair[1] }
    }
    guard let ip = fields["ip"], let loc = fields["loc"] else { return nil }
    return View(ip: ip, country: loc.uppercased())
  }

  // Страна адреса; кэш на всё время работы, адреса VPN повторяются.
  private static var geoCache: [String: String] = [:]
  private static let geoLock = NSLock()

  private static func cached(_ ip: String) -> String? {
    geoLock.lock(); defer { geoLock.unlock() }
    return geoCache[ip]
  }

  private static func remember(_ ip: String, _ country: String) {
    geoLock.lock(); defer { geoLock.unlock() }
    geoCache[ip] = country
  }

  static func country(of ip: String) async -> String? {
    if let cached = cached(ip) { return cached }
    let session = session()
    defer { session.invalidateAndCancel() }
    // ipinfo — база, по которой страну определяют многие сайты; country.is — запасная.
    // Базы расходятся: один и тот же адрес VPN бывает «DE» в одной и «US» в другой.
    var found: String?
    if let plain = await text("https://ipinfo.io/\(ip)/country", in: session), plain.count == 2 {
      found = plain
    }
    if found == nil, let json = await text("https://api.country.is/\(ip)", in: session),
       let data = json.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      found = object["country"] as? String
    }
    guard let country = found?.uppercased(), country.count == 2 else { return nil }
    remember(ip, country)
    return country
  }
}

struct View: Equatable {
  let ip: String
  let country: String
}

func flag(_ country: String) -> String {
  let base: UInt32 = 0x1F1E6 - 65
  let scalars = country.uppercased().unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
  return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : country
}

// MARK: - Процессы

struct Proc: Hashable {
  let pid: Int32
  let start: Int64  // время старта — чтобы не отправить сигнал чужому процессу с тем же номером
}

enum Procs {
  // Все процессы: номер, родитель, время старта, путь к исполняемому файлу.
  static func list() -> [(proc: Proc, ppid: Int32, path: String)] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
    let stride = MemoryLayout<kinfo_proc>.stride
    var items = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
    size = items.count * stride
    guard sysctl(&mib, 4, &items, &size, nil, 0) == 0 else { return [] }
    var out: [(proc: Proc, ppid: Int32, path: String)] = []
    var buffer = [CChar](repeating: 0, count: 4096)
    for item in items.prefix(size / stride) {
      let pid = item.kp_proc.p_pid
      guard pid > 0 else { continue }
      let started = item.kp_proc.p_un.__p_starttime
      let start = Int64(started.tv_sec) * 1_000_000 + Int64(started.tv_usec)
      let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
      let path = length > 0 ? String(cString: buffer) : ""
      out.append((Proc(pid: pid, start: start), item.kp_eproc.e_ppid, path))
    }
    return out
  }

  static func startOf(_ pid: Int32) -> Int64? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var item = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, 4, &item, &size, nil, 0) == 0, size > 0, item.kp_proc.p_pid == pid else { return nil }
    let started = item.kp_proc.p_un.__p_starttime
    return Int64(started.tv_sec) * 1_000_000 + Int64(started.tv_usec)
  }

  // Сигнал, только если номер всё ещё принадлежит тому же процессу.
  static func send(_ proc: Proc, _ signal: Int32) {
    guard startOf(proc.pid) == proc.start else { return }
    kill(proc.pid, signal)
  }

  // Процессы программы из бандла и всё, что они запустили (у Claude это и Claude Code, и MCP).
  static func tree(of bundlePaths: [String], in all: [(proc: Proc, ppid: Int32, path: String)]) -> Set<Proc> {
    let me = getpid()
    var picked = Set<Int32>()
    for item in all where item.proc.pid != me {
      if bundlePaths.contains(where: { item.path.hasPrefix($0 + "/") }) { picked.insert(item.proc.pid) }
    }
    var grew = true
    while grew {
      grew = false
      for item in all where !picked.contains(item.proc.pid) && picked.contains(item.ppid) && item.proc.pid != me {
        picked.insert(item.proc.pid)
        grew = true
      }
    }
    return Set(all.filter { picked.contains($0.proc.pid) }.map(\.proc))
  }
}

// MARK: - Защищаемые программы

struct Guarded: Codable, Hashable {
  let name: String
  let path: String       // путь к .app
  let probe: String?     // сайт, у которого спрашивать, каким адресом видна программа

  // Известные программы: ищутся среди установленных по идентификатору.
  static let known: [(name: String, bundleID: String, probe: String?)] = [
    ("Claude", "com.anthropic.claudefordesktop", "claude.ai"),
    ("ChatGPT", "com.openai.chat", "chatgpt.com"),
    ("Codex", "com.openai.codex", "chatgpt.com"),
    ("Cursor", "com.todesktop.230313mzl4w4u92", nil),
    ("Perplexity", "ai.perplexity.mac", "www.perplexity.ai"),
    ("Telegram", "ru.keepcoder.Telegram", nil),
    ("Telegram", "org.telegram.desktop", nil),
  ]

  static func installed() -> [Guarded] {
    known.compactMap { item in
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID)
        .map { Guarded(name: item.name, path: $0.path, probe: item.probe) }
    }
  }
}

// MARK: - Страж

enum Health { case ok, bad, unknown }

final class NetGuard: @unchecked Sendable {  // состояние трогается только на главном потоке
  static let shared = NetGuard()

  // Настройки
  private let defaults = UserDefaults.standard
  var allowed: Set<String> {
    get { Set(defaults.stringArray(forKey: "allowedCountries") ?? []) }
    set { defaults.set(newValue.sorted(), forKey: "allowedCountries"); enforce() }
  }
  var guarded: [Guarded] {
    get { (defaults.data(forKey: "guardedApps")).flatMap { try? JSONDecoder().decode([Guarded].self, from: $0) } ?? [] }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "guardedApps"); enforce() }
  }
  var isEnabled: Bool {
    get { defaults.object(forKey: "guardEnabled") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "guardEnabled"); enforce() }
  }
  var pausedUntil: Date? { didSet { enforce() } }

  // Что видно снаружи
  private(set) var general: View?             // адрес, на котором сошлись два сервиса
  private(set) var disagreement: String?      // второй сервис назвал другой адрес
  private(set) var v6: View?                  // адрес IPv6, если он есть
  private(set) var views: [String: View] = [:] // как нас видят сами сайты (claude.ai, chatgpt.com)
  private(set) var checkedAt: Date?
  private(set) var isChecking = false

  // Заморожено сейчас: процесс → имя программы
  private(set) var frozen: [Proc: String] = [:]
  private var suspect = false  // сеть сменилась, адрес ещё не подтверждён

  var onChange: (() -> Void)?
  private var monitor: NWPathMonitor?
  private var seenFirstPath = false
  private var timer: Timer?
  private var signalSources: [DispatchSourceSignal] = []

  private init() {}

  func start() {
    releaseStale()
    // Перезапуск сборкой (pkill), выход по сигналу — отпускаем всех, а не оставляем замороженными.
    for sig in [SIGTERM, SIGINT, SIGHUP] {
      signal(sig, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      source.setEventHandler { [weak self] in self?.releaseAll(); exit(0) }
      source.resume()
      signalSources.append(source)
    }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] _ in
      DispatchQueue.main.async { self?.networkChanged() }
    }
    monitor.start(queue: .global(qos: .utility))
    self.monitor = monitor
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.networkChanged() }
    check()
  }

  // Сменилась сеть или Мак проснулся: сразу замораживаем, потом проверяем — так программа
  // не успевает отправить ни одного запроса с неправильного адреса.
  private func networkChanged() {
    guard seenFirstPath else { seenFirstPath = true; return }
    if canFreeze { suspect = true; enforce() }
    check()
  }

  private var canFreeze: Bool {
    isEnabled && !(pausedUntil.map { $0 > Date() } ?? false) && !allowed.isEmpty && !guarded.isEmpty
  }

  // Чей взгляд решает для программы: её сайт, а если он молчит — общий адрес.
  func health(for app: Guarded) -> Health {
    if suspect { return .unknown }
    if let v6, !allowed.contains(v6.country) { return .bad }  // IPv6 мимо VPN
    if let probe = app.probe, let view = views[probe] { return allowed.contains(view.country) ? .ok : .bad }
    guard let general else { return .unknown }
    return allowed.contains(general.country) && disagreement == nil ? .ok : .bad
  }

  // Общее состояние для строки меню: худшее по программам; без программ — по общему адресу.
  var overall: Health {
    if allowed.isEmpty { return general == nil ? .unknown : .ok }
    let apps = guarded
    if apps.isEmpty {
      guard let general else { return .unknown }
      return allowed.contains(general.country) ? .ok : .bad
    }
    let states = apps.map(health(for:))
    if states.contains(.bad) { return .bad }
    return states.contains(.unknown) ? .unknown : .ok
  }

  // Страна, которую показываем: так видит Claude, иначе общий адрес.
  var shownCountry: String? { views["claude.ai"]?.country ?? general?.country }

  func check() {
    guard !isChecking else { return }
    isChecking = true
    let probes = Set(guarded.compactMap(\.probe)).union(["claude.ai"])
    Task.detached { [weak self] in
      let session = Net.session()
      async let first = Net.ip("https://api.ipify.org", v6: false, in: session)
      async let second = Net.ip("https://ipv4.icanhazip.com", v6: false, in: session)
      async let six = Net.ip("https://api6.ipify.org", v6: true, in: session)
      var seen: [String: View] = [:]
      for probe in probes {
        if let view = await Net.trace(probe, in: session) { seen[probe] = view }
      }
      let (a, b, ip6) = await (first, second, six)
      session.invalidateAndCancel()
      var general: View?
      var other: String?
      if let ip = a ?? b {
        if let a, let b, a != b { other = b }
        if let country = await Net.country(of: ip) { general = View(ip: ip, country: country) }
      }
      var v6: View?
      if let ip6, let country = await Net.country(of: ip6) { v6 = View(ip: ip6, country: country) }
      DispatchQueue.main.async {
        self?.apply(general: general, other: other, v6: v6, views: seen)
      }
    }
  }

  private func apply(general: View?, other: String?, v6: View?, views: [String: View]) {
    self.general = general
    self.disagreement = other
    self.v6 = v6
    self.views = views
    checkedAt = Date()
    isChecking = false
    suspect = false
    enforce()
    schedule()
  }

  // Пока что-то не так — проверяем часто, чтобы отпустить быстро; когда всё хорошо — редко.
  private func schedule() {
    timer?.invalidate()
    let isCalm = frozen.isEmpty && overall != .bad
    let interval: TimeInterval = isCalm ? 20 : 3
    let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.check() }
    timer.tolerance = isCalm ? 5 : 0.5
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  // Приводит заморозку в соответствие с состоянием.
  func enforce() {
    defer { saveFrozen(); onChange?() }
    let toFreeze = canFreeze ? guarded.filter { health(for: $0) != .ok } : []
    if toFreeze.isEmpty && frozen.isEmpty { return }  // всё спокойно — процессы даже не перебираем
    let all = Procs.list()
    var wanted: [Proc: String] = [:]
    for app in toFreeze {
      for proc in Procs.tree(of: [app.path], in: all) { wanted[proc] = app.name }
    }
    for (proc, _) in frozen where wanted[proc] == nil { Procs.send(proc, SIGCONT) }
    for (proc, _) in wanted where frozen[proc] == nil { Procs.send(proc, SIGSTOP) }
    if frozen.isEmpty && !wanted.isEmpty { NSSound(named: "Funk")?.play() }
    let alive = Set(all.map(\.proc))
    frozen = wanted.filter { alive.contains($0.key) }
  }

  func releaseAll() {
    for proc in frozen.keys { Procs.send(proc, SIGCONT) }
    frozen = [:]
    saveFrozen()
  }

  // Номера замороженных сохраняются: если приложение упало, при следующем старте отпустит их.
  private func saveFrozen() {
    defaults.set(frozen.keys.map { [Int64($0.pid), $0.start] }, forKey: "frozenProcs")
  }

  private func releaseStale() {
    let saved = defaults.array(forKey: "frozenProcs") as? [[Int64]] ?? []
    for pair in saved where pair.count == 2 { Procs.send(Proc(pid: Int32(pair[0]), start: pair[1]), SIGCONT) }
    defaults.removeObject(forKey: "frozenProcs")
  }

  var frozenApps: [String] { Array(Set(frozen.values)).sorted() }
}

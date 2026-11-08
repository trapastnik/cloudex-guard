// С 1.2 страж сети — отдельное приложение Cloudex Shield. Кто пользовался им в Cloudex Guard 1.1
// (выбирал программы или страны), один раз получает объяснение и ссылку; настройки Shield
// заберёт сам при первом запуске.

import AppKit

enum ShieldNotice {
  static func onLaunch() {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: "shieldNoticeShown") == nil else { return }
    let usedGuard = !(defaults.stringArray(forKey: "allowedCountries") ?? []).isEmpty
      || defaults.data(forKey: "guardedApps") != nil
    let shieldInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.github.trapastnik.cloudex-shield") != nil
    defaults.set(true, forKey: "shieldNoticeShown")
    guard usedGuard, !shieldInstalled else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = t("The network guard is now Cloudex Shield", "Страж сети теперь — Cloudex Shield")
      alert.informativeText = t(
        "Cloudex Guard now does one thing: the context of your Claude Code chats. Pausing apps when your VPN drops or switches servers moved to a separate free app, Cloudex Shield. Your apps and countries carry over when you install it.",
        "Cloudex Guard теперь делает одно: контекст чатов Claude Code. Пауза программ, когда VPN отвалился или сменил сервер, переехала в отдельное бесплатное приложение Cloudex Shield. Ваши программы и страны перейдут в него сами.")
      alert.addButton(withTitle: t("Get Cloudex Shield", "Скачать Cloudex Shield"))
      alert.addButton(withTitle: t("Later", "Позже"))
      if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: shieldURL) { NSWorkspace.shared.open(url) }
    }
  }
}

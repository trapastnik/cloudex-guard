import type { Register, EngineInterface, SessionRateLimit } from 'claude-code'

// Сюда каждый чат пишет своё заполнение контекста; строка меню (ContextMeter.app) читает папку:
// ~/.claude/context-meter. Домашняя папка — из пути, где лежит мод (/Users/<имя>/… или /home/<имя>/…).
function dataDir($: EngineInterface) {
  const home = /^(\/(?:Users|home)\/[^/]+)\//.exec($.plugin.root)
  return `${home ? home[1] : ''}/.claude/context-meter`
}
// Метка, которую ставила прежняя версия мода: найдём — уберём из названия.
const OLD_PREFIX = /^(?:🟢|🟡|🟠|🔴|⚪) \d{1,3}% · /u
// При старте чата приложение подключается не сразу: пробуем ещё столько раз с такой паузой.
const RETRIES = 12
const RETRY_MS = 5000
// Кнопка 🧹 в строке меню кладёт запрос в requests/<адрес>.json; чат проверяет его так часто.
const POLL_MS = 10000
const CLEANUP_TEXT =
  'У тебя достаточно большой контекст, когда сможешь, пожалуйста сохрани все подробно в документации напиши подробный Handoff и короткий текст для вставки в новый чат после чего будем тебя чистить.'

type Fill = { tokens: number; window: number; percent: number }

const textOf = (result: { content: { type: string; text?: string }[] }) =>
  result.content.map(block => (block.type === 'text' ? (block.text ?? '') : '')).join('')

// Заполнение, которое ещё не удалось записать.
let pending: Fill | undefined
let isWriting = false
let isRetrying = false
// Адрес этого чата (local_…), узнаётся при первой записи.
let myId: string | undefined
// Отметка «чат запущен» для строки меню: спящему чату просьбу надо вставить руками.
const BEAT_MS = 60000
let lastBeat = 0

// Пишет файл чата; false — приложение пока недоступно, стоит повторить позже.
async function record($: EngineInterface, fill: Fill): Promise<boolean> {
  if (isWriting) {
    return false
  }
  isWriting = true
  try {
    const got = await $.mcp.call('ccd_session_mgmt', 'get_session', { session_id: 'self' })
    if (got.isError) {
      return false
    }
    const session = JSON.parse(textOf(got))
    myId = session.sessionId
    const title: string = session.title ?? ''
    const clean = title.replace(OLD_PREFIX, '')
    if (clean !== title && clean !== '') {
      await $.mcp.call('ccd_session_mgmt', 'set_session_title', { session_id: 'self', title: clean })
    }
    const row = {
      id: session.sessionId,
      title: clean,
      group: session.group?.name ?? null,
      cwd: session.cwd,
      link: session.link ?? null,
      ...fill,
      updatedAt: await $.clock.now(),
    }
    await $.fs.write(`${dataDir($)}/${session.sessionId}.json`, JSON.stringify(row))
    return true
  } catch {
    // Чат ещё запускается или сервер приложения не подключён: молча повторим позже.
    return false
  } finally {
    isWriting = false
  }
}

// Лимиты аккаунта общие для всех чатов: пишет их любой чат, последний и прав.
async function recordLimits($: EngineInterface, rateLimits: readonly SessionRateLimit[]) {
  if (rateLimits.length === 0) {
    return
  }
  try {
    await $.fs.write(`${dataDir($)}/_limits.json`, JSON.stringify({ rateLimits, updatedAt: await $.clock.now() }))
  } catch {
    // Не записалось — запишет следующий ответ.
  }
}

// Есть свежий запрос от кнопки 🧹 — ставит сообщение в очередь чата и отмечает запрос выполненным.
async function poll($: EngineInterface) {
  if (myId === undefined) {
    return
  }
  const now = await $.clock.now()
  if (now - lastBeat >= BEAT_MS) {
    lastBeat = now
    await $.fs.write(`${dataDir($)}/alive/${myId}`, String(now)).catch(() => undefined)
  }
  const request = `${dataDir($)}/requests/${myId}.json`
  const ack = `${dataDir($)}/requests/${myId}.ack`
  try {
    if (!(await $.fs.exists(request))) {
      return
    }
    const { createdAt } = JSON.parse(String(await $.fs.read(request)))
    const done = (await $.fs.exists(ack)) ? Number(String(await $.fs.read(ack))) : 0
    if (!(createdAt > done)) {
      return
    }
    await $.fs.write(ack, String(createdAt))
    void $.prompt.submit({ text: CLEANUP_TEXT })
  } catch {
    // Файл в процессе записи — посмотрим в следующий раз.
  }
}

// Записывает последнее известное заполнение; при неудаче повторяет по таймеру.
async function apply($: EngineInterface, tries: number) {
  if (pending === undefined) {
    return
  }
  const fill = pending
  const isDone = await record($, fill)
  if (isDone && pending === fill) {
    pending = undefined
  }
  if (pending === undefined || isRetrying || tries <= 0) {
    return
  }
  isRetrying = true
  $.clock.after(RETRY_MS, () => {
    isRetrying = false
    void apply($, tries - 1)
  })
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    $.clock.every(POLL_MS, () => void poll($))
    const { context, rateLimits } = await $.session.usage()
    void recordLimits($, rateLimits)
    if (context.tokens !== undefined && context.percent !== undefined) {
      pending = { tokens: context.tokens, window: context.window, percent: context.percent }
      void apply($, RETRIES)
    }

    return next(e)
  })

  // Возобновлённый чат: свежего ответа ещё нет, но движок знает размер его последнего контекста.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.context_tokens !== undefined) {
      const { context } = await $.session.usage()
      const percent = Math.round((e.context_tokens / context.window) * 100)
      pending = { tokens: e.context_tokens, window: context.window, percent }
      void apply($, RETRIES)
    }

    return next(e)
  })
    // Ошибка здесь не должна мешать чату стартовать.
    .catch(($, e, next) => next(e))

  on('session.measure', async ($, e, next) => {
    if (e.changed.includes('rateLimits')) {
      void recordLimits($, e.rateLimits)
    }
    const { tokens, window, percent } = e.context
    if (e.changed.includes('context') && tokens !== undefined && percent !== undefined) {
      pending = { tokens, window, percent }
      void apply($, RETRIES)
    }

    return next(e)
  })
}

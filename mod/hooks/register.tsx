import type { Register, EngineInterface, SessionRateLimit } from 'claude-code'

// Каждый чат пишет сюда своё заполнение контекста, лимиты и состояние; строка меню
// (Cloudex Guard.app) читает папку ~/.claude/cloudex-guard. Модели мод ничего не отправляет.

// При старте чата приложение Claude подключается не сразу: пробуем ещё столько раз с такой паузой.
const RETRIES = 12
const RETRY_MS = 5000
// Кнопка 🧹 в строке меню кладёт запрос в requests/<адрес>.json; чат проверяет его так часто.
const POLL_MS = 10000
// Запрос старше этого не выполняется: чат, проснувшийся через день, не должен получить старую просьбу.
const REQUEST_TTL_MS = 10 * 60 * 1000
// Текст просьбы приходит в запросе (на языке интерфейса); этот — если его там нет.
const CLEANUP_TEXT =
  'Your context is getting large. When you can, please save everything in detail to the project docs, write a detailed handoff and a short text to paste into a new chat — after that we will clear this chat.'
// Отметка «чат запущен»: спящему чату просьбу 🧹 приходится вставлять руками.
const BEAT_MS = 60000

type Fill = { tokens: number; window: number; percent: number }
type Status = 'working' | 'asking' | 'done' | 'none'

const textOf = (result: { content: { type: string; text?: string }[] }) =>
  result.content.map(block => (block.type === 'text' ? (block.text ?? '') : '')).join('')

let dir: string | undefined
let pending: Fill | undefined
let isWriting = false
let isRetrying = false
let lastBeat = 0
// Адрес этого чата (local_…), узнаётся при первой записи.
let myId: string | undefined
// Состояние для раздела «Ждут вас» и инструменты, ждущие разрешения человека.
let status: { state: Status; at: number } | undefined
let askingTools: string[] = []

// Мод нужен только в чатах десктопного приложения Claude (вкладка Code): название и ссылку чата
// даёт само приложение. В терминальном `claude`, `claude -p`, SDK и скриптах мод ничего не делает.
let desktop: boolean | undefined

async function inDesktop($: EngineInterface): Promise<boolean> {
  if (desktop === undefined) {
    desktop = (await $.env.get('CLAUDE_CODE_ENTRYPOINT')) === 'claude-desktop'
    if (desktop) {
      myId = (await $.env.get('CLAUDE_CODE_HOST_SESSION_ID')) || undefined
    }
  }
  return desktop
}

async function dataDir($: EngineInterface): Promise<string> {
  if (dir === undefined) {
    dir = `${(await $.env.get('HOME')) ?? ''}/.claude/cloudex-guard`
  }
  return dir
}

async function setStatus($: EngineInterface, state: Status) {
  status = { state, at: await $.clock.now() }
  await writeStatus($)
}

async function writeStatus($: EngineInterface) {
  if (myId === undefined || status === undefined) {
    return  // адрес чата ещё не известен — запишем сразу, как узнаем
  }
  await $.fs.write(`${await dataDir($)}/status/${myId}.json`, JSON.stringify(status)).catch(() => undefined)
}

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
    void writeStatus($)
    const row = {
      id: session.sessionId,
      title: session.title ?? '',
      group: session.group?.name ?? null,
      cwd: session.cwd,
      link: session.link ?? null,
      ...fill,
      updatedAt: await $.clock.now(),
    }
    await $.fs.write(`${await dataDir($)}/${session.sessionId}.json`, JSON.stringify(row))
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
  const row = { rateLimits, updatedAt: await $.clock.now() }
  await $.fs.write(`${await dataDir($)}/_limits.json`, JSON.stringify(row)).catch(() => undefined)
}

// Есть свежий запрос от кнопки 🧹 — ставит сообщение в очередь чата и отмечает запрос выполненным.
async function poll($: EngineInterface) {
  if (myId === undefined) {
    return
  }
  const base = await dataDir($)
  const now = await $.clock.now()
  if (now - lastBeat >= BEAT_MS) {
    lastBeat = now
    await $.fs.write(`${base}/alive/${myId}`, String(now)).catch(() => undefined)
  }
  const request = `${base}/requests/${myId}.json`
  const ack = `${base}/requests/${myId}.ack`
  try {
    if (!(await $.fs.exists(request))) {
      return
    }
    const asked = JSON.parse(String(await $.fs.read(request)))
    const createdAt = Number(asked.createdAt)
    const text = typeof asked.text === 'string' && asked.text.trim() !== '' ? asked.text.slice(0, 2000) : CLEANUP_TEXT
    const doneAt = (await $.fs.exists(ack)) ? Number(String(await $.fs.read(ack))) : 0
    const done = Number.isFinite(doneAt) ? doneAt : 0
    if (!Number.isFinite(createdAt) || createdAt <= done || now - createdAt > REQUEST_TTL_MS) {
      return
    }
    await $.fs.write(ack, String(createdAt))
    void $.prompt.submit({ text })
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

function remember($: EngineInterface, fill: Fill) {
  if (fill.window <= 0) {
    return
  }
  pending = fill
  void apply($, RETRIES)
}

// Инструмент дождался решения человека (разрешили, отказали или он уже отработал).
async function answered($: EngineInterface, tool: string) {
  const index = askingTools.indexOf(tool)
  if (index >= 0) {
    askingTools.splice(index, 1)
  }
  if (askingTools.length === 0 && status?.state === 'asking') {
    await setStatus($, 'working')
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    if (await inDesktop($)) {
      $.clock.every(POLL_MS, () => void poll($))
      const { context, rateLimits } = await $.session.usage()
      void recordLimits($, rateLimits)
      if (context.tokens !== undefined && context.percent !== undefined) {
        remember($, { tokens: context.tokens, window: context.window, percent: context.percent })
      }
    }
    return next(e)
  })

  // Возобновлённый чат: свежего ответа ещё нет, но движок знает размер его последнего контекста.
  on('classic.SessionStart', async ($, e, next) => {
    if ((await inDesktop($)) && e.context_tokens !== undefined) {
      const { context } = await $.session.usage()
      if (context.window > 0) {
        const percent = Math.round((e.context_tokens / context.window) * 100)
        remember($, { tokens: e.context_tokens, window: context.window, percent })
      }
    }
    return next(e)
  })
    .catch(($, e, next) => next(e))  // ошибка здесь не должна мешать чату стартовать

  on('session.measure', async ($, e, next) => {
    if (await inDesktop($)) {
      if (e.changed.includes('rateLimits')) {
        void recordLimits($, e.rateLimits)
      }
      const { tokens, window, percent } = e.context
      if (e.changed.includes('context') && tokens !== undefined && percent !== undefined) {
        remember($, { tokens, window, percent })
      }
    }
    return next(e)
  })

  // Ход главного чата начался или закончился (ходы субагентов не в счёт).
  on('turn.start', async ($, e, next) => {
    if ((await inDesktop($)) && e.agentId === undefined) {
      askingTools = []
      await setStatus($, 'working')
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if ((await inDesktop($)) && e.agentId === undefined) {
      askingTools = []
      await setStatus($, 'done')
    }
    return next(e)
  })

  // Чат показывает запрос разрешения — стоит, пока человек не ответит.
  on('classic.PermissionRequest', async ($, e, next) => {
    if (await inDesktop($)) {
      askingTools.push(e.tool_name)
      await setStatus($, 'asking')
    }
    return next(e)
  })
    .catch(($, e, next) => next(e))  // сбой здесь не должен мешать запросу разрешения

  on('classic.PostToolUse', async ($, e, next) => {
    if (await inDesktop($)) await answered($, e.tool_name)
    return next(e)
  })
    .catch(($, e, next) => next(e))

  on('classic.PostToolUseFailure', async ($, e, next) => {
    if (await inDesktop($)) await answered($, e.tool_name)
    return next(e)
  })
    .catch(($, e, next) => next(e))

  on('classic.PermissionDenied', async ($, e, next) => {
    if (await inDesktop($)) await answered($, e.tool_name)
    return next(e)
  })
    .catch(($, e, next) => next(e))

  // Форма от MCP-сервера — тоже ожидание человека.
  on('classic.Notification', async ($, e, next) => {
    if ((await inDesktop($)) && e.notification_type === 'elicitation_dialog') {
      await setStatus($, 'asking')
    }
    return next(e)
  })
    .catch(($, e, next) => next(e))

  // Вопрос человеку: ждём, пока ответит.
  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    if (!(await inDesktop($))) {
      return next(e)
    }
    await setStatus($, 'asking')
    const ran = await next(e)
    await setStatus($, 'working')
    return ran
  })
    .catch(($, e, next) => next(e))  // сбой здесь не должен мешать вопросу

  // Чат закрыт или очищен — ждать от него нечего.
  on('session.end', async ($, e, next) => {
    if (await inDesktop($)) {
      askingTools = []
      await setStatus($, 'none')
    }
    return next(e)
  })
}

import { flushPromises, mount, type VueWrapper } from '@vue/test-utils'
import lucide from '@iconify-json/lucide/icons.json'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { EditorMeta, EditorMetaMoodOption } from '../bridge/meta'
import { installBridge } from '../bridge'
import { post } from '../bridge/post'
import EditorMetaHeader from './EditorMetaHeader.vue'

vi.mock('../bridge/post', () => ({ post: vi.fn() }))

const selectableMoodValues = [
  'positive', 'neutral', 'negative', 'fulfilled', 'angry', 'anxious',
  'tired', 'speechless', 'love', 'relaxed', 'grateful', 'lonely',
  'excited', 'expectant', 'proud', 'relieved', 'hurt', 'disappointed', 'irritated', 'confused',
]

const moodEmojis: Record<string, string> = {
  positive: '😊',
  neutral: '😐',
  negative: '😔',
  fulfilled: '😁',
  angry: '😠',
  anxious: '😰',
  tired: '😩',
  speechless: '😑',
  love: '🥰',
  relaxed: '😌',
  grateful: '🥹',
  lonely: '🥲',
  excited: '😆',
  expectant: '🤩',
  proud: '😎',
  relieved: '😮‍💨',
  hurt: '🥺',
  disappointed: '😞',
  irritated: '😤',
  confused: '😕',
}

const moods: EditorMetaMoodOption[] = [
  ['positive', 'smile'],
  ['neutral', 'meh'],
  ['negative', 'frown'],
  ['fulfilled', 'sparkles'],
  ['angry', 'angry'],
  ['anxious', 'tornado'],
  ['tired', 'battery-low'],
  ['speechless', 'annoyed'],
  ['love', 'heart'],
  ['study', 'book-open'],
  ['slacking', 'fish'],
  ['food', 'utensils'],
  ['work', 'briefcase'],
  ['travel', 'plane'],
  ['sports', 'dumbbell'],
  ['sick', 'thermometer'],
  ['relaxed', 'leaf'],
  ['grateful', 'hand-heart'],
  ['lonely', 'cloud-rain'],
  ['celebrating', 'party-popper'],
  ['focused', 'target'],
  ['meeting', 'users'],
  ['overtime', 'clock'],
  ['commuting', 'train-front'],
  ['sleep', 'moon'],
  ['coffee', 'coffee'],
  ['home', 'house'],
  ['shopping', 'shopping-bag'],
  ['cooking', 'chef-hat'],
  ['gaming', 'gamepad-2'],
  ['music', 'music'],
  ['movie', 'clapperboard'],
  ['excited', 'zap'],
  ['expectant', 'sunrise'],
  ['proud', 'award'],
  ['relieved', 'wind'],
  ['hurt', 'heart-crack'],
  ['disappointed', 'cloud-drizzle'],
  ['irritated', 'flame'],
  ['confused', 'circle-question-mark'],
].map(([value, icon]) => ({
  value, icon, label: value, color: '#2EB872',
  emoji: moodEmojis[value],
  selectable: selectableMoodValues.includes(value),
}))

const icons: Record<string, { body: string }> = lucide.icons

function iconBody(name: string): string {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
  svg.innerHTML = icons[name].body
  return svg.innerHTML
}

function meta(overrides: Partial<EditorMeta> = {}): EditorMeta {
  return {
    dateText: '2026/10/03',
    subText: '周六',
    mood: 'neutral',
    moods,
    weatherOptions: [],
    weatherClearLabel: '清除天气',
    places: [],
    positionNewPlaceLabel: '新建地点',
    positionManageLabel: '管理地点',
    positionClearLabel: '清除地点',
    tags: [],
    deleteLabel: '删除',
    ...overrides,
  }
}

let header: VueWrapper | undefined
const fontsDescriptor = Object.getOwnPropertyDescriptor(document, 'fonts')

beforeEach(() => {
  vi.clearAllMocks()
  vi.stubGlobal('FontFace', class {
    load() { return Promise.resolve(this) }
  })
  Object.defineProperty(document, 'fonts', {
    configurable: true,
    value: { add: vi.fn() },
  })
})

afterEach(() => {
  header?.unmount()
  header = undefined
  vi.useRealTimers()
  vi.unstubAllGlobals()
  if (fontsDescriptor) Object.defineProperty(document, 'fonts', fontsDescriptor)
  else Reflect.deleteProperty(document, 'fonts')
})

function latestTagRequest(): { reqId: string; query: string } {
  const requests = vi.mocked(post).mock.calls.filter(([type]) => type === 'requestTagCandidates')
  expect(requests.length).toBeGreaterThan(0)
  return requests[requests.length - 1][1] as { reqId: string; query: string }
}

async function replyWithTags(tags: string[] | null, reqId = latestTagRequest().reqId): Promise<void> {
  window.MoodiaryBridge!.resolveTagCandidates(reqId, JSON.stringify(tags))
  await flushPromises()
}

describe('inline tag selector', () => {
  beforeEach(() => {
    installBridge()
  })

  it('opens existing tag choices without asking the host to open an add dialog', async () => {
    const view = render({ tags: ['生活'] })

    await view.get('.meta-tag-add').trigger('click')

    expect(view.find('.meta-tag-input').exists()).toBe(true)
    expect(latestTagRequest().query).toBe('')
    expect(post).not.toHaveBeenCalledWith('addTag')
    await replyWithTags(['生活', '工作', '读书'])
    const choices = view.findAll('.meta-tag-option')
    expect(choices).toHaveLength(2)
    expect(choices[0].text()).toContain('工作')
    expect(choices[1].text()).toContain('读书')

    await choices[1].trigger('click')

    expect(post).toHaveBeenCalledWith('addTag', { tag: '读书' })
    expect(view.find('.meta-tag-input').exists()).toBe(false)
    expect(view.findAll('.meta-tag').map((tag) => tag.text())).toEqual(['#生活'])
    await view.setProps({ meta: meta({ tags: ['生活', '读书'] }) })
    expect(view.findAll('.meta-tag').map((tag) => tag.text())).toEqual(['#生活', '#读书'])
  })

  it.each([
    ['  #旅行/日本  ', '旅行/日本'],
    ['  old tag  ', 'old tag'],
    [' C# ', 'C#'],
  ])('creates the normalized tag %s directly from the inline input', async (input, tag) => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    await replyWithTags([])
    await view.get('.meta-tag-input').setValue(input)
    await replyWithTags([])

    await view.get('.meta-tag-create').trigger('click')

    expect(post).toHaveBeenCalledWith('addTag', { tag })
    expect(view.find('.meta-tag-input').exists()).toBe(false)
  })

  it.each(['', '   ', '#', '旅行//日本', '/旅行', '旅行/'])('does not submit an empty or invalid path %s', async (input) => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    await replyWithTags([])
    await view.get('.meta-tag-input').setValue(input)
    await replyWithTags([])

    await view.get('.meta-tag-input').trigger('keydown', { key: 'Enter' })

    expect(vi.mocked(post).mock.calls.filter(([type]) => type === 'addTag')).toHaveLength(0)
    expect(view.find('.meta-tag-input').exists()).toBe(true)
    const create = view.find('.meta-tag-create')
    expect(!create.exists() || create.attributes('disabled') !== undefined).toBe(true)
  })

  it('searches as the input changes and ignores responses for older queries', async () => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    const initial = latestTagRequest()
    await view.get('.meta-tag-input').setValue('工')
    const firstQuery = latestTagRequest()
    expect(firstQuery.query).toBe('工')
    await view.get('.meta-tag-input').setValue('读')
    const latestQuery = latestTagRequest()
    expect(latestQuery.query).toBe('读')
    expect(latestQuery.reqId).not.toBe(firstQuery.reqId)
    await replyWithTags(['读书'], latestQuery.reqId)
    await replyWithTags(['工作'], firstQuery.reqId)
    await replyWithTags(['旅行'], initial.reqId)

    expect(view.findAll('.meta-tag-option')).toHaveLength(1)
    expect(view.get('.meta-tag-option').text()).toContain('读书')
  })

  it('uses Enter to submit the typed tag unless a suggestion is explicitly highlighted', async () => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    await replyWithTags([])
    await view.get('.meta-tag-input').setValue('工作')
    await replyWithTags(['工作/项目'])

    await view.get('.meta-tag-input').trigger('keydown', { key: 'Enter' })

    expect(post).toHaveBeenCalledWith('addTag', { tag: '工作' })
    expect(view.find('.meta-tag-input').exists()).toBe(false)
  })

  it('selects an exact existing match with Enter without offering a duplicate new tag', async () => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    await replyWithTags([])
    await view.get('.meta-tag-input').setValue(' #工作 ')
    await replyWithTags(['工作', '工作/项目'])

    expect(view.find('.meta-tag-create').exists()).toBe(false)
    await view.get('.meta-tag-input').trigger('keydown', { key: 'Enter' })

    expect(post).toHaveBeenCalledWith('addTag', { tag: '工作' })
  })

  it('allows arrow keys to choose an existing tag before pressing Enter', async () => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    await replyWithTags(['工作', '读书'])
    const input = view.get('.meta-tag-input')

    await input.trigger('keydown', { key: 'ArrowDown' })
    await input.trigger('keydown', { key: 'ArrowDown' })
    await input.trigger('keydown', { key: 'ArrowUp' })
    await input.trigger('keydown', { key: 'Enter' })

    expect(post).toHaveBeenCalledWith('addTag', { tag: '工作' })
    expect(view.find('.meta-tag-input').exists()).toBe(false)
  })

  it('does not submit Enter while the user is composing text with an IME', async () => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    await replyWithTags([])
    const input = view.get('.meta-tag-input')
    await input.setValue('学习')
    await replyWithTags([])

    await input.trigger('keydown', { key: 'Enter', isComposing: true })

    expect(vi.mocked(post).mock.calls.filter(([type]) => type === 'addTag')).toHaveLength(0)
    expect(view.find('.meta-tag-input').exists()).toBe(true)
    await input.trigger('keydown', { key: 'Enter' })
    expect(post).toHaveBeenCalledWith('addTag', { tag: '学习' })
  })

  it('preserves Enter activation of the close button without submitting the input', async () => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    await replyWithTags([])
    await view.get('.meta-tag-input').setValue('学习')
    await replyWithTags([])
    const close = view.get('.meta-tag-close')
    const enter = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true })

    close.element.dispatchEvent(enter)

    expect(enter.defaultPrevented).toBe(false)
    expect(vi.mocked(post).mock.calls.filter(([type]) => type === 'addTag')).toHaveLength(0)
    // jsdom does not synthesize the native button click after a keyboard event.
    await close.trigger('click')
    expect(view.find('.meta-tag-input').exists()).toBe(false)
  })

  it('does not re-add a selected tag typed into the input', async () => {
    const view = render({ tags: ['工作'] })
    await view.get('.meta-tag-add').trigger('click')
    await replyWithTags(['工作'])
    await view.get('.meta-tag-input').setValue(' #工作 ')
    await replyWithTags(['工作'])

    await view.get('.meta-tag-input').trigger('keydown', { key: 'Enter' })

    expect(view.find('.meta-tag-option').exists()).toBe(false)
    expect(view.find('.meta-tag-create').exists()).toBe(false)
    expect(vi.mocked(post).mock.calls.filter(([type]) => type === 'addTag')).toHaveLength(0)
  })

  it.each(['Escape', 'close button'])('closes with %s and ignores late results after reopening', async (method) => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    const closedRequest = latestTagRequest()
    if (method === 'Escape') await view.get('.meta-tag-input').trigger('keydown', { key: 'Escape' })
    else await view.get('.meta-tag-close').trigger('click')

    expect(view.find('.meta-tag-input').exists()).toBe(false)
    expect(vi.mocked(post).mock.calls.filter(([type]) => type === 'addTag')).toHaveLength(0)
    await view.get('.meta-tag-add').trigger('click')
    await replyWithTags(['读书'])
    await replyWithTags(['旧结果'], closedRequest.reqId)

    expect(view.findAll('.meta-tag-option')).toHaveLength(1)
    expect(view.get('.meta-tag-option').text()).toContain('读书')
  })

  it('shows a retry action when the host fails to load tags and recovers', async () => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    const failedRequest = latestTagRequest()
    await replyWithTags(null)

    expect(view.find('.meta-tag-retry').exists()).toBe(true)
    await view.get('.meta-tag-retry').trigger('click')
    expect(latestTagRequest().reqId).not.toBe(failedRequest.reqId)
    expect(latestTagRequest().query).toBe('')
    await replyWithTags(['旅行'])

    expect(view.find('.meta-tag-retry').exists()).toBe(false)
    expect(view.get('.meta-tag-option').text()).toContain('旅行')
  })

  it('preserves Enter activation of retry without submitting the input', async () => {
    const view = render()
    await view.get('.meta-tag-add').trigger('click')
    await replyWithTags([])
    await view.get('.meta-tag-input').setValue('学习')
    const failedRequest = latestTagRequest()
    await replyWithTags(null)
    const retry = view.get('.meta-tag-retry')
    const enter = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true })

    retry.element.dispatchEvent(enter)

    expect(enter.defaultPrevented).toBe(false)
    expect(vi.mocked(post).mock.calls.filter(([type]) => type === 'addTag')).toHaveLength(0)
    // Preserve the browser's native Enter-to-click behavior for the retry action.
    await retry.trigger('click')
    expect(latestTagRequest().reqId).not.toBe(failedRequest.reqId)
    expect(latestTagRequest().query).toBe('学习')
    await replyWithTags(['学习/课程'])
    expect(view.get('.meta-tag-option').text()).toContain('学习/课程')
  })

  it('offers retry after a candidate request times out', async () => {
    vi.useFakeTimers()
    const view = render()
    await view.get('.meta-tag-add').trigger('click')

    await vi.advanceTimersByTimeAsync(4000)

    expect(view.find('.meta-tag-retry').exists()).toBe(true)
    expect(vi.mocked(post).mock.calls.filter(([type]) => type === 'addTag')).toHaveLength(0)
  })

  it('hides the add control and picker in read-only mode', () => {
    const view = render({ tags: ['读书'] }, false)

    expect(view.find('.meta-tag-add').exists()).toBe(false)
    expect(view.find('.meta-tag-input').exists()).toBe(false)
    expect(view.get('.meta-tag').text()).toBe('#读书')
    expect(post).not.toHaveBeenCalled()
  })
})

function render(options: Partial<EditorMeta> = {}, editable = true): VueWrapper {
  header = mount(EditorMetaHeader, {
    props: { meta: meta(options), editable, wordCount: 12 },
    global: { stubs: { teleport: true } },
  })
  return header
}

describe('mood selector', () => {
  it('shows the twenty selectable moods as emoji with labels and selected state', async () => {
    expect(moods).toHaveLength(40)
    const view = render()
    expect(view.find('.mood-panel').exists()).toBe(false)

    await view.get('.meta-mood-chip').trigger('click')

    const cells = view.findAll('.mood-cell')
    expect(cells).toHaveLength(20)
    expect(cells.map((cell) => cell.get('.mood-cell-label').text())).toEqual(selectableMoodValues)
    cells.forEach((cell) => {
      const mood = moods.find((option) => option.label === cell.get('.mood-cell-label').text())!
      expect(cell.get('.mood-emoji').text()).toBe(mood.emoji)
      expect(cell.get('.mood-emoji').attributes('aria-hidden')).toBe('true')
      expect(cell.find('svg').exists()).toBe(false)
      expect(cell.attributes('aria-pressed')).toBe(String(mood.value === 'neutral'))
    })
  })

  it.each([
    'grateful', 'excited', 'expectant', 'proud', 'relieved',
    'hurt', 'disappointed', 'irritated', 'confused',
  ])('sends the selected %s mood to the host and closes the panel', async (value) => {
    const view = render()
    const selected = moods.find((mood) => mood.value === value)!
    await view.get('.meta-mood-chip').trigger('click')

    await view.findAll('.mood-cell').find((cell) => cell.get('.mood-cell-label').text() === selected.label)!.trigger('click')

    expect(post).toHaveBeenCalledExactlyOnceWith('changeMood', { mood: selected.value })
    expect(view.find('.mood-panel').exists()).toBe(false)

    // The host remains the source of truth and sends the accepted selection back.
    await view.setProps({ meta: meta({ mood: selected.value }) })
    expect(view.get('.meta-mood-label').text()).toBe(selected.label)
    expect(view.get('.meta-mood-emoji').text()).toBe(selected.emoji)
    expect(view.get('.meta-mood-emoji').attributes('aria-hidden')).toBe('true')
    expect(view.find('.meta-mood-chip svg').exists()).toBe(false)
    await view.get('.meta-mood-chip').trigger('click')
    expect(view.get('.mood-cell[aria-pressed="true"] .mood-cell-label').text()).toBe(selected.label)
  })

  it.each(moods)('renders the $value visual in read-only mode without opening a selector', async (selected) => {
    const view = render({ mood: selected.value }, false)

    expect(view.get('.meta-mood-label').text()).toBe(selected.label)
    if (selected.emoji) {
      expect(view.get('.meta-mood-emoji').text()).toBe(selected.emoji)
      expect(view.get('.meta-mood-emoji').attributes('aria-hidden')).toBe('true')
      expect(view.find('.meta-mood-chip svg').exists()).toBe(false)
    } else {
      expect(view.get('.meta-mood-chip svg').element.innerHTML).toBe(iconBody(selected.icon))
      expect(view.find('.meta-mood-emoji').exists()).toBe(false)
    }
    await view.get('.meta-mood-chip').trigger('click')
    expect(view.find('.mood-panel').exists()).toBe(false)
    expect(post).not.toHaveBeenCalled()
  })

  it.each([true, false])('preserves the historical work label and icon with editable=%s', async (editable) => {
    const view = render({ mood: 'work' }, editable)

    expect(view.get('.meta-mood-label').text()).toBe('work')
    expect(view.get('.meta-mood-chip svg').element.innerHTML).toBe(iconBody('briefcase'))
    await view.get('.meta-mood-chip').trigger('click')
    const cells = view.findAll('.mood-cell')
    expect(cells.map((cell) => cell.get('.mood-cell-label').text())).toEqual(editable ? selectableMoodValues : [])
    expect(view.find('.mood-cell[aria-pressed="true"]').exists()).toBe(false)
    expect(post).not.toHaveBeenCalled()
  })

  it('keeps legacy icons and selection when an older host omits emoji and selectable', async () => {
    const legacyMoods = moods.map(({ emoji, selectable, ...mood }) => mood)
    const view = render({ moods: legacyMoods })
    await view.get('.meta-mood-chip').trigger('click')

    const cells = view.findAll('.mood-cell')
    expect(cells).toHaveLength(moods.length)
    cells.forEach((cell, index) => {
      expect(cell.get('svg').element.innerHTML).toBe(iconBody(legacyMoods[index].icon))
      expect(cell.find('.mood-emoji').exists()).toBe(false)
    })
    await cells.find((cell) => cell.get('.mood-cell-label').text() === 'work')!.trigger('click')
    expect(post).toHaveBeenCalledExactlyOnceWith('changeMood', { mood: 'work' })
    expect(view.find('.mood-panel').exists()).toBe(false)
  })

  it('ignores a stale selection after the host marks the option unselectable', async () => {
    const view = render()
    await view.get('.meta-mood-chip').trigger('click')
    const cell = view.findAll('.mood-cell').find((option) => option.get('.mood-cell-label').text() === 'grateful')!
    await view.setProps({ meta: meta({
      moods: moods.map((mood) => mood.value === 'grateful' ? { ...mood, selectable: false } : mood),
    }) })

    await cell.trigger('click')

    expect(post).not.toHaveBeenCalled()
    expect(view.find('.mood-panel').exists()).toBe(true)
    expect(view.findAll('.mood-cell').map((option) => option.get('.mood-cell-label').text())).not.toContain('grateful')
  })

  it.each([undefined, null, ''])('falls back to the legacy icon when emoji is %s', async (emoji) => {
    const view = render({
      mood: 'grateful',
      moods: moods.map((mood) => mood.value === 'grateful' ? { ...mood, emoji } : mood),
    })

    expect(view.find('.meta-mood-emoji').exists()).toBe(false)
    expect(view.get('.meta-mood-chip svg').element.innerHTML).toBe(iconBody('hand-heart'))
    await view.get('.meta-mood-chip').trigger('click')
    const cell = view.get('.mood-cell[aria-pressed="true"]')
    expect(cell.find('.mood-emoji').exists()).toBe(false)
    expect(cell.get('svg').element.innerHTML).toBe(iconBody('hand-heart'))
  })

  it('uses the host emoji even when the legacy icon is unknown', async () => {
    const future = { value: 'future', label: '未来心情', color: '#64748B', icon: 'unknown-icon', emoji: '🙂' }
    const view = render({ mood: future.value, moods: [...moods, future] })

    expect(view.get('.meta-mood-label').text()).toBe(future.label)
    expect(view.get('.meta-mood-emoji').text()).toBe(future.emoji)
    expect(view.find('.meta-mood-chip svg').exists()).toBe(false)
    await view.get('.meta-mood-chip').trigger('click')
    const cell = view.get('.mood-cell[aria-pressed="true"]')
    expect(cell.get('.mood-emoji').text()).toBe(future.emoji)
    expect(cell.find('svg').exists()).toBe(false)
  })

  it('keeps an unknown icon selectable while displaying the neutral fallback', async () => {
    const unknown = { value: 'future', label: '未来状态', color: '#64748B', icon: 'unknown-icon' }
    const view = render({ mood: unknown.value, moods: [...moods, unknown] })

    expect(view.get('.meta-mood-label').text()).toBe(unknown.label)
    expect(view.get('.meta-mood-chip svg').element.innerHTML).toBe(iconBody('meh'))
    await view.get('.meta-mood-chip').trigger('click')
    const cell = view.get('.mood-cell[aria-pressed="true"]')
    expect(cell.get('svg').element.innerHTML).toBe(iconBody('meh'))
    await cell.trigger('click')
    expect(post).toHaveBeenCalledExactlyOnceWith('changeMood', { mood: unknown.value })
    expect(view.find('.mood-panel').exists()).toBe(false)
  })
})

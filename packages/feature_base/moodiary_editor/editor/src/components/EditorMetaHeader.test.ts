import { mount, type VueWrapper } from '@vue/test-utils'
import lucide from '@iconify-json/lucide/icons.json'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { EditorMeta, EditorMetaMoodOption } from '../bridge/meta'
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
  vi.unstubAllGlobals()
  if (fontsDescriptor) Object.defineProperty(document, 'fonts', fontsDescriptor)
  else Reflect.deleteProperty(document, 'fonts')
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

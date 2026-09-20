import { mount, type VueWrapper } from '@vue/test-utils'
import { nextTick } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import defaultThemes from '../../../../core/moodiary_theme/test/fixtures/default_editor_themes.json'
import Harness from './Harness.vue'

let wrapper: VueWrapper | undefined
let systemDark = false
const listeners = new Set<(event: MediaQueryListEvent) => void>()
const removeListener = vi.fn((_: string, listener: (event: MediaQueryListEvent) => void) => {
  listeners.delete(listener)
})

beforeEach(() => {
  localStorage.clear()
  systemDark = false
  listeners.clear()
  removeListener.mockClear()
  vi.stubGlobal('matchMedia', vi.fn(() => ({
    get matches() { return systemDark },
    addEventListener: (_: string, listener: (event: MediaQueryListEvent) => void) => listeners.add(listener),
    removeEventListener: removeListener,
  })))
})

afterEach(() => {
  wrapper?.unmount()
  wrapper = undefined
  vi.unstubAllGlobals()
  document.body.replaceChildren()
})

async function mountHarness() {
  wrapper = mount(Harness, { attachTo: document.body })
  await nextTick()
  const frame = wrapper.get('iframe').element as HTMLIFrameElement
  const bridge = { setTheme: vi.fn(), setContent: vi.fn(), setEditable: vi.fn() }
  Object.defineProperty(frame.contentWindow, 'MoodiaryBridge', { value: bridge })
  await wrapper.get('iframe').trigger('load')
  return { frame, bridge }
}

async function selectMode(label: string) {
  const button = wrapper!.findAll('button').find((item) => item.text() === label)!
  await button.trigger('click')
}

async function changeSystemTheme(dark: boolean) {
  systemDark = dark
  for (const listener of listeners) listener({ matches: dark } as MediaQueryListEvent)
  await nextTick()
}

describe('default editor palettes', () => {
  for (const dark of [false, true]) {
    it(`boots with the ${dark ? 'dim' : 'lemonade'} palette for the system appearance`, async () => {
      systemDark = dark
      const { bridge } = await mountHarness()
      expect(window.matchMedia).toHaveBeenCalledWith('(prefers-color-scheme: dark)')
      expect(bridge.setTheme).toHaveBeenLastCalledWith({
        roles: defaultThemes[dark ? 'dark' : 'light'], dark,
      })
      expect(wrapper!.attributes('data-theme')).toBe(dark ? 'dim' : 'lemonade')
    })
  }

  it('follows system changes without reloading the document or replacing content', async () => {
    const { frame, bridge } = await mountHarness()
    const source = frame.src
    bridge.setContent.mockClear()

    await changeSystemTheme(true)
    expect(bridge.setTheme).toHaveBeenLastCalledWith({ roles: defaultThemes.dark, dark: true })
    expect(wrapper!.attributes('data-theme')).toBe('dim')

    await changeSystemTheme(false)
    expect(bridge.setTheme).toHaveBeenLastCalledWith({ roles: defaultThemes.light, dark: false })
    expect(wrapper!.attributes('data-theme')).toBe('lemonade')
    expect(frame.src).toBe(source)
    expect(bridge.setContent).not.toHaveBeenCalled()
  })

  it('keeps manual overrides until follow-system is selected again', async () => {
    const { bridge } = await mountHarness()
    await selectMode('深色')
    expect(bridge.setTheme).toHaveBeenLastCalledWith({ roles: defaultThemes.dark, dark: true })
    await changeSystemTheme(true)
    await changeSystemTheme(false)
    expect(wrapper!.attributes('data-theme')).toBe('dim')

    await selectMode('浅色')
    await changeSystemTheme(true)
    expect(bridge.setTheme).toHaveBeenLastCalledWith({ roles: defaultThemes.light, dark: false })
    expect(wrapper!.attributes('data-theme')).toBe('lemonade')

    await selectMode('跟随系统')
    expect(bridge.setTheme).toHaveBeenLastCalledWith({ roles: defaultThemes.dark, dark: true })
    expect(wrapper!.attributes('data-theme')).toBe('dim')
  })

  it('removes the system appearance listener on unmount', async () => {
    await mountHarness()
    expect(listeners.size).toBe(1)
    wrapper!.unmount()
    wrapper = undefined
    expect(listeners.size).toBe(0)
    expect(removeListener).toHaveBeenCalledWith('change', expect.any(Function))
  })
})

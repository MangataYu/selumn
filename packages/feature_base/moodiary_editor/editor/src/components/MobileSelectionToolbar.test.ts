import { mount } from '@vue/test-utils'
import type { VueWrapper } from '@vue/test-utils'
import { nextTick } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { EditorHarness } from '../test/harness'
import { setupEditor } from '../test/harness'
import MobileSelectionToolbar from './MobileSelectionToolbar.vue'

let h: EditorHarness
let wrapper: VueWrapper
let viewport: HTMLElement
let selectionRect: DOMRect
let unmounted: boolean

function rect(left: number, top: number, width: number, height: number): DOMRect {
  return {
    x: left, y: top, left, top, width, height,
    right: left + width, bottom: top + height, toJSON: () => ({}),
  } as DOMRect
}

async function settle(): Promise<void> {
  await nextTick()
  await vi.advanceTimersByTimeAsync(50)
  await nextTick()
}

async function selectText(from: number, to: number): Promise<void> {
  h.editor.view.focus()
  h.editor.commands.setTextSelection({ from, to })
  await settle()
}

const find = (id: string): HTMLElement | null =>
  document.querySelector(`[data-testid="${id}"]`)

function button(id: string): HTMLElement {
  const element = find(id)
  if (!element) throw new Error(`Missing ${id}`)
  return element
}

beforeEach(() => {
  vi.useFakeTimers()
  unmounted = false
  h = setupEditor()
  viewport = document.createElement('div')
  viewport.appendChild(h.editor.view.dom)
  document.body.appendChild(viewport)
  viewport.getBoundingClientRect = () => rect(0, 0, 360, 600)
  selectionRect = rect(90, 210, 70, 22)
  vi.spyOn(Range.prototype, 'getClientRects').mockImplementation(() => {
    const list = [selectionRect]
    return Object.assign(list, { item: (index: number) => list[index] ?? null }) as unknown as DOMRectList
  })
  vi.spyOn(Range.prototype, 'getBoundingClientRect').mockImplementation(() => selectionRect)
  wrapper = mount(MobileSelectionToolbar, {
    props: { editor: h.editor, viewport },
    attachTo: document.body,
  })
})

afterEach(() => {
  if (!unmounted) wrapper.unmount()
  h.destroy()
  vi.restoreAllMocks()
  vi.useRealTimers()
})

describe('mobile selection toolbar', () => {
  it('formats only the selected text, preserves the selection and reflects active marks', async () => {
    await h.type('前文后文')
    await selectText(1, 3)

    expect(find('selection-toolbar')).not.toBeNull()
    const bold = button('selection-bold')
    const down = new MouseEvent('pointerdown', { bubbles: true, cancelable: true })
    bold.dispatchEvent(down)
    expect(down.defaultPrevented).toBe(true)
    bold.click()
    await settle()

    expect(h.editor.state.selection.from).toBe(1)
    expect(h.editor.state.selection.to).toBe(3)
    expect(h.editor.getJSON().content?.[0]?.content).toEqual([
      { type: 'text', text: '前文', marks: [{ type: 'bold' }] },
      { type: 'text', text: '后文' },
    ])
    expect(bold.getAttribute('aria-pressed')).toBe('true')

    button('selection-italic').click()
    await settle()
    expect(h.editor.isActive('bold')).toBe(true)
    expect(h.editor.isActive('italic')).toBe(true)
    expect(button('selection-italic').getAttribute('aria-pressed')).toBe('true')
    expect(find('selection-toolbar')).not.toBeNull()

    bold.click()
    await settle()
    expect(h.editor.isActive('bold')).toBe(false)
    expect(h.editor.isActive('italic')).toBe(true)
    expect(bold.getAttribute('aria-pressed')).toBe('false')
  })

  it('hides for a collapsed selection, read-only editor and blur', async () => {
    await h.type('前文后文')
    await selectText(1, 3)
    expect(find('selection-toolbar')).not.toBeNull()

    h.editor.commands.setTextSelection(2)
    await settle()
    expect(find('selection-toolbar')).toBeNull()

    await selectText(1, 3)
    h.editor.setEditable(false)
    wrapper.unmount()
    wrapper = mount(MobileSelectionToolbar, {
      props: { editor: h.editor, viewport },
      attachTo: document.body,
    })
    await settle()
    expect(find('selection-toolbar')).toBeNull()

    h.editor.setEditable(true)
    await selectText(1, 3)
    document.dispatchEvent(new Event('selectionchange'))
    await settle()
    expect(find('selection-toolbar')).not.toBeNull()
    h.editor.view.dom.blur()
    await settle()
    expect(find('selection-toolbar')).toBeNull()
  })

  it('hides for a selected image node', async () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'image', attrs: { src: 'image-1.jpg' } },
      { type: 'paragraph' },
    ] }))
    h.editor.view.focus()
    h.editor.commands.setNodeSelection(0)
    await settle()
    expect(find('selection-toolbar')).toBeNull()
  })

  it('offers formatting after selecting all text', async () => {
    await h.type('整篇日记')
    h.editor.view.focus()
    h.editor.commands.selectAll()
    await settle()
    expect(find('selection-toolbar')).not.toBeNull()
    button('selection-bold').click()
    await settle()
    expect(h.editor.getJSON().content?.[0]?.content?.[0]?.marks?.[0]?.type).toBe('bold')
  })

  it('keeps the toolbar available when a keyboard user focuses a format button', async () => {
    await h.type('前文后文')
    await selectText(1, 3)
    const bold = button('selection-bold')
    bold.focus()
    await settle()
    expect(find('selection-toolbar')).not.toBeNull()
    expect(document.activeElement).toBe(bold)
    bold.click()
    await settle()
    expect(h.editor.isActive('bold')).toBe(true)
  })

  it('hides when keyboard focus leaves the toolbar', async () => {
    await h.type('前文后文')
    await selectText(1, 3)
    button('selection-bold').focus()
    await settle()
    const outside = document.createElement('button')
    document.body.appendChild(outside)
    outside.focus()
    await settle()
    expect(find('selection-toolbar')).toBeNull()
    outside.remove()
  })

  it('hides rather than keeping a stale position if the viewport changes while focused', async () => {
    await h.type('前文后文')
    await selectText(1, 3)
    button('selection-bold').focus()
    await settle()
    window.dispatchEvent(new Event('resize'))
    await settle()
    expect(find('selection-toolbar')).toBeNull()
  })

  it('repositions when the editor viewport scrolls or the window resizes', async () => {
    await h.type('前文后文')
    await selectText(1, 3)
    const toolbar = button('selection-toolbar')
    const initialStyle = toolbar.getAttribute('style')

    selectionRect = rect(90, 160, 70, 22)
    viewport.dispatchEvent(new Event('scroll'))
    await settle()
    const scrolledStyle = toolbar.getAttribute('style')
    expect(scrolledStyle).not.toBe(initialStyle)

    selectionRect = rect(30, 120, 70, 22)
    window.dispatchEvent(new Event('resize'))
    await settle()
    expect(toolbar.getAttribute('style')).not.toBe(scrolledStyle)
  })

  it('hides when the selection scrolls out of view and returns when visible', async () => {
    await h.type('前文后文')
    await selectText(1, 3)
    expect(find('selection-toolbar')).not.toBeNull()

    selectionRect = rect(90, -80, 70, 22)
    viewport.dispatchEvent(new Event('scroll'))
    await settle()
    expect(find('selection-toolbar')).toBeNull()

    selectionRect = rect(90, 210, 70, 22)
    viewport.dispatchEvent(new Event('scroll'))
    await settle()
    expect(find('selection-toolbar')).not.toBeNull()
  })

  it('hides while composing and restores the toolbar after composition ends', async () => {
    const composing = vi.spyOn(h.editor.view, 'composing', 'get').mockReturnValue(false)
    await h.type('前文后文')
    await selectText(1, 3)
    expect(find('selection-toolbar')).not.toBeNull()

    composing.mockReturnValue(true)
    h.editor.view.dom.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }))
    await settle()
    expect(find('selection-toolbar')).toBeNull()

    composing.mockReturnValue(false)
    h.editor.view.dom.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true }))
    await settle()
    expect(find('selection-toolbar')).not.toBeNull()
  })

  it('removes the toolbar and event handlers on unmount', async () => {
    await h.type('前文后文')
    await selectText(1, 3)
    expect(find('selection-toolbar')).not.toBeNull()
    wrapper.unmount()
    unmounted = true

    document.dispatchEvent(new Event('selectionchange'))
    viewport.dispatchEvent(new Event('scroll'))
    window.dispatchEvent(new Event('resize'))
    await settle()
    expect(find('selection-toolbar')).toBeNull()
  })

  it('cleans up safely if the parent destroys the editor first', async () => {
    await h.type('前文后文')
    await selectText(1, 3)
    h.editor.destroy()
    expect(() => wrapper.unmount()).not.toThrow()
    unmounted = true
    await settle()
    expect(find('selection-toolbar')).toBeNull()
  })
})

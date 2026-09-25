import { mount } from '@vue/test-utils'
import type { VueWrapper } from '@vue/test-utils'
import { nextTick } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { setupEditor } from '../test/harness'
import type { EditorHarness } from '../test/harness'
import { selectTag, tagSuggestion } from '../editor/tag'
import { i18n } from '../i18n'
import EditorToolbar from './EditorToolbar.vue'

let h: EditorHarness
let toolbar: VueWrapper

beforeEach(() => {
  vi.useFakeTimers()
  h = setupEditor()
  toolbar = mount(EditorToolbar, {
    props: { editor: h.editor, platform: 'mobile' },
    attachTo: document.body,
  })
})

afterEach(() => {
  toolbar.unmount()
  h.destroy()
  vi.useRealTimers()
})

const btn = (id: string) => toolbar.get(`[data-testid="${id}"]`)
const disabled = (id: string): boolean =>
  (btn(id).element as HTMLButtonElement).disabled

describe('bold button', () => {
  const boldButton = () => toolbar.get(`button[title="${i18n.global.t('toolbar.bold')}"]`)

  it('toggles bold for a mixed Chinese and English selection without changing surrounding text', async () => {
    const selected = '中文 English'
    await h.type(`前文${selected}后文`)
    h.editor.commands.setTextSelection({ from: 3, to: 3 + selected.length })

    await boldButton().trigger('click')

    expect(h.editor.getJSON().content?.[0]?.content).toEqual([
      { type: 'text', text: '前文' },
      { type: 'text', text: selected, marks: [{ type: 'bold' }] },
      { type: 'text', text: '后文' },
    ])
    expect(h.editor.view.dom.querySelector('strong')?.textContent).toBe(selected)
    expect(boldButton().classes()).toContain('btn-active')

    await boldButton().trigger('click')

    expect(h.editor.getJSON().content?.[0]?.content).toEqual([
      { type: 'text', text: `前文${selected}后文` },
    ])
    expect(h.editor.view.dom.querySelector('strong')).toBeNull()
    expect(boldButton().classes()).not.toContain('btn-active')
  })

  it('keeps newly entered Chinese bold through saving and reloading', async () => {
    await boldButton().trigger('click')
    await h.type('中文 English')

    const saved = h.api.getContent()
    expect(JSON.parse(saved).content[0].content).toEqual([
      { type: 'text', text: '中文 English', marks: [{ type: 'bold' }] },
    ])

    h.api.reset()
    h.api.setContent(saved)

    expect(h.api.getContent()).toBe(saved)
    expect(h.editor.view.dom.querySelector('strong')?.textContent).toBe('中文 English')
  })

  it('retains bold when composition replaces phonetic text with Chinese characters', async () => {
    await boldButton().trigger('click')
    const composing = vi.spyOn(h.editor.view, 'composing', 'get').mockReturnValue(true)
    h.editor.view.dispatch(h.editor.state.tr.insertText('zhongwen'))
    h.editor.view.dispatch(h.editor.state.tr.insertText('中文', 1, 9))
    composing.mockReturnValue(false)
    h.editor.view.dom.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '中文' }))
    await vi.advanceTimersByTimeAsync(20)

    expect(h.editor.getJSON().content?.[0]?.content).toEqual([
      { type: 'text', text: '中文', marks: [{ type: 'bold' }] },
    ])
    expect(h.editor.view.dom.querySelector('strong')?.textContent).toBe('中文')
    composing.mockRestore()
  })
})

describe('undo / redo buttons', () => {
  it('starts disabled on a fresh document', () => {
    expect(disabled('undo')).toBe(true)
    expect(disabled('redo')).toBe(true)
  })

  it('undoes and redoes an edit', async () => {
    await h.type('今天天气不错')
    await nextTick()
    expect(disabled('undo')).toBe(false)

    await btn('undo').trigger('click')
    await nextTick()
    expect(h.editor.getText()).not.toContain('今天天气不错')
    expect(disabled('redo')).toBe(false)

    await btn('redo').trigger('click')
    await nextTick()
    expect(h.editor.getText()).toContain('今天天气不错')
  })

  it('goes back to disabled after loading new content', async () => {
    await h.type('旧内容')
    await nextTick()
    expect(disabled('undo')).toBe(false)

    h.api.setContent(
      JSON.stringify({
        type: 'doc',
        content: [{ type: 'paragraph', content: [{ type: 'text', text: '新的一篇' }] }],
      }),
    )
    await nextTick()
    expect(disabled('undo')).toBe(true)
  })
})

describe('tag shortcut', () => {
  it.each(['mobile', 'desktop'] as const)('opens tag candidates from an empty %s editor', async (platform) => {
    await toolbar.setProps({ platform })
    expect(disabled('insert-tag')).toBe(false)
    expect(btn('insert-tag').attributes('aria-label')).toBeTruthy()

    await btn('insert-tag').trigger('click')
    await vi.advanceTimersByTimeAsync(20)

    expect(h.editor.getText()).toBe('#')
    expect(h.editor.isFocused).toBe(true)
    expect(tagSuggestion.open).toBe(true)
    expect(h.lastPost('requestTagCandidates')?.payload?.query).toBe('')
  })

  it('preserves the cursor on mousedown and inserts a selected tag between surrounding text', async () => {
    await h.type('前文后文')
    h.editor.commands.setTextSelection(3)
    const event = new MouseEvent('mousedown', { bubbles: true, cancelable: true })
    btn('insert-tag').element.dispatchEvent(event)
    expect(event.defaultPrevented).toBe(true)
    expect(h.editor.state.selection.from).toBe(3)

    await btn('insert-tag').trigger('click')
    await vi.advanceTimersByTimeAsync(20)
    expect(h.editor.getText()).toBe('前文 #后文')
    expect(h.lastPost('requestTagCandidates')?.payload?.query).toBe('')

    const request = h.lastPost('requestTagCandidates')!
    h.api.resolveTagCandidates(request.payload!.reqId, JSON.stringify(['工作/项目']))
    selectTag('工作/项目')
    await h.type('继续')

    expect(h.editor.getJSON().content?.[0]?.content).toEqual([
      { type: 'text', text: '前文 ' },
      { type: 'text', text: '#工作/项目', marks: [{ type: 'tag', attrs: { tag: '工作/项目' } }] },
      { type: 'text', text: ' 继续后文' },
    ])
    expect(tagSuggestion.open).toBe(false)
  })

  it('replaces the selected text when starting a tag', async () => {
    await h.type('前文要替换后文')
    h.editor.commands.setTextSelection({ from: 3, to: 6 })

    await btn('insert-tag').trigger('click')
    await vi.advanceTimersByTimeAsync(20)

    expect(h.editor.getText()).toBe('前文 #后文')
    expect(h.editor.state.selection.empty).toBe(true)
    expect(h.lastPost('requestTagCandidates')?.payload?.query).toBe('')
    selectTag('生活')
    expect(h.editor.getText()).toBe('前文 #生活 后文')
  })

  it('reuses an open tag query when clicked again', async () => {
    await btn('insert-tag').trigger('click')
    await h.type('工')
    const request = h.lastPost('requestTagCandidates')!
    h.api.resolveTagCandidates(request.payload!.reqId, JSON.stringify(['工作']))
    const requestCount = h.posted.filter((message) => message.type === 'requestTagCandidates').length

    await btn('insert-tag').trigger('click')
    await vi.advanceTimersByTimeAsync(20)

    expect(h.editor.getText()).toBe('#工')
    expect(tagSuggestion.open).toBe(true)
    expect(tagSuggestion.items).toEqual(['工作'])
    expect(h.posted.filter((message) => message.type === 'requestTagCandidates')).toHaveLength(requestCount)
    selectTag('工作')
    expect(h.editor.getText()).toBe('#工作 ')
  })

  it('separates a new tag from a completed tag without damaging its mark', async () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph', content: [
        { type: 'text', text: '#工作', marks: [{ type: 'tag', attrs: { tag: '工作' } }] },
      ] },
    ] }))
    h.editor.commands.setTextSelection(4)
    await nextTick()
    expect(disabled('insert-tag')).toBe(false)

    await btn('insert-tag').trigger('click')
    await vi.advanceTimersByTimeAsync(20)

    expect(h.editor.getJSON().content?.[0]?.content).toEqual([
      { type: 'text', text: '#工作', marks: [{ type: 'tag', attrs: { tag: '工作' } }] },
      { type: 'text', text: ' #' },
    ])
    expect(h.lastPost('requestTagCandidates')?.payload?.query).toBe('')
    selectTag('生活')
    expect(h.editor.getJSON().content?.[0]?.content).toEqual([
      { type: 'text', text: '#工作', marks: [{ type: 'tag', attrs: { tag: '工作' } }] },
      { type: 'text', text: ' ' },
      { type: 'text', text: '#生活', marks: [{ type: 'tag', attrs: { tag: '生活' } }] },
      { type: 'text', text: ' ' },
    ])
  })

  it.each(['heading', 'codeBlock'])('is disabled inside a %s', async (type) => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type, ...(type === 'heading' ? { attrs: { level: 1 } } : {}), content: [{ type: 'text', text: '内容' }] },
    ] }))
    h.editor.commands.setTextSelection(2)
    await nextTick()
    const before = h.editor.getJSON()
    const requestCount = h.posted.filter((message) => message.type === 'requestTagCandidates').length

    expect(disabled('insert-tag')).toBe(true)
    await btn('insert-tag').trigger('click')
    expect(h.editor.getJSON()).toEqual(before)
    expect(h.posted.filter((message) => message.type === 'requestTagCandidates')).toHaveLength(requestCount)
  })

  it.each(['code', 'link', 'tag'])('is disabled inside a %s mark', async (type) => {
    const attrs = type === 'link' ? { href: 'https://example.test' }
      : type === 'tag' ? { tag: '工作' } : undefined
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph', content: [
        { type: 'text', text: '#工作', marks: [{ type, attrs }] },
      ] },
    ] }))
    h.editor.commands.setTextSelection(2)
    await nextTick()
    const before = h.editor.getJSON()
    const requestCount = h.posted.filter((message) => message.type === 'requestTagCandidates').length

    expect(disabled('insert-tag')).toBe(true)
    await btn('insert-tag').trigger('click')
    expect(h.editor.getJSON()).toEqual(before)
    expect(h.posted.filter((message) => message.type === 'requestTagCandidates')).toHaveLength(requestCount)
  })
})

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { closeHistory } from '@tiptap/pm/history'
import { setupEditor, type EditorHarness } from '../test/harness'
import { selectTag, tagChoices, tagSuggestion } from './tag'

let h: EditorHarness
const type = async (text: string): Promise<void> => {
  h.editor.view.dispatch(h.editor.state.tr.insertText(text))
  await vi.advanceTimersByTimeAsync(0)
}
const tags = (): string[] => {
  const found = new Set<string>()
  h.editor.state.doc.descendants((node) => {
    for (const mark of node.marks) if (mark.type.name === 'tag') found.add(mark.attrs.tag)
  })
  return [...found]
}

beforeEach(() => {
  vi.useFakeTimers()
  h = setupEditor()
})
afterEach(() => {
  h.destroy()
  vi.useRealTimers()
})

describe('inline tags', () => {
  it('recognizes a Chinese hierarchical tag on space, preserving normal text', async () => {
    await type('今天又改了方案 #工作/项目')
    expect(tags()).toEqual([])
    await type(' ')
    expect(tags()).toEqual(['工作/项目'])
    expect(h.editor.getText()).toBe('今天又改了方案 #工作/项目 ')
    await type('继续写')
    expect(h.editor.state.doc.lastChild?.lastChild?.marks).toEqual([])
  })

  it('recognizes a tag when Enter starts a new paragraph', async () => {
    await type('#生活/运动')
    h.editor.commands.splitBlock()
    expect(tags()).toEqual(['生活/运动'])
  })

  it('waits for a delimiter while typing in a paragraph before existing content', async () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph' },
      { type: 'paragraph', content: [{ type: 'text', text: '已有下一段' }] },
    ] }))
    h.editor.commands.setTextSelection(1)
    for (const character of '#工作') {
      await type(character)
      expect(tags()).toEqual([])
    }
    await type(' ')
    expect(tags()).toEqual(['工作'])
  })

  it('waits for a delimiter while typing in the last list paragraph', async () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'bulletList', content: [{ type: 'listItem', content: [{ type: 'paragraph' }] }] },
    ] }))
    h.editor.commands.setTextSelection(3)
    for (const character of '#工作') {
      await type(character)
      expect(tags()).toEqual([])
    }
    await type(' ')
    expect(tags()).toEqual(['工作'])
  })

  it('completes a list tag when Enter creates the next item', async () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'bulletList', content: [{ type: 'listItem', content: [{ type: 'paragraph' }] }] },
    ] }))
    h.editor.commands.setTextSelection(3)
    await type('#工作')
    expect(tags()).toEqual([])
    h.editor.commands.splitListItem('listItem')
    expect(tags()).toEqual(['工作'])
  })

  it('extends the full tag when text is appended at a completed mark boundary', async () => {
    await type('#工 ')
    h.editor.commands.setTextSelection(3)
    await type('作')
    expect(tags()).toEqual(['工作'])
    expect(h.editor.getText()).toBe('#工作 ')
    h.editor.commands.setTextSelection(4)
    await type('/项目')
    expect(tags()).toEqual(['工作/项目'])
  })

  it('deduplicates repeated tag associations and updates edited marks', async () => {
    await type('#工作 #工作 ')
    expect(tags()).toEqual(['工作'])
    h.editor.commands.insertContentAt({ from: 2, to: 4 }, '生活')
    expect(tags()).toEqual(['生活', '工作'])
    h.editor.commands.deleteRange({ from: 1, to: 4 })
    expect(tags()).toEqual(['工作'])
  })

  it('preserves undo and redo of tag completion', async () => {
    await type('#工作')
    h.editor.view.dispatch(closeHistory(h.editor.state.tr))
    await type(' ')
    expect(tags()).toEqual(['工作'])
    h.editor.commands.undo()
    expect(tags()).toEqual([])
    expect(h.editor.getText()).toBe('#工作')
    h.editor.commands.redo()
    expect(tags()).toEqual(['工作'])
  })

  it('removes a header tag without clearing undo history or removing child tags', async () => {
    await type('#工作 #工作/项目 ')
    h.editor.view.dispatch(closeHistory(h.editor.state.tr))
    h.api.removeTag('工作')
    expect(tags()).toEqual(['工作/项目'])
    expect(h.editor.getText()).toBe('工作 #工作/项目 ')
    h.editor.commands.undo()
    expect(tags()).toEqual(['工作', '工作/项目'])
    expect(h.editor.getText()).toBe('#工作 #工作/项目 ')
    h.editor.commands.redo()
    expect(tags()).toEqual(['工作/项目'])
  })

  it('preserves an internal hash when removing a formatted C# tag', () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph', content: [
        { type: 'text', text: '#C', marks: [{ type: 'tag', attrs: { tag: 'C#' } }] },
        { type: 'text', text: '#', marks: [{ type: 'tag', attrs: { tag: 'C#' } }, { type: 'italic' }] },
      ] },
    ] }))
    h.api.removeTag('C#')
    expect(tags()).toEqual([])
    expect(h.editor.getText()).toBe('C#')
  })

  it('does not interpret plain hashes, URL fragments or invalid hierarchy paths', async () => {
    await type('# ##标题 C#语言 https://a.test/#片段 #/空 #空//段 #尾/ ')
    expect(tags()).toEqual([])
  })

  it('does not interpret heading or code content', async () => {
    h.editor.commands.setContent({ type: 'doc', content: [
      { type: 'heading', attrs: { level: 1 }, content: [{ type: 'text', text: '#标题 ' }] },
      { type: 'codeBlock', content: [{ type: 'text', text: '#代码 ' }] },
      { type: 'paragraph', content: [
        { type: 'text', text: '#行内代码 ', marks: [{ type: 'code' }] },
        { type: 'text', text: '#链接 ', marks: [{ type: 'link', attrs: { href: 'https://example.test' } }] },
      ] },
    ] })
    expect(tags()).toEqual([])
  })

  it('recognizes pasted text including a final tag without a trailing space', () => {
    h.editor.view.dispatch(h.editor.state.tr.insertText('记一笔 #生活/运动').setMeta('uiEvent', 'paste'))
    expect(tags()).toEqual(['生活/运动'])
  })

  it('does not rewrite legacy hashes when loading a saved document', () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph', content: [{ type: 'text', text: '#普通文本 ' }] },
    ] }))
    expect(tags()).toEqual([])
  })

  it('does not turn old hashes in other paragraphs into tags on unrelated edits', async () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph', content: [{ type: 'text', text: '#旧说明 ' }] },
      { type: 'paragraph', content: [{ type: 'text', text: '#另一个旧词 ' }] },
      { type: 'paragraph', content: [{ type: 'text', text: '今天' }] },
    ] }))
    h.editor.commands.setTextSelection(h.editor.state.doc.content.size - 1)
    await type('写正文 #新标签 ')
    expect(tags()).toEqual(['新标签'])
    h.editor.commands.undo()
    expect(tags()).toEqual([])
    h.editor.commands.redo()
    expect(tags()).toEqual(['新标签'])
  })

  it('does not recognize an old hash when editing elsewhere in the same paragraph', async () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph', content: [{ type: 'text', text: '#说明 后面还有正文' }] },
    ] }))
    h.editor.commands.setTextSelection(h.editor.state.doc.content.size - 1)
    await type('再补充一些')
    expect(tags()).toEqual([])
    h.editor.commands.setTextSelection(1)
    await type('前面补充 ')
    expect(tags()).toEqual([])
  })

  it('limits paste recognition to the pasted range', () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph', content: [{ type: 'text', text: '#旧说明 普通正文 ' }] },
    ] }))
    h.editor.commands.setTextSelection(h.editor.state.doc.content.size - 1)
    h.editor.view.dispatch(h.editor.state.tr.insertText('#新标签').setMeta('uiEvent', 'paste'))
    expect(tags()).toEqual(['新标签'])
  })

  it('retains the edited range through IME composition without recognizing old hashes', async () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph', content: [{ type: 'text', text: '#旧说明 后文 ' }] },
    ] }))
    h.editor.commands.setTextSelection(h.editor.state.doc.content.size - 1)
    const composing = vi.spyOn(h.editor.view, 'composing', 'get').mockReturnValue(true)
    await type('#工作 ')
    expect(tags()).toEqual([])
    composing.mockReturnValue(false)
    h.editor.view.dom.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true }))
    await vi.advanceTimersByTimeAsync(0)
    expect(tags()).toEqual(['工作'])
  })

  it('retains explicit legacy tags with spaces after other edits', async () => {
    h.api.setContent(JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph', content: [
        { type: 'text', text: '#工作 会议', marks: [{ type: 'tag', attrs: { tag: '工作 会议' } }] },
        { type: 'text', text: ' ' },
      ] },
    ] }))
    h.editor.commands.setTextSelection(h.editor.state.doc.content.size - 1)
    await type('继续写')
    expect(tags()).toEqual(['工作 会议'])
  })

  it('exports the visible hashtag to Markdown without HTML markup', async () => {
    await type('记录 #工作/项目 ')
    const storage = h.editor.storage as unknown as { markdown: { getMarkdown(): string } }
    expect(storage.markdown.getMarkdown()).toBe('记录 #工作/项目 ')
  })
})

describe('tag suggestions', () => {
  it('can select a legacy C# tag without losing the internal hash', async () => {
    await type('#')
    const request = h.lastPost('requestTagCandidates')!
    h.api.resolveTagCandidates(request.payload!.reqId, JSON.stringify(['C#']))
    expect(tagChoices()).toEqual(['C#'])
    selectTag('C#')
    await type('继续写')
    expect(tags()).toEqual(['C#'])
    expect(h.editor.getText()).toBe('#C# 继续写')
  })

  it('requests history at # and supports creating a new path', async () => {
    await type('#')
    const first = h.lastPost('requestTagCandidates')!
    expect(first.payload?.query).toBe('')
    h.api.resolveTagCandidates(first.payload!.reqId, JSON.stringify(['工作/项目']))
    expect(tagChoices()).toEqual(['工作/项目'])
    await type('生活/运动')
    expect(tagChoices()).toEqual(['生活/运动'])
    selectTag('生活/运动')
    expect(tags()).toEqual(['生活/运动'])
    expect(h.editor.getText()).toBe('#生活/运动 ')
  })

  it('filters stale responses and lets the user choose historical tags', async () => {
    await type('#')
    const oldRequest = h.lastPost('requestTagCandidates')!
    await type('工')
    const request = h.lastPost('requestTagCandidates')!
    h.api.resolveTagCandidates(oldRequest.payload!.reqId, JSON.stringify(['过时']))
    expect(tagSuggestion.items).toEqual([])
    h.api.resolveTagCandidates(request.payload!.reqId, JSON.stringify(['工作/项目']))
    await h.press('Enter')
    expect(tags()).toEqual(['工作/项目'])
    expect(tagSuggestion.open).toBe(false)
  })

  it('does not consume Enter during IME composition', async () => {
    await type('#工')
    const request = h.lastPost('requestTagCandidates')!
    h.api.resolveTagCandidates(request.payload!.reqId, JSON.stringify(['工作']))
    vi.spyOn(h.editor.view, 'composing', 'get').mockReturnValue(true)
    const event = new KeyboardEvent('keydown', { key: 'Enter', isComposing: true, bubbles: true, cancelable: true })
    h.editor.view.dom.dispatchEvent(event)
    expect(tags()).toEqual([])
  })
})

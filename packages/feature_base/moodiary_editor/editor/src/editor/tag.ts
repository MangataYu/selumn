import { Mark, mergeAttributes } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import type { EditorState, Transaction } from '@tiptap/pm/state'
import Suggestion, { type SuggestionProps } from '@tiptap/suggestion'
import { reactive } from 'vue'
import { post } from '../bridge/post'

const pathPattern = /^[\p{L}\p{M}\p{N}_-]+(?:\/[\p{L}\p{M}\p{N}_-]+)*$/u
const tokenPattern = /#([\p{L}\p{M}\p{N}_/-]+)(?=\s|$)/gu
const pathCharacter = /[\p{L}\p{M}\p{N}_/-]/u
export const validTag = (value: string): boolean => pathPattern.test(value)
const validStoredTag = (value: string): boolean => value.length > 0 &&
  !/[\r\n\t]/.test(value) && value.split('/').every((part) => part.trim().length > 0)

// Tags can touch ordinary text, but repeated hashes and URL fragments stay literal.
const validTagStart = (text: string, start: number): boolean =>
  text[start - 1] !== '#' &&
  !/(?:[a-z][a-z\d+.-]*:\/\/|www\.)\S*$/iu.test(text.slice(0, start))

export const tagSuggestion = reactive({
  open: false,
  loading: false,
  query: '',
  items: [] as string[],
  index: 0,
  rect: null as { left: number; top: number; bottom: number } | null,
})
let command: ((tag: string) => void) | null = null
let requestSequence = 0
let activeRequest = ''
let requestTimer = 0

export function selectTag(tag: string): void {
  if (validStoredTag(tag)) command?.(tag)
}

function close(): void {
  tagSuggestion.open = false
  tagSuggestion.loading = false
  tagSuggestion.items = []
  activeRequest = ''
  window.clearTimeout(requestTimer)
  command = null
}

export function resolveTagCandidates(reqId: string, json: string): void {
  if (reqId !== activeRequest || !tagSuggestion.open) return
  window.clearTimeout(requestTimer)
  tagSuggestion.loading = false
  let candidates: unknown
  try {
    candidates = JSON.parse(json)
  } catch {
    candidates = []
  }
  tagSuggestion.items = Array.isArray(candidates)
    ? [...new Set(candidates.filter((x): x is string => typeof x === 'string' && validStoredTag(x)))].slice(0, 20)
    : []
  tagSuggestion.index = 0
}

export function tagChoices(): string[] {
  const query = tagSuggestion.query
  return validTag(query) && !tagSuggestion.items.includes(query)
    ? [...tagSuggestion.items, query]
    : tagSuggestion.items
}

function update(props: SuggestionProps<string>): void {
  command = props.command
  const rect = props.clientRect?.()
  if (rect) tagSuggestion.rect = { left: rect.left, top: rect.top, bottom: rect.bottom }
  const query = props.query ?? ''
  if (tagSuggestion.open && tagSuggestion.query === query) return
  tagSuggestion.open = true
  tagSuggestion.query = query
  tagSuggestion.items = []
  tagSuggestion.index = 0
  tagSuggestion.loading = true
  activeRequest = `tag-${++requestSequence}`
  post('requestTagCandidates', { reqId: activeRequest, query })
  window.clearTimeout(requestTimer)
  requestTimer = window.setTimeout(() => {
    tagSuggestion.loading = false
    activeRequest = ''
  }, 4000)
}

interface EditedRange { from: number; to: number }

function editedRanges(transactions: readonly Transaction[], pending: EditedRange[] = []): EditedRange[] {
  let ranges = pending
  for (const transaction of transactions) {
    for (const map of transaction.mapping.maps) {
      ranges = ranges.map((range) => ({
        from: map.map(range.from, -1),
        to: map.map(range.to, 1),
      }))
      map.forEach((_oldStart, _oldEnd, from, to) => ranges.push({ from, to }))
    }
  }
  return ranges
}

// Normalize explicit marks throughout the document, but recognize new tags only
// where text changed. Old literal hashes must survive edits elsewhere unchanged.
function normalizeTags(state: EditorState, pasted: boolean, edits: EditedRange[], completedAt?: number): Transaction | null {
  const mark = state.schema.marks.tag!
  const tr = state.tr
  state.doc.descendants((node, pos) => {
    if (!node.isTextblock) return true
    const allowed = node.type.name !== 'codeBlock' && node.type.name !== 'heading'
    const text = node.textBetween(0, node.content.size, '\n', '\ufffc')
    const ranges: Array<{ from: number; to: number; tag: string }> = []
    if (allowed) {
      // Existing tags may have spaces or punctuation (legacy names / renames).
      // Preserve a complete explicit mark even if it cannot be typed as #word.
      let run: { from: number; to: number; tag: string; text: string } | null = null
      const finishRun = (): void => {
        if (run && validStoredTag(run.tag) && run.text === `#${run.tag}`) {
          const start = run.from - pos - 1
          const end = run.to - pos - 1
          // A non-inclusive mark leaves appended characters outside the mark.
          // Reparse that token instead of preserving only its old prefix.
          const extended = end < text.length && pathCharacter.test(text[end]!)
          if (validTagStart(text, start) && !extended) ranges.push(run)
        }
        run = null
      }
      node.forEach((child, offset) => {
        const value = child.marks.find((m) => m.type === mark)?.attrs.tag
        const blocked = child.marks.some((m) => ['code', 'link'].includes(m.type.name))
        const from = pos + 1 + offset
        if (!child.isText || typeof value !== 'string' || blocked) { finishRun(); return }
        if (run && run.tag === value && run.to === from) {
          run.to += child.nodeSize
          run.text += child.text ?? ''
        } else {
          finishRun()
          run = { from, to: from + child.nodeSize, tag: value, text: child.text ?? '' }
        }
      })
      finishRun()
      const pattern = new RegExp(tokenPattern)
      let match: RegExpExecArray | null
      while ((match = pattern.exec(text)) !== null) {
        const tag = match[1]!
        const start = match.index
        if (!validTag(tag) || !validTagStart(text, start)) continue
        const from = pos + 1 + start
        const to = from + tag.length + 1
        if (ranges.some((range) => from < range.to && to > range.from)) continue
        let blocked = false
        let wasTag = false
        node.nodesBetween(start, start + tag.length + 1, (child) => {
          if (child.marks.some((m) => m.type.name === 'code' || m.type.name === 'link')) blocked = true
          if (child.marks.some((m) => m.type === mark)) wasTag = true
        })
        const affected = edits.some((range) =>
          (range.to > from && range.from <= to) ||
          (range.from === range.to && range.from > from && range.from <= to))
        if (!wasTag && !affected) continue
        const complete = start + tag.length + 1 < text.length ||
          to === completedAt || pasted || wasTag
        if (!blocked && complete) ranges.push({ from, to, tag })
      }
    }
    node.descendants((child, offset) => {
      if (!child.isText) return
      const from = pos + 1 + offset
      const to = from + child.nodeSize
      const current = child.marks.find((m) => m.type === mark)
      if (current && !ranges.some((r) => from >= r.from && to <= r.to && r.tag === current.attrs.tag)) {
        tr.removeMark(from, to, mark)
      }
    })
    for (const range of ranges) tr.addMark(range.from, range.to, mark.create({ tag: range.tag }))
    return false
  })
  return tr.doc.eq(state.doc) ? null : tr
}

export const Tag = Mark.create({
  name: 'tag',
  inclusive: false,
  onDestroy: close,
  addStorage: () => ({ markdown: { serialize: { open: '', close: '' } } }),
  addAttributes: () => ({ tag: { default: null, parseHTML: (el) => el.getAttribute('data-tag') } }),
  parseHTML: () => [{ tag: 'span[data-tag]' }],
  renderHTML: ({ HTMLAttributes }) => ['span', mergeAttributes({ class: 'moodiary-tag', 'data-tag': HTMLAttributes.tag }, HTMLAttributes), 0],
  addProseMirrorPlugins() {
    const editor = this.editor
    let compositionEdits: EditedRange[] = []
    return [
      new Plugin({
        key: new PluginKey('normalizeTags'),
        appendTransaction(transactions, oldState, state) {
          if (!editor.isEditable || transactions.some((tr) => tr.getMeta('preventUpdate'))) {
            compositionEdits = []
            return null
          }
          if (!transactions.some((tr) => tr.docChanged)) return null
          const edits = editedRanges(transactions, compositionEdits)
          if (editor.view.composing) {
            compositionEdits = edits
            return null
          }
          compositionEdits = []
          // Enter completes the token at the old cursor, including inside a
          // list/quote. Other paragraphs already existing after it do not.
          let completedAt: number | undefined
          if (oldState.selection.empty && state.selection.empty &&
            state.selection.$from.parentOffset === 0) {
            completedAt = oldState.selection.from
            for (const transaction of transactions) {
              completedAt = transaction.mapping.map(completedAt, -1)
            }
          }
          return normalizeTags(
            state,
            transactions.some((tr) => tr.getMeta('uiEvent') === 'paste'),
            edits,
            completedAt,
          )
        },
        props: {
          handleDOMEvents: {
            compositionend: (view) => {
              window.setTimeout(() => {
                if (!view.isDestroyed) {
                  const edits = compositionEdits
                  compositionEdits = []
                  const tr = normalizeTags(view.state, false, edits)
                  if (tr) view.dispatch(tr)
                }
              }, 0)
              return false
            },
          },
        },
      }),
      Suggestion<string>({
        editor,
        pluginKey: new PluginKey('tagSuggestion'),
        char: '#',
        allowedPrefixes: null,
        allow: ({ state, range }) => {
          const at = state.doc.resolve(range.from)
          const prefix = at.parent.textBetween(0, at.parentOffset, '\n', '\ufffc')
          return at.parent.type.name !== 'codeBlock' && at.parent.type.name !== 'heading' &&
            validTagStart(prefix, prefix.length) &&
            !at.marks().some((m) => ['code', 'link', 'tag'].includes(m.type.name))
        },
        items: () => [],
        command: ({ editor, range, props: tag }) => {
          if (!validStoredTag(tag)) return
          editor.chain().focus().insertContentAt(range, [
            { type: 'text', text: `#${tag}`, marks: [{ type: 'tag', attrs: { tag } }] },
            { type: 'text', text: ' ' },
          ]).run()
          close()
        },
        render: () => ({
          onStart: update,
          onUpdate: update,
          onExit: close,
          onKeyDown: ({ event }) => {
            if (event.isComposing || editor.view.composing) return false
            if (event.key === 'Escape') { close(); return true }
            const choices = tagChoices()
            if (event.key === 'ArrowDown' && choices.length) {
              tagSuggestion.index = (tagSuggestion.index + 1) % choices.length
              return true
            }
            if (event.key === 'ArrowUp' && choices.length) {
              tagSuggestion.index = (tagSuggestion.index - 1 + choices.length) % choices.length
              return true
            }
            if (event.key === 'Enter' && choices.length && tagSuggestion.items.length) {
              selectTag(choices[tagSuggestion.index]!)
              return true
            }
            return false
          },
        }),
      }),
    ]
  },
})

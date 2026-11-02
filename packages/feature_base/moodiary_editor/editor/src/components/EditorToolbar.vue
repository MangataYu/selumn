<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, type Component } from 'vue'
import type { Editor } from '@tiptap/core'
import IconUndo from '~icons/lucide/undo-2'
import IconRedo from '~icons/lucide/redo-2'
import IconHash from '~icons/lucide/hash'
import IconImage from '~icons/lucide/image'
import IconAudio from '~icons/lucide/music'
import IconVideo from '~icons/lucide/video'
import IconBold from '~icons/lucide/bold'
import IconItalic from '~icons/lucide/italic'
import IconUnderline from '~icons/lucide/underline'
import IconStrike from '~icons/lucide/strikethrough'
import IconCode from '~icons/lucide/code'
import IconBullet from '~icons/lucide/list'
import IconOrdered from '~icons/lucide/list-ordered'
import IconQuote from '~icons/lucide/quote'
import IconCodeBlock from '~icons/lucide/square-code'
import IconChecklist from '~icons/lucide/list-checks'
import IconTable from '~icons/lucide/table'
import IconLink from '~icons/lucide/link'
import IconSeparator from '~icons/lucide/separator-horizontal'
import IconSearch from '~icons/lucide/search'
import IconPlus from '~icons/lucide/plus'
import IconType from '~icons/lucide/type'
import IconArrowLeft from '~icons/lucide/arrow-left'
import IconArrowUp from '~icons/lucide/arrow-up'
import IconArrowDown from '~icons/lucide/arrow-down'
import IconSliders from '~icons/lucide/sliders-horizontal'
import IconClose from '~icons/lucide/x'
import IconChevronRight from '~icons/lucide/chevron-right'
import IconParagraph from '~icons/lucide/pilcrow'
import IconH1 from '~icons/lucide/heading-1'
import IconH2 from '~icons/lucide/heading-2'
import IconH3 from '~icons/lucide/heading-3'
import { openSearch } from '../editor/search'
import { tagSuggestion } from '../editor/tag'
import { post } from '../bridge/post'
import TableGridPicker from './TableGridPicker.vue'
import PopupMenu from './PopupMenu.vue'
import type { PopupMenuItem } from './PopupMenu.vue'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  editor: Editor
  platform: 'mobile' | 'desktop'
  toolbarOrder?: string[]
}>()

const emit = defineEmits<{
  (e: 'pick-image'): void
  (e: 'pick-audio'): void
  (e: 'pick-video'): void
}>()

const { t } = useI18n()

const btnClass = computed(
  () => `btn btn-ghost shrink-0 ${props.platform === 'mobile' ? 'btn-md' : 'btn-sm'}`,
)

const tick = ref(0)
const bump = (): void => {
  tick.value += 1
}
onMounted(() => props.editor.on('transaction', bump))
onBeforeUnmount(() => props.editor.off('transaction', bump))

const isActive = (name: string, attrs?: Record<string, unknown>): boolean => {
  void tick.value
  return props.editor.isActive(name, attrs)
}

const chain = () => props.editor.chain().focus()

const canUndo = (): boolean => {
  void tick.value
  return props.editor.can().undo()
}
const canRedo = (): boolean => {
  void tick.value
  return props.editor.can().redo()
}

const insertLink = (): void => {
  chain().insertContent('[[').run()
}

const canInsertTag = (): boolean =>
  !['heading', 'codeBlock', 'code', 'link', 'tag'].some((name) => isActive(name))

const insertTag = (): void => {
  if (tagSuggestion.open) {
    chain().run()
    return
  }
  const { $from } = props.editor.state.selection
  const before = $from.parent.textBetween(0, $from.parentOffset, '\n', '\ufffc')
  // Explicit text avoids interpreting the hash as a Markdown heading.
  chain().insertContent({ type: 'text', text: before && !/\s$/.test(before) ? ' #' : '#' }).run()
}

interface Tool {
  key: string
  title: string
  icon?: Component
  label?: string
  run: () => void
  active: () => boolean
}

const tools = computed<Tool[]>(() => [
  { key: 'bold', title: t('toolbar.bold'), icon: IconBold, run: () => chain().toggleBold().run(), active: () => isActive('bold') },
  { key: 'italic', title: t('toolbar.italic'), icon: IconItalic, run: () => chain().toggleItalic().run(), active: () => isActive('italic') },
  { key: 'underline', title: t('toolbar.underline'), icon: IconUnderline, run: () => chain().toggleUnderline().run(), active: () => isActive('underline') },
  { key: 'strike', title: t('toolbar.strike'), icon: IconStrike, run: () => chain().toggleStrike().run(), active: () => isActive('strike') },
  { key: 'code', title: t('toolbar.code'), icon: IconCode, run: () => chain().toggleCode().run(), active: () => isActive('code') },
  { key: 'bullet', title: t('toolbar.bulletList'), icon: IconBullet, run: () => chain().toggleBulletList().run(), active: () => isActive('bulletList') },
  { key: 'ordered', title: t('toolbar.orderedList'), icon: IconOrdered, run: () => chain().toggleOrderedList().run(), active: () => isActive('orderedList') },
  { key: 'task', title: t('toolbar.taskList'), icon: IconChecklist, run: () => chain().toggleTaskList().run(), active: () => isActive('taskList') },
  { key: 'quote', title: t('toolbar.quote'), icon: IconQuote, run: () => chain().toggleBlockquote().run(), active: () => isActive('blockquote') },
  { key: 'codeBlock', title: t('toolbar.codeBlock'), icon: IconCodeBlock, run: () => chain().toggleCodeBlock().run(), active: () => isActive('codeBlock') },
])

const inTable = (): boolean => isActive('table')

const tableOpen = ref(false)
const tablePos = ref({ left: 0, top: 0 })
function openTablePicker(e: MouseEvent): void {
  const rect = (e.currentTarget as HTMLElement).getBoundingClientRect()
  const PW = 184
  const PH = 214
  const M = 8
  const vw = window.innerWidth
  const vh = window.innerHeight
  let left = rect.left
  if (left + PW > vw - M) left = vw - PW - M
  if (left < M) left = M
  let top = rect.bottom + 4
  if (top + PH > vh - M) top = rect.top - PH - 4
  if (top < M) top = M
  tablePos.value = { left: Math.round(left), top: Math.round(top) }
  tableOpen.value = true
}
function onPickTable(rows: number, cols: number): void {
  chain().insertTable({ rows, cols, withHeaderRow: true }).run()
  tableOpen.value = false
}
const tableOps = computed<{ key: string; label: string; title: string; run: () => void }[]>(() => [
  { key: 'rowAfter', label: t('toolbar.rowAfterLabel'), title: t('toolbar.rowAfter'), run: () => chain().addRowAfter().run() },
  { key: 'delRow', label: t('toolbar.deleteRowLabel'), title: t('toolbar.deleteRow'), run: () => chain().deleteRow().run() },
  { key: 'colAfter', label: t('toolbar.columnAfterLabel'), title: t('toolbar.columnAfter'), run: () => chain().addColumnAfter().run() },
  { key: 'delCol', label: t('toolbar.deleteColumnLabel'), title: t('toolbar.deleteColumn'), run: () => chain().deleteColumn().run() },
  { key: 'delTable', label: t('toolbar.deleteTableLabel'), title: t('toolbar.deleteTable'), run: () => chain().deleteTable().run() },
])

const headingMenuOpen = ref(false)
const headingItems = computed<PopupMenuItem[]>(() => [
  { key: 'paragraph', label: t('toolbar.paragraph'), icon: IconParagraph, active: !isActive('heading') },
  { key: 'h1', label: t('toolbar.heading1'), icon: IconH1, active: isActive('heading', { level: 1 }) },
  { key: 'h2', label: t('toolbar.heading2'), icon: IconH2, active: isActive('heading', { level: 2 }) },
  { key: 'h3', label: t('toolbar.heading3'), icon: IconH3, active: isActive('heading', { level: 3 }) },
])
function onHeadingSelect(key: string): void {
  if (key === 'paragraph') {
    const level = isActive('heading', { level: 1 })
      ? 1
      : isActive('heading', { level: 2 })
        ? 2
        : isActive('heading', { level: 3 })
          ? 3
          : 1
    chain().toggleHeading({ level }).run()
  } else if (key === 'h1') {
    chain().toggleHeading({ level: 1 }).run()
  } else if (key === 'h2') {
    chain().toggleHeading({ level: 2 }).run()
  } else if (key === 'h3') {
    chain().toggleHeading({ level: 3 }).run()
  }
}

// Stable IDs are persisted by the host; append new actions rather than renaming them.
const defaultMobileOrder = [
  'undo', 'image', 'tag', 'redo', 'audio', 'video', 'diaryLink', 'divider',
  'heading', 'bold', 'italic', 'underline', 'strike', 'code', 'bullet',
  'ordered', 'task', 'quote', 'codeBlock', 'table', 'search',
] as const

function normalizeOrder(raw: unknown): string[] {
  const allowed = new Set<string>(defaultMobileOrder)
  const ids = Array.isArray(raw) ? raw.filter((id): id is string => typeof id === 'string' && allowed.has(id)) : []
  const known = [...new Set(ids)]
  return [...known, ...defaultMobileOrder.filter((id) => !known.includes(id))]
}

// Keep future-version IDs on disk even though this version cannot display them.
const unknownMobileIds = Array.isArray(props.toolbarOrder)
  ? [...new Set(props.toolbarOrder.filter((id) => typeof id === 'string' && !defaultMobileOrder.includes(id as typeof defaultMobileOrder[number])))]
  : []
const mobileOrder = ref(normalizeOrder(props.toolbarOrder))
const mobileMode = ref<'main' | 'format'>('main')
const mobilePanel = ref<'insert' | 'order' | null>(null)

interface MobileAction {
  key: string
  title: string
  shortTitle?: string
  icon: Component
  run: (event: MouseEvent) => void
  disabled?: () => boolean
  active?: () => boolean
}

const mobileActions = computed<MobileAction[]>(() => [
  { key: 'undo', title: t('toolbar.undo'), icon: IconUndo, run: () => chain().undo().run(), disabled: () => !canUndo() },
  { key: 'image', title: t('toolbar.insertImage'), shortTitle: t('toolbar.quickImage'), icon: IconImage, run: () => emit('pick-image') },
  { key: 'tag', title: t('toolbar.insertTag'), shortTitle: t('toolbar.quickTag'), icon: IconHash, run: insertTag, disabled: () => !canInsertTag() },
  { key: 'redo', title: t('toolbar.redo'), icon: IconRedo, run: () => chain().redo().run(), disabled: () => !canRedo() },
  { key: 'audio', title: t('toolbar.insertAudio'), shortTitle: t('toolbar.quickAudio'), icon: IconAudio, run: () => emit('pick-audio') },
  { key: 'video', title: t('toolbar.insertVideo'), shortTitle: t('toolbar.quickVideo'), icon: IconVideo, run: () => emit('pick-video') },
  { key: 'diaryLink', title: t('toolbar.insertDiaryLink'), shortTitle: t('toolbar.quickDiaryLink'), icon: IconLink, run: insertLink },
  { key: 'divider', title: t('toolbar.divider'), icon: IconSeparator, run: () => chain().setHorizontalRule().run() },
  { key: 'heading', title: t('toolbar.heading'), icon: IconH1, run: () => { headingMenuOpen.value = true }, active: () => isActive('heading') },
  ...tools.value.map((tool) => ({ key: tool.key, title: tool.title, icon: tool.icon!, run: tool.run, active: tool.active })),
  { key: 'table', title: t('toolbar.insertTable'), shortTitle: t('toolbar.quickTable'), icon: IconTable, run: openTablePicker },
  { key: 'search', title: t('toolbar.findReplace'), shortTitle: t('toolbar.quickSearch'), icon: IconSearch, run: openSearch },
])
const actionFor = (id: string): MobileAction => mobileActions.value.find((action) => action.key === id)!
const favoriteActions = computed(() => mobileOrder.value.slice(0, 3).map(actionFor))
const insertActions = computed(() => ['undo', 'redo', 'image', 'tag', 'audio', 'video', 'diaryLink', 'divider', 'table', 'search'].map(actionFor))

function runMobileAction(action: MobileAction, event: MouseEvent): void {
  mobilePanel.value = null
  action.run(event)
}

function moveMobileTool(index: number, delta: number): void {
  const target = index + delta
  if (target < 0 || target >= mobileOrder.value.length) return
  const next = [...mobileOrder.value]
  ;[next[index], next[target]] = [next[target]!, next[index]!]
  mobileOrder.value = next
  post('toolbarOrderChange', [...next, ...unknownMobileIds])
}
</script>

<template>
  <div
    v-if="platform === 'desktop'"
    class="moodiary-toolbar no-scrollbar flex items-center gap-0.5 overflow-x-auto bg-base-100 px-2 py-1.5"
    :class="platform === 'desktop' ? 'border-b border-base-300' : 'border-t border-base-300'"
  >
    <button
      :class="[btnClass, 'btn-square']"
      type="button"
      :title="t('toolbar.undo')"
      data-testid="undo"
      :disabled="!canUndo()"
      @mousedown.prevent
      @click="chain().undo().run()"
    >
      <IconUndo class="size-5" />
    </button>
    <button
      :class="[btnClass, 'btn-square']"
      type="button"
      :title="t('toolbar.redo')"
      data-testid="redo"
      :disabled="!canRedo()"
      @mousedown.prevent
      @click="chain().redo().run()"
    >
      <IconRedo class="size-5" />
    </button>
    <span class="mx-1 h-5 w-px shrink-0 bg-base-300" />

    <button
      :class="[btnClass, 'btn-square']"
      type="button"
      :title="t('toolbar.insertTag')"
      :aria-label="t('toolbar.insertTag')"
      data-testid="insert-tag"
      :disabled="!canInsertTag()"
      @mousedown.prevent
      @click="insertTag"
    >
      <IconHash class="size-5" />
    </button>
    <button :class="[btnClass, 'btn-square']" type="button" :title="t('toolbar.insertImage')" @mousedown.prevent @click="emit('pick-image')">
      <IconImage class="size-5" />
    </button>
    <button :class="[btnClass, 'btn-square']" type="button" :title="t('toolbar.insertAudio')" @mousedown.prevent @click="emit('pick-audio')">
      <IconAudio class="size-5" />
    </button>
    <button :class="[btnClass, 'btn-square']" type="button" :title="t('toolbar.insertVideo')" @mousedown.prevent @click="emit('pick-video')">
      <IconVideo class="size-5" />
    </button>
    <button :class="[btnClass, 'btn-square']" type="button" :title="t('toolbar.insertDiaryLink')" @mousedown.prevent @click="insertLink">
      <IconLink class="size-5" />
    </button>
    <button
      :class="[btnClass, 'gap-1 px-2']"
      type="button"
      :title="t('toolbar.insertDivider')"
      :aria-label="t('toolbar.insertDivider')"
      data-testid="insert-divider"
      @mousedown.prevent
      @click="chain().setHorizontalRule().run()"
    >
      <IconSeparator class="size-5" />
      <span class="text-sm">{{ t('toolbar.divider') }}</span>
    </button>
    <span class="mx-1 h-5 w-px shrink-0 bg-base-300" />
    <PopupMenu v-model="headingMenuOpen" :items="headingItems" @select="onHeadingSelect">
      <template #trigger>
        <button
          :class="[
            btnClass,
            'btn-square',
            isActive('heading') ? 'btn-active text-primary' : '',
          ]"
          type="button"
          :title="t('toolbar.heading')"
          @mousedown.prevent
        >
          <IconH1 v-if="isActive('heading', { level: 1 })" class="size-5" />
          <IconH2 v-else-if="isActive('heading', { level: 2 })" class="size-5" />
          <IconH3 v-else-if="isActive('heading', { level: 3 })" class="size-5" />
          <IconParagraph v-else class="size-5" />
        </button>
      </template>
    </PopupMenu>
    <button
      v-for="tool in tools"
      :key="tool.key"
      :class="[btnClass, tool.icon ? 'btn-square' : 'px-2', tool.active() ? 'btn-active text-primary' : '']"
      type="button"
      :title="tool.title"
      @mousedown.prevent
      @click="tool.run()"
    >
      <component :is="tool.icon" v-if="tool.icon" class="size-5" />
      <span v-else class="text-sm font-semibold leading-none">{{ tool.label }}</span>
    </button>

    <span class="mx-1 h-5 w-px shrink-0 bg-base-300" />
    <button :class="[btnClass, 'btn-square']" type="button" :title="t('toolbar.insertTable')" @mousedown.prevent @click="openTablePicker">
      <IconTable class="size-5" />
    </button>
    <template v-if="inTable()">
      <button
        v-for="op in tableOps"
        :key="op.key"
        :class="[btnClass, 'px-2']"
        type="button"
        :title="op.title"
        @mousedown.prevent
        @click="op.run()"
      >
        <span class="text-xs font-semibold leading-none">{{ op.label }}</span>
      </button>
    </template>

    <span class="mx-1 h-5 w-px shrink-0 bg-base-300" />
    <button :class="[btnClass, 'btn-square']" type="button" :title="t('toolbar.findReplace')" @mousedown.prevent @click="openSearch">
      <IconSearch class="size-5" />
    </button>

    <template v-if="tableOpen">
      <div class="fixed inset-0 z-[60]" @mousedown.prevent="tableOpen = false" />
      <TableGridPicker
        class="fixed z-[61]"
        :style="{ left: `${tablePos.left}px`, top: `${tablePos.top}px` }"
        @select="onPickTable"
      />
    </template>
  </div>

  <div v-else class="moodiary-toolbar relative border-t border-base-300 bg-base-100" data-testid="mobile-toolbar">
    <div v-if="mobilePanel" class="fixed inset-0 z-[60]" @mousedown.prevent="mobilePanel = null" @touchstart.prevent="mobilePanel = null" />

    <div v-if="mobilePanel === 'insert'" class="absolute bottom-full left-2 right-2 z-[61] mb-2 max-h-[45vh] overflow-y-auto rounded-xl bg-base-100 p-2 shadow-lg" data-testid="mobile-insert-panel">
      <div class="sticky top-0 z-10 bg-base-100">
        <button type="button" class="btn btn-ghost w-full justify-start" data-testid="mobile-reorder-open" @mousedown.prevent @click="mobilePanel = 'order'">
          <IconSliders class="size-5" /> {{ t('toolbar.reorder') }}
        </button>
      </div>
      <div class="grid grid-cols-3 gap-1">
        <button
          v-for="action in insertActions"
          :key="action.key"
          type="button"
          class="btn btn-ghost min-h-11 h-auto flex-col gap-1 py-2 text-xs"
          :aria-label="action.title"
          :disabled="action.disabled?.()"
          :data-testid="`mobile-insert-${action.key}`"
          @mousedown.prevent
          @click="runMobileAction(action, $event)"
        >
          <component :is="action.icon" class="size-5" />
          <span>{{ action.shortTitle ?? action.title }}</span>
        </button>
        <button
          v-for="op in inTable() ? tableOps : []"
          :key="op.key"
          type="button"
          class="btn btn-ghost min-h-11 h-auto py-2 text-xs"
          :aria-label="op.title"
          @mousedown.prevent
          @click="op.run(); mobilePanel = null"
        >{{ op.title }}</button>
      </div>
    </div>

    <div v-if="mobilePanel === 'order'" class="absolute bottom-full left-2 right-2 z-[61] mb-2 max-h-[55vh] overflow-y-auto rounded-xl bg-base-100 p-2 shadow-lg" data-testid="mobile-order-panel">
      <div class="flex items-center justify-between px-2">
        <span class="font-medium">{{ t('toolbar.reorder') }}</span>
        <button type="button" class="btn btn-ghost btn-square" :aria-label="t('toolbar.close')" data-testid="mobile-reorder-close" @mousedown.prevent @click="mobilePanel = null"><IconClose class="size-5" /></button>
      </div>
      <p class="px-2 pb-1 text-sm opacity-70">{{ t('toolbar.reorderHint') }}</p>
      <div v-for="(id, index) in mobileOrder" :key="id" class="flex min-h-11 items-center gap-2 px-2" :data-testid="`mobile-order-${id}`">
        <component :is="actionFor(id).icon" class="size-5 shrink-0" />
        <span class="min-w-0 flex-1 truncate">{{ actionFor(id).title }}</span>
        <button type="button" class="btn btn-ghost btn-square" :aria-label="`${actionFor(id).title} ${t('toolbar.moveUp')}`" :disabled="index === 0" :data-testid="`mobile-order-up-${id}`" @mousedown.prevent @click="moveMobileTool(index, -1)"><IconArrowUp class="size-5" /></button>
        <button type="button" class="btn btn-ghost btn-square" :aria-label="`${actionFor(id).title} ${t('toolbar.moveDown')}`" :disabled="index === mobileOrder.length - 1" :data-testid="`mobile-order-down-${id}`" @mousedown.prevent @click="moveMobileTool(index, 1)"><IconArrowDown class="size-5" /></button>
      </div>
    </div>

    <div v-if="mobileMode === 'main'" class="flex items-stretch px-1 py-1" data-testid="mobile-main-row">
      <template v-for="action in favoriteActions" :key="action.key">
        <PopupMenu v-if="action.key === 'heading'" v-model="headingMenuOpen" :items="headingItems" class="min-w-0 flex-1" @select="onHeadingSelect">
          <template #trigger>
            <button type="button" class="btn btn-ghost h-12 w-full flex-col gap-0 px-1 text-xs" :aria-label="action.title" @mousedown.prevent><component :is="action.icon" class="size-5" /><span class="max-w-full truncate">{{ action.title }}</span></button>
          </template>
        </PopupMenu>
        <button
          v-else
          type="button"
          class="btn btn-ghost h-12 min-w-0 flex-1 flex-col gap-0 px-1 text-xs"
          :class="action.active?.() ? 'btn-active text-primary' : ''"
          :aria-label="action.title"
          :disabled="action.disabled?.()"
          :data-testid="`mobile-favorite-${action.key}`"
          @mousedown.prevent
          @click="runMobileAction(action, $event)"
        ><component :is="action.icon" class="size-5" /><span class="max-w-full truncate">{{ action.shortTitle ?? action.title }}</span></button>
      </template>
      <button type="button" class="btn btn-ghost h-12 min-w-0 flex-1 flex-col gap-0 px-1 text-xs" :aria-label="t('toolbar.format')" data-testid="mobile-format-open" @mousedown.prevent @click="mobileMode = 'format'; mobilePanel = null"><IconType class="size-5" /><span>{{ t('toolbar.format') }}</span></button>
      <button type="button" class="btn btn-ghost h-12 min-w-0 flex-1 flex-col gap-0 px-1 text-xs" :aria-label="t('toolbar.insert')" :aria-expanded="mobilePanel === 'insert'" data-testid="mobile-insert-open" @mousedown.prevent @click="mobilePanel = mobilePanel === 'insert' ? null : 'insert'"><IconPlus class="size-5" /><span>{{ t('toolbar.insert') }}</span></button>
    </div>

    <div v-else class="flex items-stretch px-1 py-1" data-testid="mobile-format-row">
      <button type="button" class="btn btn-ghost h-12 shrink-0 flex-col gap-0 px-2 text-xs" :aria-label="t('toolbar.back')" data-testid="mobile-format-back" @mousedown.prevent @click="mobileMode = 'main'"><IconArrowLeft class="size-5" /><span>{{ t('toolbar.back') }}</span></button>
      <div class="flex min-w-0 flex-1">
        <div class="flex min-w-0 flex-1 overflow-x-auto">
        <PopupMenu v-model="headingMenuOpen" class="shrink-0" :items="headingItems" @select="onHeadingSelect">
          <template #trigger><button type="button" class="btn btn-ghost h-12 flex-col gap-0 whitespace-nowrap px-2 text-xs" :aria-label="t('toolbar.heading')" @mousedown.prevent><IconH1 class="size-5" /><span class="whitespace-nowrap">{{ t('toolbar.heading') }}</span></button></template>
        </PopupMenu>
        <button
          v-for="tool in tools"
          :key="tool.key"
          type="button"
          class="btn btn-ghost h-12 shrink-0 flex-col gap-0 whitespace-nowrap px-2 text-xs"
          :class="tool.active() ? 'btn-active text-primary' : ''"
          :aria-label="tool.title"
          :title="tool.title"
          @mousedown.prevent
          @click="tool.run()"
        ><component :is="tool.icon" v-if="tool.icon" class="size-5" /><span class="whitespace-nowrap">{{ tool.title }}</span></button>
        </div>
        <span class="pointer-events-none flex shrink-0 items-center bg-base-100" aria-hidden="true"><IconChevronRight class="size-4" /></span>
      </div>
    </div>

    <template v-if="tableOpen">
      <div class="fixed inset-0 z-[60]" @mousedown.prevent="tableOpen = false" />
      <TableGridPicker class="fixed z-[61]" :style="{ left: `${tablePos.left}px`, top: `${tablePos.top}px` }" @select="onPickTable" />
    </template>
  </div>
</template>

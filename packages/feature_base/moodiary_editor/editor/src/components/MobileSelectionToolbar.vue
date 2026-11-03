<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import type { Editor } from '@tiptap/core'
import { AllSelection, TextSelection } from '@tiptap/pm/state'
import { useI18n } from 'vue-i18n'
import IconBold from '~icons/lucide/bold'
import IconItalic from '~icons/lucide/italic'
import IconUnderline from '~icons/lucide/underline'
import IconStrike from '~icons/lucide/strikethrough'
import IconCode from '~icons/lucide/code'
import { selectionToolbarPosition } from './selection_toolbar_position'

const props = defineProps<{ editor: Editor; viewport: HTMLElement | null }>()
const { t } = useI18n()
const toolbar = ref<HTMLElement | null>(null)
const position = ref<{ left: number; top: number; width: number } | null>(null)
const tick = ref(0)
let frame = 0
let editorDom: HTMLElement | null = null

const actions = computed(() => [
  { key: 'bold', title: t('toolbar.bold'), icon: IconBold, run: () => props.editor.chain().focus().toggleBold().run() },
  { key: 'italic', title: t('toolbar.italic'), icon: IconItalic, run: () => props.editor.chain().focus().toggleItalic().run() },
  { key: 'underline', title: t('toolbar.underline'), icon: IconUnderline, run: () => props.editor.chain().focus().toggleUnderline().run() },
  { key: 'strike', title: t('toolbar.strike'), icon: IconStrike, run: () => props.editor.chain().focus().toggleStrike().run() },
  { key: 'code', title: t('toolbar.code'), icon: IconCode, run: () => props.editor.chain().focus().toggleCode().run() },
])

function active(key: string): boolean {
  void tick.value
  return props.editor.isActive(key)
}

function updatePosition(): void {
  const editor = props.editor
  const viewport = props.viewport
  if (editor.isDestroyed) {
    position.value = null
    return
  }
  const selection = editor.state.selection
  const toolbarFocused = toolbar.value?.contains(document.activeElement) ?? false
  if (!viewport || !editor.isEditable || (!editor.isFocused && !toolbarFocused) || editor.view.composing ||
      !(selection instanceof TextSelection || selection instanceof AllSelection) || selection.empty ||
      !editor.state.doc.textBetween(selection.from, selection.to, '\n', '').trim().length) {
    position.value = null
    return
  }
  // Browsers may clear the DOM selection when a keyboard user focuses a button.
  // Keep the last position until focus returns to the editor or leaves the toolbar.
  if (toolbarFocused && !editor.isFocused) return

  const domSelection = window.getSelection()
  if (!domSelection || domSelection.isCollapsed || domSelection.rangeCount === 0 ||
      !editor.view.dom.contains(domSelection.anchorNode) ||
      !editor.view.dom.contains(domSelection.focusNode)) {
    position.value = null
    return
  }

  const viewportRect = viewport.getBoundingClientRect()
  const visual = window.visualViewport
  const bounds = {
    left: Math.max(viewportRect.left, visual?.offsetLeft ?? 0),
    top: Math.max(viewportRect.top, visual?.offsetTop ?? 0),
    right: Math.min(viewportRect.right, visual ? visual.offsetLeft + visual.width : window.innerWidth),
    bottom: Math.min(viewportRect.bottom, visual ? visual.offsetTop + visual.height : window.innerHeight),
  }
  const rects = Array.from(domSelection.getRangeAt(0).getClientRects())
  const rect = rects.reverse().find((r) =>
    r.right > bounds.left && r.left < bounds.right && r.bottom > bounds.top && r.top < bounds.bottom,
  )
  if (!rect) {
    position.value = null
    return
  }
  // Five 44px targets, plus padding and border, shrinking only on very narrow screens.
  const width = Math.min(230, bounds.right - bounds.left - 16)
  const placed = selectionToolbarPosition(rect, bounds, width, 54)
  position.value = placed ? { ...placed, width } : null
}

function scheduleUpdate(): void {
  tick.value += 1
  cancelAnimationFrame(frame)
  frame = requestAnimationFrame(updatePosition)
}

function hideToolbar(): void {
  cancelAnimationFrame(frame)
  position.value = null
}

function onViewportChange(): void {
  if (!props.editor.isFocused && toolbar.value?.contains(document.activeElement)) {
    hideToolbar()
  } else {
    scheduleUpdate()
  }
}

watch(() => props.viewport, scheduleUpdate)
onMounted(() => {
  editorDom = props.editor.view.dom
  props.editor.on('transaction', scheduleUpdate)
  props.editor.on('focus', scheduleUpdate)
  props.editor.on('blur', scheduleUpdate)
  editorDom.addEventListener('compositionstart', hideToolbar)
  editorDom.addEventListener('compositionend', scheduleUpdate)
  document.addEventListener('selectionchange', scheduleUpdate)
  window.addEventListener('resize', onViewportChange)
  window.addEventListener('scroll', onViewportChange, true)
  window.visualViewport?.addEventListener('resize', onViewportChange)
  window.visualViewport?.addEventListener('scroll', onViewportChange)
  scheduleUpdate()
})
onBeforeUnmount(() => {
  props.editor.off('transaction', scheduleUpdate)
  props.editor.off('focus', scheduleUpdate)
  props.editor.off('blur', scheduleUpdate)
  editorDom?.removeEventListener('compositionstart', hideToolbar)
  editorDom?.removeEventListener('compositionend', scheduleUpdate)
  document.removeEventListener('selectionchange', scheduleUpdate)
  window.removeEventListener('resize', onViewportChange)
  window.removeEventListener('scroll', onViewportChange, true)
  window.visualViewport?.removeEventListener('resize', onViewportChange)
  window.visualViewport?.removeEventListener('scroll', onViewportChange)
  cancelAnimationFrame(frame)
})
</script>

<template>
  <Teleport to="body">
    <div
      v-if="position"
      ref="toolbar"
      class="selection-toolbar"
      role="toolbar"
      :aria-label="t('toolbar.format')"
      :style="{ left: `${position.left}px`, top: `${position.top}px`, width: `${position.width}px` }"
      data-testid="selection-toolbar"
      @focusout="scheduleUpdate"
    >
      <button
        v-for="action in actions"
        :key="action.key"
        type="button"
        class="selection-toolbar-button"
        :class="{ 'selection-toolbar-button--active': active(action.key) }"
        :aria-label="action.title"
        :aria-pressed="active(action.key)"
        :title="action.title"
        :data-testid="`selection-${action.key}`"
        @pointerdown.prevent
        @mousedown.prevent
        @click="action.run()"
      ><component :is="action.icon" class="size-5" /></button>
    </div>
  </Teleport>
</template>

<style scoped>
.selection-toolbar {
  position: fixed;
  z-index: 55;
  box-sizing: border-box;
  height: 54px;
  display: flex;
  align-items: center;
  padding: 4px;
  border: 1px solid var(--app-outline);
  border-radius: 16px;
  background: var(--app-hover);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.2), 0 2px 4px rgba(0, 0, 0, 0.14);
}
.selection-toolbar-button {
  display: flex;
  flex: 1 1 0;
  min-width: 0;
  height: 44px;
  align-items: center;
  justify-content: center;
  border: 0;
  border-radius: 12px;
  background: transparent;
  color: var(--app-on-surface);
  -webkit-tap-highlight-color: transparent;
}
.selection-toolbar-button--active {
  background: var(--app-secondary);
  color: var(--app-on-secondary);
}
.selection-toolbar-button:focus-visible {
  outline: 2px solid var(--app-primary);
  outline-offset: -2px;
}
</style>

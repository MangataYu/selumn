<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, useId, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { requestTagCandidates } from '../bridge/tag-candidates'
import IconHash from '~icons/lucide/hash'
import IconPlus from '~icons/lucide/plus'
import IconX from '~icons/lucide/x'

const props = defineProps<{ selected: string[] }>()
const emit = defineEmits<{ select: [tag: string]; close: [] }>()
const { t } = useI18n()
const id = useId()
const panel = ref<HTMLElement>()
const input = ref<HTMLInputElement>()
const query = ref('')
const candidates = ref<string[]>([])
const loading = ref(false)
const failed = ref(false)
const activeIndex = ref(-1)
let requestSequence = 0

// Match Dart TagPath.normalize: manual tags also allow spaces/punctuation.
const normalized = computed(() => {
  const parts = query.value.trim().replace(/^#/, '').split('/').map((part) => part.trim())
  return parts.some((part) => !part || /[\r\n\t]/.test(part)) ? null : parts.join('/')
})
const choices = computed(() => {
  const existing = [...new Set(candidates.value)].filter((tag) => !props.selected.includes(tag))
  const result = existing.map((tag) => ({ tag, create: false }))
  const tag = normalized.value
  if (tag && !props.selected.includes(tag) && !existing.includes(tag)) result.push({ tag, create: true })
  return result
})
const invalid = computed(() => query.value.trim().length > 0 && normalized.value === null)
const alreadySelected = computed(() => normalized.value !== null && props.selected.includes(normalized.value))

async function search(): Promise<void> {
  const current = ++requestSequence
  candidates.value = []
  activeIndex.value = -1
  loading.value = true
  failed.value = false
  const term = query.value.trim().replace(/^#/, '').split('/').map((part) => part.trim()).join('/')
  try {
    const result = await requestTagCandidates(term)
    if (current === requestSequence) candidates.value = result
  } catch {
    if (current === requestSequence) failed.value = true
  } finally {
    if (current === requestSequence) loading.value = false
  }
}

function select(tag: string): void {
  if (!props.selected.includes(tag)) emit('select', tag)
}

function onKeydown(event: KeyboardEvent): void {
  if (event.isComposing || event.keyCode === 229) return
  if (event.key === 'Escape') {
    event.preventDefault()
    event.stopPropagation()
    emit('close')
    return
  }
  if (event.target !== input.value) return
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault()
    const count = choices.value.length
    if (!count) return
    activeIndex.value = event.key === 'ArrowDown'
      ? (activeIndex.value + 1) % count
      : (activeIndex.value < 0 ? count - 1 : (activeIndex.value + count - 1) % count)
    void nextTick(() => document.getElementById(`${id}-${activeIndex.value}`)?.scrollIntoView?.({ block: 'nearest' }))
  } else if (event.key === 'Enter') {
    event.preventDefault()
    const tag = choices.value[activeIndex.value]?.tag ?? normalized.value
    if (tag) select(tag)
  }
}

function onOutsidePointer(event: PointerEvent): void {
  if (event.target instanceof Node && !panel.value?.contains(event.target)) emit('close')
}

watch(query, search)
watch(choices, () => { activeIndex.value = -1 })
onMounted(() => {
  input.value?.focus()
  void search()
  document.addEventListener('pointerdown', onOutsidePointer)
})
onBeforeUnmount(() => {
  requestSequence++
  document.removeEventListener('pointerdown', onOutsidePointer)
})
</script>

<template>
  <div ref="panel" class="meta-tag-picker" @keydown="onKeydown">
    <div class="tag-input-row">
      <IconHash class="tag-input-icon" aria-hidden="true" />
      <input
        ref="input"
        v-model="query"
        class="meta-tag-input"
        type="text"
        role="combobox"
        :aria-label="t('tags.placeholder')"
        :placeholder="t('tags.placeholder')"
        aria-autocomplete="list"
        aria-expanded="true"
        :aria-controls="id"
        :aria-activedescendant="activeIndex >= 0 ? `${id}-${activeIndex}` : undefined"
        :aria-invalid="invalid"
        autocomplete="off"
        enterkeyhint="done"
      />
      <button type="button" class="meta-tag-close" :aria-label="t('search.close')" @click="emit('close')">
        <IconX aria-hidden="true" />
      </button>
    </div>
    <div :id="id" class="tag-options" role="listbox" :aria-label="t('tags.existing')" :aria-busy="loading">
      <button
        v-for="(choice, index) in choices"
        :id="`${id}-${index}`"
        :key="choice.tag"
        type="button"
        :class="[choice.create ? 'meta-tag-create' : 'meta-tag-option', { active: index === activeIndex }]"
        role="option"
        :aria-selected="index === activeIndex"
        tabindex="-1"
        @mousedown.prevent
        @click="select(choice.tag)"
      >
        <IconPlus v-if="choice.create" aria-hidden="true" />
        <IconHash v-else aria-hidden="true" />
        <span>{{ choice.create ? t('tags.create', { tag: choice.tag }) : choice.tag }}</span>
      </button>
    </div>
    <div class="tag-status" aria-live="polite">
      <span v-if="invalid">{{ t('tags.invalid') }}</span>
      <span v-else-if="alreadySelected">{{ t('tags.selected') }}</span>
      <span v-else-if="loading">{{ t('tags.loading') }}</span>
      <span v-else-if="!failed && !choices.length">{{ t('tags.empty') }}</span>
      <template v-if="failed">
        <span>{{ t('tags.failed') }}</span>
        <button type="button" class="meta-tag-retry" @click="search">{{ t('tags.retry') }}</button>
      </template>
    </div>
  </div>
</template>

<style scoped>
.meta-tag-picker {
  width: 100%;
  max-width: 360px;
  min-width: 0;
  margin: 4px 0 8px;
  border: 1px solid var(--app-outline);
  border-radius: 12px;
  background: var(--app-surface);
  color: var(--app-on-surface);
  font-size: calc(13px * var(--app-font-scale, 1));
  overflow: hidden;
}
.tag-input-row { display: flex; align-items: center; padding: 2px 8px; gap: 6px; }
.tag-input-row:focus-within { box-shadow: inset 0 -2px var(--app-primary); }
.tag-input-icon { width: 16px; height: 16px; flex: none; color: var(--app-primary); }
.meta-tag-input { flex: 1; width: 0; min-width: 0; padding: 10px 0; border: none; outline: none; background: transparent; color: inherit; font: inherit; }
.meta-tag-input::placeholder { color: var(--app-on-surface-variant); }
button { font: inherit; border: none; background: transparent; cursor: pointer; color: inherit; }
button:focus-visible { outline: 2px solid var(--app-primary); outline-offset: -2px; }
.meta-tag-close { display: grid; place-items: center; width: 36px; height: 36px; flex: none; border-radius: 8px; color: var(--app-on-surface-variant); }
.meta-tag-close svg { width: 16px; height: 16px; }
.tag-options { max-height: 200px; overflow-y: auto; overscroll-behavior: contain; padding: 4px; }
.tag-options:empty { display: none; }
.meta-tag-option, .meta-tag-create { display: flex; align-items: center; gap: 8px; width: 100%; min-height: 40px; padding: 8px; border-radius: 8px; text-align: left; }
.tag-options button svg { width: 15px; height: 15px; flex: none; color: var(--app-on-surface-variant); }
.tag-options button span { overflow-wrap: anywhere; min-width: 0; }
.meta-tag-create, .tag-options .meta-tag-create svg { color: var(--app-primary); }
.tag-options button:hover, .tag-options button.active, .meta-tag-close:hover { background: var(--app-hover); }
.tag-status { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; padding: 0 12px 8px; color: var(--app-on-surface-variant); font-size: calc(12px * var(--app-font-scale, 1)); }
.tag-status:empty { display: none; }
.meta-tag-retry { color: var(--app-primary); padding: 4px; }
</style>

<script setup lang="ts">
import { computed } from 'vue'
import { tagChoices, tagSuggestion, selectTag } from '../editor/tag'

const choices = computed(tagChoices)
const style = computed(() => {
  const rect = tagSuggestion.rect
  if (!rect) return {}
  const below = window.innerHeight - rect.bottom > 180
  return {
    left: `${Math.max(8, Math.min(rect.left, window.innerWidth - 296))}px`,
    top: below ? `${rect.bottom + 4}px` : 'auto',
    bottom: below ? 'auto' : `${window.innerHeight - rect.top + 4}px`,
  }
})
</script>

<template>
  <div
    v-if="tagSuggestion.open && tagSuggestion.rect && (tagSuggestion.loading || choices.length)"
    class="tag-suggestions fixed z-[70] overflow-y-auto rounded-box border border-base-300 bg-base-100 p-1 shadow-lg"
    :style="style"
    role="listbox"
  >
    <span v-if="tagSuggestion.loading" class="loading loading-spinner loading-xs m-2" />
    <button
      v-for="(tag, index) in choices"
      :key="tag"
      type="button"
      role="option"
      :aria-selected="index === tagSuggestion.index"
      class="block w-full truncate rounded-field px-2 py-1.5 text-left text-sm"
      :class="index === tagSuggestion.index ? 'bg-primary text-primary-content' : 'hover:bg-base-200'"
      @mousedown.prevent="selectTag(tag)"
    >
      <span v-if="!tagSuggestion.items.includes(tag)">+ </span>#{{ tag }}
    </button>
  </div>
</template>

<style scoped>
.tag-suggestions { width: min(18rem, calc(100vw - 1rem)); max-height: min(18rem, 40vh); }
</style>

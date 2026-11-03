type RectEdges = Pick<DOMRect, 'left' | 'top' | 'right' | 'bottom'>

/** Place the toolbar near the visible selection, inside the editor viewport. */
export function selectionToolbarPosition(
  selection: RectEdges,
  bounds: RectEdges,
  menuWidth: number,
  menuHeight: number,
): { left: number; top: number } | null {
  const padding = 8
  const gap = 8
  const values = [
    selection.left, selection.top, selection.right, selection.bottom,
    bounds.left, bounds.top, bounds.right, bounds.bottom, menuWidth, menuHeight,
  ]
  if (values.some((value) => !Number.isFinite(value)) || menuWidth <= 0 || menuHeight <= 0) return null

  const minLeft = bounds.left + padding
  const maxLeft = bounds.right - padding - menuWidth
  const minTop = bounds.top + padding
  const maxTop = bounds.bottom - padding - menuHeight
  if (minLeft > maxLeft || minTop > maxTop) return null

  const visibleLeft = Math.max(selection.left, bounds.left)
  const visibleRight = Math.min(selection.right, bounds.right)
  const visibleTop = Math.max(selection.top, bounds.top)
  const visibleBottom = Math.min(selection.bottom, bounds.bottom)
  if (visibleLeft >= visibleRight || visibleTop >= visibleBottom) return null

  const left = Math.max(minLeft, Math.min((visibleLeft + visibleRight - menuWidth) / 2, maxLeft))
  const below = visibleBottom + gap
  const above = visibleTop - gap - menuHeight
  const preferredTop = below <= maxTop ? below : above >= minTop ? above : below
  const top = Math.max(minTop, Math.min(preferredTop, maxTop))
  return { left, top }
}

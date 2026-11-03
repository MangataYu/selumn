import { describe, expect, it } from 'vitest'
import { selectionToolbarPosition } from './selection_toolbar_position'

describe('selectionToolbarPosition', () => {
  const bounds = { left: 0, top: 0, right: 320, bottom: 500 }

  it('places the toolbar below and centered on a visible selection', () => {
    const selection = { left: 120, top: 100, right: 200, bottom: 120 }
    expect(selectionToolbarPosition(selection, bounds, 160, 44)).toEqual({ left: 80, top: 128 })
  })

  it('uses the space above when the bottom is occupied by the keyboard or toolbar', () => {
    const selection = { left: 120, top: 440, right: 200, bottom: 460 }
    expect(selectionToolbarPosition(selection, bounds, 160, 44)).toEqual({ left: 80, top: 388 })
  })

  it('keeps the toolbar within the viewport at both horizontal edges', () => {
    const left = { left: 0, top: 50, right: 15, bottom: 70 }
    const right = { left: 305, top: 50, right: 320, bottom: 70 }
    expect(selectionToolbarPosition(left, bounds, 160, 44)?.left).toBe(8)
    expect(selectionToolbarPosition(right, bounds, 160, 44)?.left).toBe(152)
  })

  it('anchors partially clipped text to the visible part of the selection', () => {
    const selection = { left: -50, top: -20, right: 30, bottom: 20 }
    expect(selectionToolbarPosition(selection, bounds, 100, 44)).toEqual({ left: 8, top: 28 })
  })

  it('clamps the toolbar to the viewport when neither side has enough space', () => {
    const selection = { left: 50, top: 20, right: 270, bottom: 95 }
    const shortBounds = { left: 0, top: 0, right: 320, bottom: 120 }
    expect(selectionToolbarPosition(selection, shortBounds, 160, 44)).toEqual({ left: 80, top: 68 })
  })

  it('respects a viewport offset within the page', () => {
    const offsetBounds = { left: 10, top: 100, right: 310, bottom: 400 }
    const selection = { left: 20, top: 115, right: 100, bottom: 135 }
    expect(selectionToolbarPosition(selection, offsetBounds, 160, 44)).toEqual({ left: 18, top: 143 })
  })

  it('hides the toolbar when the selection is not visible', () => {
    expect(selectionToolbarPosition({ left: 20, top: 510, right: 100, bottom: 530 }, bounds, 160, 44)).toBeNull()
    expect(selectionToolbarPosition({ left: 20, top: 100, right: 20, bottom: 120 }, bounds, 160, 44)).toBeNull()
  })

  it('hides the toolbar when it cannot fit safely or geometry is invalid', () => {
    const selection = { left: 20, top: 20, right: 100, bottom: 40 }
    expect(selectionToolbarPosition(selection, bounds, 305, 44)).toBeNull()
    expect(selectionToolbarPosition(selection, bounds, 100, 485)).toBeNull()
    expect(selectionToolbarPosition(selection, bounds, 0, 44)).toBeNull()
    expect(selectionToolbarPosition({ ...selection, left: NaN }, bounds, 100, 44)).toBeNull()
  })
})

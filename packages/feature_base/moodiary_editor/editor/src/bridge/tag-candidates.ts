import { post } from './post'

// The metadata picker shares the host's tag search with inline # suggestions,
// but owns its requests so responses cannot update the other UI.
const pending = new Map<string, (json: string) => void>()
let sequence = 0

export function requestTagCandidates(query: string): Promise<string[]> {
  return new Promise((resolve, reject) => {
    const reqId = `meta-tag-${++sequence}`
    const timer = window.setTimeout(() => {
      pending.delete(reqId)
      reject(new Error('Tag candidates timed out'))
    }, 4000)
    pending.set(reqId, (json) => {
      window.clearTimeout(timer)
      try {
        const values: unknown = JSON.parse(json)
        if (!Array.isArray(values) || !values.every((value) => typeof value === 'string')) {
          throw new Error('Invalid tag candidates response')
        }
        resolve(values)
      } catch {
        reject(new Error('Tag candidates unavailable'))
      }
    })
    post('requestTagCandidates', { reqId, query })
  })
}

export function resolveTagCandidateRequest(reqId: string, json: string): boolean {
  const resolve = pending.get(reqId)
  if (!resolve) return false
  pending.delete(reqId)
  resolve(json)
  return true
}

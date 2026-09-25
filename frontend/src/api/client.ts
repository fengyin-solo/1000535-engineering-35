/** 统一请求封装：拼后端地址、抛网络错误、给页脚留一句可读的说明。 */
const API_BASE = import.meta.env.VITE_API_BASE ?? ''

export function request(path: string, init?: RequestInit): Promise<Response> {
  const url = path.startsWith('http') ? path : `${API_BASE}${path}`
  return fetch(url, {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  }).catch((error: unknown) => {
    const detail = error instanceof Error ? error.message : '请求未送达'
    throw new Error(`接口请求失败：${detail}`)
  })
}

export async function fetchJson<T>(path: string): Promise<T> {
  const response = await request(path)
  if (!response.ok) {
    throw new Error(`接口返回 ${response.status}，数据未更新`)
  }
  return (await response.json()) as T
}

export type StatItem = { label: string; value: number }

/** 读取模块页头统计卡片；失败时抛错，由页面决定保留旧值还是提示。 */
export async function fetchStats(endpoint: string): Promise<StatItem[]> {
  const response = await request(`${endpoint}/stats`)
  if (!response.ok) {
    throw new Error(`统计接口返回 ${response.status}`)
  }
  const payload = (await response.json()) as { items?: StatItem[] }
  return payload.items ?? []
}

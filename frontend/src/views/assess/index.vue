<template>
  <section class="page" data-module="assess">
    <header class="page-head">
      <div>
        <h2>状态评估管理</h2>
        <p class="page-desc">维护评估记录，围绕评估编号、评估对象、评估周期、健康分值做登记、筛选与状态流转。</p>
      </div>
      <div class="page-actions">
        <button class="btn primary" type="button" @click="openCreate">登记评估记录</button>
        <button class="btn" type="button" @click="exportRows">导出状态评估清单</button>
      </div>
    </header>

    <div class="stat-row">
      <article v-for="item in stats" :key="item.label" class="stat-card">
        <span class="stat-label">{{ item.label }}</span>
        <strong class="stat-value">{{ item.value }}</strong>
      </article>
    </div>

    <form class="filter-bar" @submit.prevent="reload">
      <label v-for="field in filterFields" :key="field" class="filter-item">
        <span>{{ field }}</span>
        <input v-model="filters[field]" :placeholder="`按${field}检索`" />
      </label>
      <button class="btn" type="submit">查询</button>
      <button class="btn ghost" type="button" @click="resetFilters">重置条件</button>
    </form>

    <table class="data-table">
      <thead>
        <tr>
          <th v-for="column in columns" :key="column">{{ column }}</th>
          <th>可执行动作</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="row in rows" :key="String(row.id)">
          <td v-for="column in columns" :key="column">{{ row[column] ?? '—' }}</td>
          <td class="row-actions">
            <button
              v-for="action in actions"
              :key="action"
              class="link"
              type="button"
              @click="runAction(action, row)"
            >
              {{ action }}
            </button>
          </td>
        </tr>
        <tr v-if="!rows.length">
          <td :colspan="columns.length + 1" class="empty-state">暂无状态评估数据，可先登记评估记录</td>
        </tr>
      </tbody>
    </table>

    <footer class="page-foot">
      <span>共 {{ total }} 条状态评估记录</span>
      <span v-if="errorMessage" class="error-text">{{ errorMessage }}</span>
    </footer>
  </section>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'

import { fetchStats, request, type StatItem } from '@/api/client'

type Row = Record<string, string | number | null>

const ENDPOINT = '/api/assess'
const columns = ["评估编号", "评估对象", "评估周期", "健康分值", "风险等级", "评估人员", "评估结论", "评估状态"]
const actions = ["开始评估", "确认定级", "发起复评"]
const statuses = ["待评估", "评估中", "已定级", "已复评"]
const stats = ref<StatItem[]>([{"label": "待评估对象", "value": 0}, {"label": "高风险设备", "value": 0}, {"label": "健康分值均值", "value": 0}])

const rows = ref<Row[]>([])
const total = ref(0)
const errorMessage = ref('')
const filters = ref<Record<string, string>>({})
const filterFields = columns.slice(0, 3)

function resetFilters() {
  filters.value = {}
  void reload()
}

function exportRows() {
  window.open(`${ENDPOINT}/export`, '_blank')
}

function openCreate() {
  errorMessage.value = '评估记录登记入口尚未接入审批流'
}

async function runAction(action: string, row: Row) {
  errorMessage.value = ''
  try {
    const response = await request(`${ENDPOINT}/${row.id}/actions`, {
      method: 'POST',
      body: JSON.stringify({ action }),
    })
    if (!response.ok) {
      throw new Error('状态评估动作未生效，请稍后重试')
    }
    await reload()
    await refreshStats()
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : '状态评估操作失败'
  }
}

async function reload() {
  errorMessage.value = ''
  const query = new URLSearchParams(filters.value as Record<string, string>).toString()
  try {
    const response = await request(`${ENDPOINT}?${query}`)
    if (!response.ok) {
      throw new Error('评估记录列表读取失败')
    }
    const payload = await response.json()
    rows.value = payload.items ?? []
    total.value = payload.total ?? rows.value.length
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : '状态评估列表读取失败'
  }
}

async function refreshStats() {
  try {
    stats.value = await fetchStats(ENDPOINT)
  } catch {
    // 统计卡片读取失败时保留旧值，不打断列表展示
  }
}

onMounted(() => {
  void reload()
  void refreshStats()
})
</script>

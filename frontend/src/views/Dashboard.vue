<template>
  <section class="page">
    <header class="page-head">
      <div>
        <h2>运营概览</h2>
        <p class="page-desc">汇总各业务模块的关键指标，先看总量再看异常。</p>
      </div>
    </header>

    <div v-if="errorMessage" class="page-foot">
      <span class="error-text">{{ errorMessage }}</span>
      <button class="btn" type="button" @click="reload">重试</button>
    </div>

    <template v-else>
      <div class="stat-row">
        <article v-for="card in cards" :key="card.label" class="stat-card">
          <span class="stat-label">{{ card.label }}</span>
          <strong class="stat-value">{{ card.value }}</strong>
        </article>
      </div>
      <table class="data-table">
        <thead>
          <tr><th>业务模块</th><th>今日新增</th><th>待处理</th><th>异常量</th></tr>
        </thead>
        <tbody>
          <tr v-for="row in moduleRows" :key="row.name">
            <td>{{ row.name }}</td>
            <td>{{ row.created }}</td>
            <td>{{ row.pending }}</td>
            <td>{{ row.abnormal }}</td>
          </tr>
        </tbody>
      </table>
      <footer class="page-foot">
        <span>共 {{ moduleRows.length }} 个业务模块，数字与各模块列表实时同源</span>
      </footer>
    </template>
  </section>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'

import { fetchJson } from '@/api/client'

type Overview = {
  cards: { label: string; value: number }[]
  modules: { name: string; created: number; pending: number; abnormal: number }[]
}

const cards = ref<Overview['cards']>([])
const moduleRows = ref<Overview['modules']>([])
const errorMessage = ref('')

async function reload() {
  errorMessage.value = ''
  try {
    const payload = await fetchJson<Overview>('/api/overview')
    cards.value = payload.cards
    moduleRows.value = payload.modules
  } catch (error) {
    // 不再静默回退成全零：全零会让人误以为业务数据就是空的
    cards.value = []
    moduleRows.value = []
    errorMessage.value = error instanceof Error
      ? `概览数据加载失败：${error.message}。请确认后端已启动（make dev），然后点重试。`
      : '概览数据加载失败，请确认后端已启动后重试。'
  }
}

onMounted(reload)
</script>

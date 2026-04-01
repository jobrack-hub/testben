<script lang="ts">
  import { onMount } from 'svelte';
  import { api, type Todo } from '$lib/api';

  let todos = $state<Todo[]>([]);
  let newTitle = $state('');
  let loading = $state(true);
  let error = $state<string | null>(null);
  let filter = $state<'all' | 'active' | 'done'>('all');
  let editingId = $state<string | null>(null);
  let editingTitle = $state('');

  const remaining = $derived(todos.filter(t => !t.isComplete).length);
  const done = $derived(todos.filter(t => t.isComplete).length);
  const filtered = $derived(
    filter === 'active' ? todos.filter(t => !t.isComplete)
    : filter === 'done'  ? todos.filter(t => t.isComplete)
    : todos
  );

  onMount(async () => {
    try {
      todos = await api.list();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load todos';
    } finally {
      loading = false;
    }
  });

  async function addTodo() {
    const title = newTitle.trim();
    if (!title) return;
    try {
      todos = [...todos, await api.create(title)];
      newTitle = '';
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to create todo';
    }
  }

  async function toggleTodo(todo: Todo) {
    try {
      const updated = await api.toggle(todo);
      todos = todos.map(t => (t.id === updated.id ? updated : t));
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to update todo';
    }
  }

  async function deleteTodo(id: string) {
    try {
      await api.delete(id);
      todos = todos.filter(t => t.id !== id);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to delete todo';
    }
  }

  function startEdit(todo: Todo) {
    editingId = todo.id;
    editingTitle = todo.title;
  }

  async function commitEdit(todo: Todo) {
    const title = editingTitle.trim();
    editingId = null;
    if (!title || title === todo.title) return;
    try {
      const updated = await api.update(todo.id, { title, isComplete: todo.isComplete });
      todos = todos.map(t => (t.id === updated.id ? updated : t));
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to update todo';
    }
  }

  function cancelEdit() {
    editingId = null;
    editingTitle = '';
  }
</script>

<svelte:head>
  <title>My Tasks</title>
</svelte:head>

<header>
  <div class="header-inner">
    <div class="brand">
      <span class="brand-dot"></span>
      <span class="brand-name">TaskFlow</span>
    </div>
    {#if !loading && todos.length > 0}
      <div class="header-filters">
        <button
          class="hf-btn"
          class:active={filter === 'active'}
          onclick={() => filter = filter === 'active' ? 'all' : 'active'}
        >
          <strong>{remaining}</strong> left
        </button>
        <span class="stat-divider"></span>
        <button
          class="hf-btn"
          class:active={filter === 'done'}
          onclick={() => filter = filter === 'done' ? 'all' : 'done'}
        >
          <strong>{done}</strong> done
        </button>
      </div>
    {/if}
  </div>
</header>

<main>
  <div class="card">
    <div class="card-top">
      <div>
        <h1>My Tasks</h1>
        <p class="subtitle">Stay on top of what matters.</p>
      </div>

      <!-- Filter tabs -->
      {#if !loading && todos.length > 0}
        <div class="tabs">
          <button class="tab" class:active={filter === 'all'}    onclick={() => filter = 'all'}>All</button>
          <button class="tab" class:active={filter === 'active'} onclick={() => filter = 'active'}>Active</button>
          <button class="tab" class:active={filter === 'done'}   onclick={() => filter = 'done'}>Done</button>
        </div>
      {/if}
    </div>

    {#if error}
      <div class="error" role="alert">
        <span>⚠ {error}</span>
        <button onclick={() => (error = null)}>✕</button>
      </div>
    {/if}

    <div class="add-form">
      <input
        type="text"
        bind:value={newTitle}
        onkeydown={e => e.key === 'Enter' && addTodo()}
        placeholder="Add a new task…"
        aria-label="New task"
      />
      <button class="btn-add" onclick={addTodo} disabled={!newTitle.trim()}>+ Add</button>
    </div>

    {#if loading}
      <div class="loading-state">
        <div class="spinner"></div>
        <span>Loading tasks…</span>
      </div>
    {:else if filtered.length === 0}
      <div class="empty-state">
        <div class="empty-icon">{filter === 'done' ? '✓' : filter === 'active' ? '◎' : '✓'}</div>
        <p>
          {filter === 'done'   ? 'Nothing completed yet.'
           : filter === 'active' ? 'Nothing left to do!'
           : 'Add a task above to get started.'}
        </p>
      </div>
    {:else}
      <ul class="todo-list">
        {#each filtered as todo (todo.id)}
          <li class:complete={todo.isComplete}>
            <!-- Checkbox -->
            <button
              class="check-btn"
              class:checked={todo.isComplete}
              onclick={() => toggleTodo(todo)}
              aria-label="Toggle {todo.title}"
            >
              {#if todo.isComplete}
                <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                  <path d="M2 6l3 3 5-5" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
              {/if}
            </button>

            <!-- Title or edit input -->
            {#if editingId === todo.id}
              <input
                class="edit-input"
                bind:value={editingTitle}
                onkeydown={e => {
                  if (e.key === 'Enter') commitEdit(todo);
                  if (e.key === 'Escape') cancelEdit();
                }}
                onblur={() => commitEdit(todo)}
                autofocus
              />
            {:else}
              <span class="title" ondblclick={() => startEdit(todo)}>{todo.title}</span>
            {/if}

            <!-- Edit button -->
            {#if editingId !== todo.id}
              <button class="icon-btn edit-btn" onclick={() => startEdit(todo)} aria-label="Edit {todo.title}">
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                  <path d="M9.5 2.5l2 2L4 12H2v-2L9.5 2.5z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
              </button>
            {/if}

            <!-- Delete button -->
            <button class="icon-btn delete-btn" onclick={() => deleteTodo(todo.id)} aria-label="Delete {todo.title}">
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <path d="M1 1l12 12M13 1L1 13" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
              </svg>
            </button>
          </li>
        {/each}
      </ul>

      {#if done > 0 && filter !== 'active'}
        <div class="progress-bar-wrap">
          <div class="progress-bar" style="width: {Math.round((done / todos.length) * 100)}%"></div>
        </div>
        <p class="progress-label">{Math.round((done / todos.length) * 100)}% complete</p>
      {/if}
    {/if}
  </div>
</main>

<style>
  header {
    background: #131426;
    border-bottom: 1px solid rgba(255,183,27,0.15);
    padding: 0 2rem;
  }

  .header-inner {
    max-width: 640px;
    margin: 0 auto;
    height: 64px;
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-family: 'Montserrat', sans-serif;
    font-weight: 800;
    font-size: 1.1rem;
    color: #fff;
    letter-spacing: -0.3px;
  }

  .brand-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: #FFB71B;
    box-shadow: 0 0 8px rgba(255,183,27,0.6);
  }

  /* Header filter buttons */
  .header-filters {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .hf-btn {
    background: none;
    border: none;
    cursor: pointer;
    font-family: 'Mulish', sans-serif;
    font-size: 0.85rem;
    color: rgba(255,255,255,0.5);
    padding: 0.25rem 0.5rem;
    border-radius: 6px;
    transition: color 0.15s, background 0.15s;
  }

  .hf-btn strong { color: rgba(255,255,255,0.5); transition: color 0.15s; }

  .hf-btn:hover,
  .hf-btn.active {
    color: #FFB71B;
    background: rgba(255,183,27,0.1);
  }

  .hf-btn:hover strong,
  .hf-btn.active strong { color: #FFB71B; }

  .stat-divider {
    width: 1px;
    height: 14px;
    background: rgba(255,255,255,0.2);
  }

  main {
    background: #131426;
    min-height: calc(100vh - 64px);
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 3rem 1.5rem 4rem;
  }

  .card {
    width: 100%;
    max-width: 560px;
    background: #fff;
    border-radius: 20px;
    padding: 2.5rem 2.5rem 2rem;
    box-shadow: 0 24px 60px rgba(0,0,0,0.35);
  }

  .card-top {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    margin-bottom: 2rem;
    gap: 1rem;
  }

  h1 {
    font-family: 'Montserrat', sans-serif;
    font-weight: 800;
    font-size: 1.9rem;
    color: #131426;
    letter-spacing: -0.5px;
    margin-bottom: 0.25rem;
  }

  .subtitle {
    font-size: 0.9rem;
    color: #6A6B6C;
    font-family: 'Mulish', sans-serif;
  }

  /* Filter tabs */
  .tabs {
    display: flex;
    gap: 0.25rem;
    background: #F0F6FB;
    border-radius: 10px;
    padding: 0.25rem;
    flex-shrink: 0;
  }

  .tab {
    padding: 0.375rem 0.875rem;
    border: none;
    background: transparent;
    border-radius: 7px;
    font-family: 'Mulish', sans-serif;
    font-size: 0.85rem;
    font-weight: 600;
    color: #6A6B6C;
    cursor: pointer;
    transition: background 0.15s, color 0.15s;
    white-space: nowrap;
  }

  .tab:hover { color: #131426; }

  .tab.active {
    background: #fff;
    color: #131426;
    box-shadow: 0 1px 4px rgba(0,0,0,0.1);
  }

  /* Error */
  .error {
    background: #fff5f5;
    border: 1px solid #fca5a5;
    border-radius: 10px;
    padding: 0.75rem 1rem;
    margin-bottom: 1.25rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 0.85rem;
    color: #dc2626;
    font-family: 'Mulish', sans-serif;
  }

  .error button {
    background: none;
    border: none;
    cursor: pointer;
    color: inherit;
    opacity: 0.7;
  }

  /* Add form */
  .add-form {
    display: flex;
    gap: 0.625rem;
    margin-bottom: 1.75rem;
  }

  .add-form input {
    flex: 1;
    padding: 0.75rem 1.1rem;
    border: 2px solid #ededed;
    border-radius: 100px;
    font-size: 0.95rem;
    font-family: 'Mulish', sans-serif;
    color: #131426;
    outline: none;
    background: #F0F6FB;
    transition: border-color 0.2s, background 0.2s;
  }

  .add-form input::placeholder { color: #aaa; }
  .add-form input:focus { border-color: #FFB71B; background: #fff; }

  .btn-add {
    padding: 0.75rem 1.5rem;
    background: #FFB71B;
    color: #131426;
    border: 2px solid #FFB71B;
    border-radius: 100px;
    font-size: 0.9rem;
    font-weight: 700;
    font-family: 'Montserrat', sans-serif;
    letter-spacing: 0.5px;
    cursor: pointer;
    transition: background 0.2s, transform 0.1s;
    white-space: nowrap;
  }

  .btn-add:hover:not(:disabled) { background: #e8a400; border-color: #e8a400; transform: translateY(-1px); }
  .btn-add:active:not(:disabled) { transform: translateY(0); }
  .btn-add:disabled { opacity: 0.4; cursor: not-allowed; }

  /* States */
  .loading-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.75rem;
    padding: 2.5rem 0;
    color: #6A6B6C;
    font-size: 0.9rem;
    font-family: 'Mulish', sans-serif;
  }

  .spinner {
    width: 28px;
    height: 28px;
    border: 3px solid #ededed;
    border-top-color: #FFB71B;
    border-radius: 50%;
    animation: spin 0.7s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.75rem;
    padding: 2.5rem 0;
    color: #6A6B6C;
    font-family: 'Mulish', sans-serif;
    font-size: 0.9rem;
    text-align: center;
  }

  .empty-icon {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: #F0F6FB;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.4rem;
    color: #FFB71B;
    font-weight: 700;
  }

  /* Todo list */
  .todo-list {
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    margin-bottom: 1.5rem;
  }

  .todo-list li {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.75rem 0.875rem;
    border-radius: 12px;
    border: 1px solid #ededed;
    background: #fff;
    transition: border-color 0.15s, box-shadow 0.15s, opacity 0.2s;
  }

  .todo-list li:hover {
    border-color: rgba(255,183,27,0.4);
    box-shadow: 0 2px 12px rgba(255,183,27,0.08);
  }

  .todo-list li:hover .edit-btn { opacity: 1; }

  .todo-list li.complete { background: #F0F6FB; border-color: transparent; opacity: 0.7; }

  .check-btn {
    width: 22px;
    height: 22px;
    border-radius: 6px;
    border: 2px solid #ddd;
    background: transparent;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    transition: border-color 0.15s, background 0.15s;
    padding: 0;
  }

  .check-btn:hover { border-color: #FFB71B; }
  .check-btn.checked { background: #FFB71B; border-color: #FFB71B; }

  .title {
    flex: 1;
    font-size: 0.95rem;
    font-family: 'Mulish', sans-serif;
    font-weight: 500;
    color: #131426;
    cursor: default;
  }

  li.complete .title { text-decoration: line-through; color: #aaa; }

  /* Inline edit input */
  .edit-input {
    flex: 1;
    border: none;
    border-bottom: 2px solid #FFB71B;
    outline: none;
    font-size: 0.95rem;
    font-family: 'Mulish', sans-serif;
    font-weight: 500;
    color: #131426;
    background: transparent;
    padding: 0 0 2px;
  }

  /* Icon buttons */
  .icon-btn {
    background: none;
    border: none;
    cursor: pointer;
    padding: 4px;
    border-radius: 6px;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: color 0.15s, background 0.15s;
    line-height: 1;
    flex-shrink: 0;
  }

  .edit-btn {
    color: #ccc;
    opacity: 0;
    transition: color 0.15s, opacity 0.15s;
  }

  .edit-btn:hover { color: #FFB71B; background: rgba(255,183,27,0.1); opacity: 1; }

  .delete-btn { color: #ccc; }
  .delete-btn:hover { color: #ef4444; background: #fff5f5; }

  /* Progress */
  .progress-bar-wrap {
    height: 4px;
    background: #ededed;
    border-radius: 100px;
    overflow: hidden;
    margin-bottom: 0.5rem;
  }

  .progress-bar {
    height: 100%;
    background: linear-gradient(90deg, #FFB71B, #e8a400);
    border-radius: 100px;
    transition: width 0.4s ease;
  }

  .progress-label {
    font-size: 0.78rem;
    color: #aaa;
    text-align: right;
    font-family: 'Mulish', sans-serif;
  }
</style>

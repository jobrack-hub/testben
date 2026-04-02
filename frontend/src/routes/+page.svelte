<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { api, type Todo, type Subtask, type Status, type Priority, type TaskInput } from '$lib/api';

  // ── Core data ─────────────────────────────────────────────────────────────
  let todos   = $state<Todo[]>([]);
  let loading = $state(true);
  let error   = $state<string | null>(null);

  // ── View ──────────────────────────────────────────────────────────────────
  let view = $state<'board' | 'list'>('board');

  // ── Modal (new task) ──────────────────────────────────────────────────────
  let showModal     = $state(false);
  let modalTitle       = $state('');
  let modalStatus      = $state<Status>('todo');
  let modalPriority    = $state<Priority>('none');
  let modalDueDate     = $state('');
  let modalDescription = $state('');
  let modalSaving      = $state(false);

  // ── Inline edit (list view) ───────────────────────────────────────────────
  let editingId    = $state<string | null>(null);
  let editingTitle = $state('');

  // ── Timer ─────────────────────────────────────────────────────────────────
  let activeTimerId = $state<string | null>(null);
  let sessionStart  = $state(0);
  let tick          = $state(0);
  let timerInterval: ReturnType<typeof setInterval> | null = null;

  // ── Drag & drop ───────────────────────────────────────────────────────────
  let draggingId  = $state<string | null>(null);
  let dragOverCol = $state<Status | null>(null);

  // ── Search & filter ───────────────────────────────────────────────────────
  let searchQuery    = $state('');
  let filterStatus   = $state<Status | 'all'>('all');
  let filterPriority = $state<Priority | 'all'>('all');
  let filterOverdue  = $state(false);

  // ── Subtasks ──────────────────────────────────────────────────────────────
  let expandedId     = $state<string | null>(null);
  let subtaskMap     = $state<Record<string, Subtask[]>>({});
  let subtaskLoading = $state<Record<string, boolean>>({});
  let subtaskDraft   = $state<Record<string, string>>({});

  // ── Derived ───────────────────────────────────────────────────────────────
  const filteredTodos = $derived.by(() => {
    let r = todos;
    const q = searchQuery.trim().toLowerCase();
    if (q) r = r.filter(t => t.title.toLowerCase().includes(q) || (t.description ?? '').toLowerCase().includes(q));
    if (filterStatus !== 'all') r = r.filter(t => t.status === filterStatus);
    if (filterPriority !== 'all') r = r.filter(t => t.priority === filterPriority);
    if (filterOverdue) {
      const today = new Date().toISOString().slice(0, 10);
      r = r.filter(t => !!t.dueDate && t.dueDate < today);
    }
    return r;
  });

  const colTodo     = $derived(filteredTodos.filter(t => t.status === 'todo'));
  const colProgress = $derived(filteredTodos.filter(t => t.status === 'in_progress'));
  const colDone     = $derived(filteredTodos.filter(t => t.status === 'done'));

  const totalCount  = $derived(todos.length);
  const activeCount = $derived(todos.filter(t => t.status !== 'done').length);
  const doneCount   = $derived(todos.filter(t => t.status === 'done').length);

  const totalTracked = $derived.by(() => {
    void tick;
    return todos.reduce((sum, t) => {
      const live = activeTimerId === t.id
        ? Math.floor((Date.now() - sessionStart) / 1000) : 0;
      return sum + t.timeSpent + live;
    }, 0);
  });

  const navTimerLabel = $derived.by(() => {
    void tick;
    if (!activeTimerId) return null;
    const t = todos.find(t => t.id === activeTimerId);
    if (!t) return null;
    const secs = t.timeSpent + Math.floor((Date.now() - sessionStart) / 1000);
    return `${fmt(secs)}  ${t.title}`;
  });

  // ── Timer helpers ─────────────────────────────────────────────────────────
  function startInterval() {
    timerInterval = setInterval(() => tick++, 1000);
  }

  function clearTimerLoop() {
    if (timerInterval) { clearInterval(timerInterval); timerInterval = null; }
  }

  async function stopActiveTimer() {
    if (!activeTimerId) return;
    const elapsed = Math.floor((Date.now() - sessionStart) / 1000);
    const id = activeTimerId;
    clearTimerLoop();
    activeTimerId = null;
    sessionStart  = 0;
    if (elapsed > 0) {
      const todo = todos.find(t => t.id === id);
      if (todo) {
        try {
          const updated = await api.update(id, {
            title: todo.title, status: todo.status,
            priority: todo.priority, timeSpent: todo.timeSpent + elapsed,
          });
          todos = todos.map(t => t.id === updated.id ? updated : t);
        } catch { error = 'Failed to save time'; }
      }
    }
  }

  async function toggleTimer(todo: Todo) {
    if (activeTimerId === todo.id) {
      await stopActiveTimer();
    } else {
      await stopActiveTimer();
      activeTimerId = todo.id;
      sessionStart  = Date.now();
      startInterval();
    }
  }

  function liveSeconds(todo: Todo): number {
    void tick;
    return activeTimerId === todo.id
      ? todo.timeSpent + Math.floor((Date.now() - sessionStart) / 1000)
      : todo.timeSpent;
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────
  function openModal() {
    modalTitle = ''; modalStatus = 'todo';
    modalPriority = 'none'; modalDueDate = '';
    modalDescription = '';
    showModal = true;
  }

  async function createTask() {
    const title = modalTitle.trim();
    if (!title || modalSaving) return;
    modalSaving = true;
    try {
      const task = await api.create({
        title,
        status:      modalStatus,
        priority:    modalPriority,
        dueDate:     modalDueDate || null,
        description: modalDescription.trim() || null,
      });
      todos = [...todos, task];
      showModal = false;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to create task';
    } finally {
      modalSaving = false;
    }
  }

  async function deleteTask(id: string) {
    if (activeTimerId === id) { clearTimerLoop(); activeTimerId = null; }
    try {
      await api.delete(id);
      todos = todos.filter(t => t.id !== id);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to delete task';
    }
  }

  async function updateTaskField(todo: Todo, patch: TaskInput) {
    try {
      const updated = await api.update(todo.id, {
        title: todo.title, status: todo.status,
        priority: todo.priority, timeSpent: todo.timeSpent,
        dueDate: todo.dueDate, description: todo.description, ...patch,
      });
      todos = todos.map(t => t.id === updated.id ? updated : t);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to update task';
    }
  }

  async function moveToStatus(id: string, status: Status) {
    const todo = todos.find(t => t.id === id);
    if (!todo || todo.status === status) return;
    if (activeTimerId === id) await stopActiveTimer();
    await updateTaskField(todo, { status });
  }

  function startEdit(todo: Todo) {
    editingId = todo.id; editingTitle = todo.title;
  }

  async function commitEdit(todo: Todo) {
    const title = editingTitle.trim();
    editingId = null;
    if (!title || title === todo.title) return;
    await updateTaskField(todo, { title });
  }

  function cancelEdit() { editingId = null; }

  // ── Subtask actions ───────────────────────────────────────────────────────
  async function toggleExpand(todo: Todo) {
    if (expandedId === todo.id) { expandedId = null; return; }
    expandedId = todo.id;
    if (!subtaskMap[todo.id]) {
      subtaskLoading = { ...subtaskLoading, [todo.id]: true };
      try {
        const subs = await api.subtasks.list(todo.id);
        subtaskMap = { ...subtaskMap, [todo.id]: subs };
      } catch { error = 'Failed to load subtasks'; }
      finally { subtaskLoading = { ...subtaskLoading, [todo.id]: false }; }
    }
  }

  async function addSubtask(todoId: string) {
    const title = (subtaskDraft[todoId] ?? '').trim();
    if (!title) return;
    try {
      const sub = await api.subtasks.create(todoId, title);
      subtaskMap = { ...subtaskMap, [todoId]: [...(subtaskMap[todoId] ?? []), sub] };
      subtaskDraft = { ...subtaskDraft, [todoId]: '' };
    } catch { error = 'Failed to add subtask'; }
  }

  async function toggleSubtask(todoId: string, sub: Subtask) {
    try {
      const updated = await api.subtasks.update(todoId, sub.id, { title: sub.title, isComplete: !sub.isComplete });
      subtaskMap = { ...subtaskMap, [todoId]: (subtaskMap[todoId] ?? []).map(s => s.id === updated.id ? updated : s) };
    } catch { error = 'Failed to update subtask'; }
  }

  async function removeSubtask(todoId: string, subtaskId: string) {
    try {
      await api.subtasks.delete(todoId, subtaskId);
      subtaskMap = { ...subtaskMap, [todoId]: (subtaskMap[todoId] ?? []).filter(s => s.id !== subtaskId) };
    } catch { error = 'Failed to delete subtask'; }
  }

  function subtaskProgress(todoId: string) {
    const subs = subtaskMap[todoId] ?? [];
    return { done: subs.filter(s => s.isComplete).length, total: subs.length };
  }

  // ── Drag & drop ───────────────────────────────────────────────────────────
  function onDragStart(e: DragEvent, todo: Todo) {
    e.dataTransfer?.setData('text/plain', todo.id);
    draggingId = todo.id;
  }

  function onDragOver(e: DragEvent, col: Status) {
    e.preventDefault();
    dragOverCol = col;
  }

  function onDrop(e: DragEvent, col: Status) {
    e.preventDefault();
    if (draggingId) moveToStatus(draggingId, col);
    draggingId = null; dragOverCol = null;
  }

  function onDragEnd() { draggingId = null; dragOverCol = null; }

  // ── Formatters ────────────────────────────────────────────────────────────
  function fmt(s: number): string {
    if (s === 0) return '0:00';
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m`;
    return `${m}:${String(sec).padStart(2, '0')}`;
  }

  function fmtTotal(s: number): string {
    if (s === 0) return '0m';
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  }

  function fmtDate(iso: string): string {
    const d = new Date(iso + 'T00:00:00');
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
  }

  function dueBadge(dueDate: string | null): { label: string; cls: string } | null {
    if (!dueDate) return null;
    const today = new Date().toISOString().slice(0, 10);
    const diff  = Math.ceil(
      (new Date(dueDate + 'T00:00:00').getTime() - new Date(today + 'T00:00:00').getTime())
      / 86400000
    );
    if (diff < 0)  return { label: 'Overdue',  cls: 'due-overdue' };
    if (diff === 0) return { label: 'Today',    cls: 'due-today'   };
    if (diff <= 3)  return { label: 'Soon',     cls: 'due-soon'    };
    return { label: fmtDate(dueDate), cls: 'due-future' };
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  onMount(async () => {
    try { todos = await api.list(); }
    catch (e) { error = e instanceof Error ? e.message : 'Failed to load'; }
    finally   { loading = false; }
  });

  onDestroy(() => clearTimerLoop());

  // ── Config ────────────────────────────────────────────────────────────────
  const COLUMNS: { status: Status; label: string; colorClass: string }[] = [
    { status: 'todo',        label: 'To Do',       colorClass: 'col-todo'     },
    { status: 'in_progress', label: 'In Progress', colorClass: 'col-progress' },
    { status: 'done',        label: 'Done',         colorClass: 'col-done'    },
  ];

  function colCards(status: Status) {
    return status === 'todo' ? colTodo
         : status === 'in_progress' ? colProgress
         : colDone;
  }

  const PRIORITY_LABELS: Record<Priority, string> = {
    none: '', low: 'Low', medium: 'Medium', high: 'High', urgent: 'Urgent',
  };
</script>

<svelte:head>
  <title>TaskFlow</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500&display=swap" rel="stylesheet">
</svelte:head>

<div class="app">

  <!-- ── Navbar ── -->
  <nav class="navbar">
    <div class="nav-left">
      <span class="brand">
        <span class="brand-icon">T</span>
        TaskFlow
      </span>
      <div class="view-tabs">
        <button class="view-tab" class:active={view === 'board'} onclick={() => view = 'board'}>
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
            <rect x="0" y="0" width="4" height="9" rx="1.5" fill="currentColor"/>
            <rect x="5" y="2" width="4" height="12" rx="1.5" fill="currentColor"/>
            <rect x="10" y="1" width="4" height="7" rx="1.5" fill="currentColor"/>
          </svg>
          Board
        </button>
        <button class="view-tab" class:active={view === 'list'} onclick={() => view = 'list'}>
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
            <rect x="0" y="1" width="14" height="2" rx="1" fill="currentColor"/>
            <rect x="0" y="6" width="14" height="2" rx="1" fill="currentColor"/>
            <rect x="0" y="11" width="14" height="2" rx="1" fill="currentColor"/>
          </svg>
          List
        </button>
      </div>
    </div>

    <div class="nav-center">
      {#if navTimerLabel}
        <div class="timer-pill">
          <span class="timer-dot"></span>
          {navTimerLabel}
        </div>
      {/if}
    </div>

    <div class="nav-right">
      <button class="btn-new" onclick={openModal}>
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none" aria-hidden="true">
          <path d="M6 1v10M1 6h10" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
        </svg>
        New Task
      </button>
    </div>
  </nav>

  <!-- ── Stats bar ── -->
  <div class="stats-bar">
    <div class="stat">
      <span class="stat-val">{totalCount}</span>
      <span class="stat-lbl">Total</span>
    </div>
    <div class="stat-divider"></div>
    <div class="stat">
      <span class="stat-val">{activeCount}</span>
      <span class="stat-lbl">Active</span>
    </div>
    <div class="stat-divider"></div>
    <div class="stat">
      <span class="stat-val done-val">{doneCount}</span>
      <span class="stat-lbl">Done</span>
    </div>
    <div class="stat-divider"></div>
    <div class="stat">
      <span class="stat-val grad-val">{fmtTotal(totalTracked)}</span>
      <span class="stat-lbl">Tracked</span>
    </div>
    {#if totalCount > 0}
      <div class="stat-divider"></div>
      <div class="stat progress-stat">
        <div class="mini-progress">
          <div class="mini-fill" style="width:{Math.round(doneCount/totalCount*100)}%"></div>
        </div>
        <span class="stat-lbl">{Math.round(doneCount/totalCount*100)}% complete</span>
      </div>
    {/if}
  </div>

  <!-- ── Filter bar ── -->
  <div class="filter-bar">
    <div class="search-wrap">
      <svg class="search-icon" width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
        <circle cx="6" cy="6" r="4.5" stroke="currentColor" stroke-width="1.5"/>
        <path d="M10 10l2.5 2.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
      </svg>
      <input class="search-input" type="text" placeholder="Search tasks…" bind:value={searchQuery} />
      {#if searchQuery}
        <button class="search-clear" onclick={() => searchQuery = ''} aria-label="Clear search">✕</button>
      {/if}
    </div>

    <div class="filter-chips">
      {#each ([['all','All'],['todo','To Do'],['in_progress','In Progress'],['done','Done']] as const) as [val, label]}
        <button
          class="chip"
          class:chip-active={filterStatus === val}
          onclick={() => filterStatus = val as Status | 'all'}
        >{label}</button>
      {/each}
    </div>

    <select class="filter-sel" bind:value={filterPriority}>
      <option value="all">All Priorities</option>
      <option value="none">None</option>
      <option value="low">Low</option>
      <option value="medium">Medium</option>
      <option value="high">High</option>
      <option value="urgent">Urgent</option>
    </select>

    <label class="overdue-toggle">
      <input type="checkbox" bind:checked={filterOverdue} />
      <span>Overdue only</span>
    </label>

    {#if searchQuery || filterStatus !== 'all' || filterPriority !== 'all' || filterOverdue}
      <button class="clear-filters" onclick={() => { searchQuery = ''; filterStatus = 'all'; filterPriority = 'all'; filterOverdue = false; }}>
        Clear filters
      </button>
    {/if}
  </div>

  <!-- ── Content ── -->
  <main class="content">

    {#if loading}
      <div class="state-center">
        <div class="spinner"></div>
        <span class="state-text">Loading your workspace…</span>
      </div>

    {:else if view === 'board'}
      <!-- ════ BOARD VIEW ════ -->
      <div class="board">
        {#each COLUMNS as col}
          {@const cards = colCards(col.status)}
          <div
            class="board-col {col.colorClass}"
            class:drag-over={dragOverCol === col.status}
            ondragover={e => onDragOver(e, col.status)}
            ondrop={e => onDrop(e, col.status)}
          >
            <div class="col-header">
              <span class="col-dot"></span>
              <span class="col-label">{col.label}</span>
              <span class="col-count">{cards.length}</span>
            </div>

            <div class="col-body">
              {#each cards as todo (todo.id)}
                {@const badge = dueBadge(todo.dueDate)}
                {@const timing = activeTimerId === todo.id}
                <div
                  class="task-card"
                  class:dragging={draggingId === todo.id}
                  class:timing
                  draggable="true"
                  ondragstart={e => onDragStart(e, todo)}
                  ondragend={onDragEnd}
                >
                  <div class="card-meta">
                    {#if todo.priority !== 'none'}
                      <span class="pri-badge pri-{todo.priority}">
                        {PRIORITY_LABELS[todo.priority]}
                      </span>
                    {/if}
                    {#if badge}
                      <span class="due-chip {badge.cls}">{badge.label}</span>
                    {/if}
                  </div>

                  <p class="card-title" class:done-title={todo.status === 'done'}>
                    {todo.title}
                  </p>

                  {#if todo.description}
                    <p class="card-desc">{todo.description.length > 80 ? todo.description.slice(0, 80) + '…' : todo.description}</p>
                  {/if}

                  {@const sp = subtaskProgress(todo.id)}
                  {#if sp.total > 0}
                    <div class="subtask-bar-wrap">
                      <div class="subtask-bar">
                        <div class="subtask-fill" style="width:{Math.round(sp.done/sp.total*100)}%"></div>
                      </div>
                      <span class="subtask-count">{sp.done}/{sp.total}</span>
                    </div>
                  {/if}

                  <div class="card-footer">
                    <span class="card-time" class:live={timing}>
                      {fmt(liveSeconds(todo))}
                    </span>
                    <div class="card-actions">
                      <button
                        class="card-btn expand-btn"
                        class:expanded={expandedId === todo.id}
                        onclick={() => toggleExpand(todo)}
                        aria-label="Subtasks"
                      >
                        <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                          <path d="M2 1h6M2 5h4M2 9h5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
                        </svg>
                      </button>
                      {#if todo.status !== 'done'}
                        <button
                          class="card-btn timer-btn"
                          class:active={timing}
                          onclick={() => toggleTimer(todo)}
                          aria-label={timing ? 'Pause' : 'Start timer'}
                        >
                          {#if timing}
                            <svg width="9" height="11" viewBox="0 0 9 11" fill="currentColor">
                              <rect x="0" y="0" width="3" height="11" rx="1"/>
                              <rect x="6" y="0" width="3" height="11" rx="1"/>
                            </svg>
                          {:else}
                            <svg width="9" height="11" viewBox="0 0 9 11" fill="currentColor">
                              <path d="M0 0l9 5.5L0 11V0z"/>
                            </svg>
                          {/if}
                        </button>
                      {/if}
                      <button class="card-btn del-btn" onclick={() => deleteTask(todo.id)} aria-label="Delete">
                        <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                          <path d="M1 1l8 8M9 1L1 9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
                        </svg>
                      </button>
                    </div>
                  </div>

                  {#if expandedId === todo.id}
                    <div class="subtask-panel">
                      {#if subtaskLoading[todo.id]}
                        <span class="subtask-loading">Loading…</span>
                      {:else}
                        {#each subtaskMap[todo.id] ?? [] as sub (sub.id)}
                          <div class="subtask-row">
                            <button
                              class="sub-check"
                              class:sub-done={sub.isComplete}
                              onclick={() => toggleSubtask(todo.id, sub)}
                              aria-label="Toggle subtask"
                            >
                              {#if sub.isComplete}
                                <svg width="8" height="8" viewBox="0 0 8 8" fill="none">
                                  <path d="M1 4l2 2 4-4" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
                                </svg>
                              {/if}
                            </button>
                            <span class="sub-title" class:sub-title-done={sub.isComplete}>{sub.title}</span>
                            <button class="sub-del" onclick={() => removeSubtask(todo.id, sub.id)} aria-label="Delete subtask">✕</button>
                          </div>
                        {/each}
                        <div class="subtask-add">
                          <input
                            class="subtask-input"
                            type="text"
                            placeholder="Add subtask…"
                            value={subtaskDraft[todo.id] ?? ''}
                            oninput={e => subtaskDraft = { ...subtaskDraft, [todo.id]: e.currentTarget.value }}
                            onkeydown={e => e.key === 'Enter' && addSubtask(todo.id)}
                          />
                          <button class="subtask-add-btn" onclick={() => addSubtask(todo.id)}>+</button>
                        </div>
                      {/if}
                    </div>
                  {/if}
                </div>
              {/each}

              {#if cards.length === 0}
                <div class="col-empty">Drop tasks here</div>
              {/if}
            </div>
          </div>
        {/each}
      </div>

    {:else}
      <!-- ════ LIST VIEW ════ -->
      <div class="list-wrap">
        {#if todos.length === 0}
          <div class="state-center">
            <div class="empty-icon">
              <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
                <rect x="2" y="2" width="18" height="18" rx="4" stroke="currentColor" stroke-width="1.5"/>
                <path d="M7 11h8M7 7h5M7 15h6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
              </svg>
            </div>
            <span class="state-text">No tasks yet. Hit <strong>New Task</strong> to start.</span>
          </div>
        {:else}
          <table class="task-table">
            <thead>
              <tr>
                <th class="th-check"></th>
                <th class="th-title">Title</th>
                <th class="th-status">Status</th>
                <th class="th-priority">Priority</th>
                <th class="th-due">Due</th>
                <th class="th-time">Time</th>
                <th class="th-actions"></th>
              </tr>
            </thead>
            <tbody>
              {#each filteredTodos as todo (todo.id)}
                {@const badge = dueBadge(todo.dueDate)}
                {@const timing = activeTimerId === todo.id}
                <tr class="task-row" class:row-done={todo.status === 'done'}>

                  <td class="td-check">
                    <button
                      class="check-btn"
                      class:checked={todo.status === 'done'}
                      onclick={() => updateTaskField(todo, { status: todo.status === 'done' ? 'todo' : 'done' })}
                      aria-label="Toggle done"
                    >
                      {#if todo.status === 'done'}
                        <svg width="9" height="9" viewBox="0 0 9 9" fill="none">
                          <path d="M1 4.5l2.5 2.5 4.5-4.5" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
                        </svg>
                      {/if}
                    </button>
                  </td>

                  <td class="td-title">
                    {#if editingId === todo.id}
                      <input
                        class="inline-edit"
                        bind:value={editingTitle}
                        onkeydown={e => {
                          if (e.key === 'Enter') commitEdit(todo);
                          if (e.key === 'Escape') cancelEdit();
                        }}
                        onblur={() => commitEdit(todo)}
                        autofocus
                      />
                    {:else}
                      <div class="title-cell">
                        <span
                          class="title-text"
                          class:done-title={todo.status === 'done'}
                          ondblclick={() => startEdit(todo)}
                        >{todo.title}</span>
                        {#if todo.description}
                          <span class="row-desc">{todo.description.length > 60 ? todo.description.slice(0, 60) + '…' : todo.description}</span>
                        {/if}
                        {@const sp = subtaskProgress(todo.id)}
                        {#if sp.total > 0}
                          <span class="row-subtask-badge">{sp.done}/{sp.total} subtasks</span>
                        {/if}
                      </div>
                    {/if}
                  </td>

                  <td class="td-status">
                    <select
                      class="sel status-sel status-{todo.status}"
                      value={todo.status}
                      onchange={e => updateTaskField(todo, { status: e.currentTarget.value as Status })}
                    >
                      <option value="todo">To Do</option>
                      <option value="in_progress">In Progress</option>
                      <option value="done">Done</option>
                    </select>
                  </td>

                  <td class="td-priority">
                    <select
                      class="sel priority-sel pri-sel-{todo.priority}"
                      value={todo.priority}
                      onchange={e => updateTaskField(todo, { priority: e.currentTarget.value as Priority })}
                    >
                      <option value="none">—</option>
                      <option value="low">Low</option>
                      <option value="medium">Medium</option>
                      <option value="high">High</option>
                      <option value="urgent">Urgent</option>
                    </select>
                  </td>

                  <td class="td-due">
                    {#if badge && todo.dueDate}
                      <span class="due-pill {badge.cls}">
                        {fmtDate(todo.dueDate)}
                      </span>
                    {:else}
                      <span class="no-val">—</span>
                    {/if}
                  </td>

                  <td class="td-time">
                    <span class="time-mono" class:live={timing}>{fmt(liveSeconds(todo))}</span>
                    {#if todo.status !== 'done'}
                      <button
                        class="row-timer"
                        class:active={timing}
                        onclick={() => toggleTimer(todo)}
                        aria-label={timing ? 'Pause' : 'Start timer'}
                      >
                        {#if timing}
                          <svg width="8" height="10" viewBox="0 0 8 10" fill="currentColor">
                            <rect x="0" y="0" width="2.5" height="10" rx="1"/>
                            <rect x="5.5" y="0" width="2.5" height="10" rx="1"/>
                          </svg>
                        {:else}
                          <svg width="8" height="10" viewBox="0 0 8 10" fill="currentColor">
                            <path d="M0 0l8 5L0 10V0z"/>
                          </svg>
                        {/if}
                      </button>
                    {/if}
                  </td>

                  <td class="td-actions">
                    <button
                      class="row-expand"
                      class:expanded={expandedId === todo.id}
                      onclick={() => toggleExpand(todo)}
                      aria-label="Subtasks"
                    >
                      <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                        <path d="M2 1h6M2 5h4M2 9h5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
                      </svg>
                    </button>
                    <button class="row-del" onclick={() => deleteTask(todo.id)} aria-label="Delete">
                      <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
                        <path d="M1 1l9 9M10 1L1 10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
                      </svg>
                    </button>
                  </td>
                </tr>

                {#if expandedId === todo.id}
                  <tr class="subtask-expand-row">
                    <td colspan="7" class="subtask-expand-cell">
                      {#if subtaskLoading[todo.id]}
                        <span class="subtask-loading">Loading…</span>
                      {:else}
                        <div class="subtask-list">
                          {#each subtaskMap[todo.id] ?? [] as sub (sub.id)}
                            <div class="subtask-row">
                              <button
                                class="sub-check"
                                class:sub-done={sub.isComplete}
                                onclick={() => toggleSubtask(todo.id, sub)}
                                aria-label="Toggle subtask"
                              >
                                {#if sub.isComplete}
                                  <svg width="8" height="8" viewBox="0 0 8 8" fill="none">
                                    <path d="M1 4l2 2 4-4" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
                                  </svg>
                                {/if}
                              </button>
                              <span class="sub-title" class:sub-title-done={sub.isComplete}>{sub.title}</span>
                              <button class="sub-del" onclick={() => removeSubtask(todo.id, sub.id)} aria-label="Delete subtask">✕</button>
                            </div>
                          {/each}
                          <div class="subtask-add">
                            <input
                              class="subtask-input"
                              type="text"
                              placeholder="Add subtask…"
                              value={subtaskDraft[todo.id] ?? ''}
                              oninput={e => subtaskDraft = { ...subtaskDraft, [todo.id]: e.currentTarget.value }}
                              onkeydown={e => e.key === 'Enter' && addSubtask(todo.id)}
                            />
                            <button class="subtask-add-btn" onclick={() => addSubtask(todo.id)}>+</button>
                          </div>
                        </div>
                      {/if}
                    </td>
                  </tr>
                {/if}
              {/each}
            </tbody>
          </table>
        {/if}
      </div>
    {/if}
  </main>

  <!-- ── New Task Modal ── -->
  {#if showModal}
    <div
      class="backdrop"
      role="presentation"
      onclick={e => e.target === e.currentTarget && (showModal = false)}
      onkeydown={e => e.key === 'Escape' && (showModal = false)}
    >
      <div class="modal" role="dialog" aria-modal="true" aria-label="New Task">
        <div class="modal-header">
          <h2 class="modal-title">New Task</h2>
          <button class="modal-close" onclick={() => showModal = false} aria-label="Close">
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
              <path d="M1 1l10 10M11 1L1 11" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
            </svg>
          </button>
        </div>

        <div class="modal-body">
          <label class="field">
            <span class="field-label">Title</span>
            <input
              class="field-input"
              type="text"
              bind:value={modalTitle}
              onkeydown={e => e.key === 'Enter' && createTask()}
              placeholder="What needs to be done?"
              autofocus
            />
          </label>

          <div class="field-row">
            <label class="field">
              <span class="field-label">Status</span>
              <select class="field-select" bind:value={modalStatus}>
                <option value="todo">To Do</option>
                <option value="in_progress">In Progress</option>
                <option value="done">Done</option>
              </select>
            </label>
            <label class="field">
              <span class="field-label">Priority</span>
              <select class="field-select" bind:value={modalPriority}>
                <option value="none">None</option>
                <option value="low">Low</option>
                <option value="medium">Medium</option>
                <option value="high">High</option>
                <option value="urgent">Urgent</option>
              </select>
            </label>
          </div>

          <label class="field">
            <span class="field-label">Due Date <span class="field-opt">(optional)</span></span>
            <input class="field-input" type="date" bind:value={modalDueDate} />
          </label>

          <label class="field">
            <span class="field-label">Notes <span class="field-opt">(optional)</span></span>
            <textarea
              class="field-input field-textarea"
              bind:value={modalDescription}
              placeholder="Add context, links, or details…"
              rows="3"
            ></textarea>
          </label>
        </div>

        <div class="modal-footer">
          <button class="btn-cancel" onclick={() => showModal = false}>Cancel</button>
          <button
            class="btn-create"
            onclick={createTask}
            disabled={!modalTitle.trim() || modalSaving}
          >
            {modalSaving ? 'Creating…' : 'Create Task'}
          </button>
        </div>
      </div>
    </div>
  {/if}

  <!-- ── Error toast ── -->
  {#if error}
    <div class="toast" role="alert">
      <span>{error}</span>
      <button onclick={() => error = null} aria-label="Dismiss">✕</button>
    </div>
  {/if}

</div>

<style>
  /* ── Reset & base ── */
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :global(html, body) {
    height: 100%;
    font-family: 'Inter', system-ui, sans-serif;
    background: #0D0F1A;
    color: #E2E8F0;
    -webkit-font-smoothing: antialiased;
  }

  .app {
    display: flex;
    flex-direction: column;
    min-height: 100vh;
    background: #0D0F1A;
  }

  /* ── Navbar ── */
  .navbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 1.5rem;
    height: 56px;
    background: #111320;
    border-bottom: 1px solid #1E2235;
    position: sticky;
    top: 0;
    z-index: 100;
    gap: 1rem;
    flex-shrink: 0;
  }

  .nav-left  { display: flex; align-items: center; gap: 1.25rem; }
  .nav-center { flex: 1; display: flex; justify-content: center; }
  .nav-right  { display: flex; align-items: center; }

  .brand {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.95rem;
    font-weight: 700;
    color: #F0F4FF;
    letter-spacing: -0.2px;
    white-space: nowrap;
  }

  .brand-icon {
    width: 26px;
    height: 26px;
    border-radius: 8px;
    background: linear-gradient(135deg, #EC4899, #8B5CF6);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.75rem;
    font-weight: 800;
    color: white;
    flex-shrink: 0;
  }

  .view-tabs {
    display: flex;
    gap: 0.15rem;
    background: #1A1D2E;
    border: 1px solid #252840;
    border-radius: 10px;
    padding: 0.2rem;
  }

  .view-tab {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.35rem 0.75rem;
    border: none;
    background: transparent;
    border-radius: 7px;
    font-size: 0.8rem;
    font-weight: 500;
    font-family: inherit;
    color: #64748B;
    cursor: pointer;
    transition: all 0.15s;
    white-space: nowrap;
  }

  .view-tab:hover { color: #94A3B8; }

  .view-tab.active {
    background: #252840;
    color: #F0F4FF;
  }

  .timer-pill {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.8rem;
    font-weight: 500;
    color: #A78BFA;
    background: rgba(167, 139, 250, 0.08);
    border: 1px solid rgba(167, 139, 250, 0.2);
    border-radius: 100px;
    padding: 0.3rem 0.8rem;
    font-family: 'JetBrains Mono', monospace;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 300px;
  }

  .timer-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: #EC4899;
    flex-shrink: 0;
    animation: pulse 1.5s ease infinite;
  }

  @keyframes pulse {
    0%, 100% { box-shadow: 0 0 0 0 rgba(236,72,153,0.5); }
    50%       { box-shadow: 0 0 0 5px rgba(236,72,153,0); }
  }

  .btn-new {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.5rem 1rem;
    background: linear-gradient(135deg, #EC4899, #8B5CF6);
    color: white;
    border: none;
    border-radius: 10px;
    font-size: 0.82rem;
    font-weight: 600;
    font-family: inherit;
    cursor: pointer;
    transition: opacity 0.15s, transform 0.1s;
    white-space: nowrap;
  }

  .btn-new:hover  { opacity: 0.9; transform: translateY(-1px); }
  .btn-new:active { transform: translateY(0); }

  /* ── Stats bar ── */
  .stats-bar {
    display: flex;
    align-items: center;
    gap: 1.5rem;
    padding: 0.75rem 1.75rem;
    background: #111320;
    border-bottom: 1px solid #1E2235;
    flex-shrink: 0;
    flex-wrap: wrap;
  }

  .stat {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 0.1rem;
  }

  .stat-val {
    font-size: 1.05rem;
    font-weight: 700;
    color: #E2E8F0;
    line-height: 1.2;
  }

  .stat-lbl {
    font-size: 0.68rem;
    font-weight: 500;
    color: #475569;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .done-val { color: #34D399; }

  .grad-val {
    background: linear-gradient(135deg, #EC4899, #8B5CF6);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }

  .stat-divider {
    width: 1px;
    height: 28px;
    background: #1E2235;
  }

  .progress-stat { flex-direction: row; align-items: center; gap: 0.6rem; }

  .mini-progress {
    width: 80px;
    height: 4px;
    background: #1E2235;
    border-radius: 100px;
    overflow: hidden;
  }

  .mini-fill {
    height: 100%;
    background: linear-gradient(90deg, #EC4899, #8B5CF6);
    border-radius: 100px;
    transition: width 0.4s ease;
  }

  /* ── Content ── */
  .content {
    flex: 1;
    padding: 1.5rem;
    overflow: auto;
  }

  /* ── Board ── */
  .board {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 1.25rem;
    align-items: start;
    min-height: calc(100vh - 160px);
  }

  .board-col {
    background: #111320;
    border: 1px solid #1E2235;
    border-radius: 14px;
    overflow: hidden;
    transition: border-color 0.15s, background 0.15s;
  }

  .board-col.drag-over {
    border-color: #8B5CF6;
    background: rgba(139, 92, 246, 0.05);
  }

  .col-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.875rem 1rem;
    border-bottom: 1px solid #1E2235;
  }

  .col-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .col-todo     .col-dot { background: #64748B; }
  .col-progress .col-dot { background: #60A5FA; }
  .col-done     .col-dot { background: #34D399; }

  .col-label {
    flex: 1;
    font-size: 0.78rem;
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }

  .col-todo     .col-label { color: #64748B; }
  .col-progress .col-label { color: #60A5FA; }
  .col-done     .col-label { color: #34D399; }

  .col-count {
    font-size: 0.72rem;
    font-weight: 600;
    color: #334155;
    background: #1A1D2E;
    border-radius: 100px;
    padding: 0.1rem 0.45rem;
  }

  .col-body {
    padding: 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    min-height: 80px;
  }

  .col-empty {
    text-align: center;
    font-size: 0.75rem;
    color: #2D3148;
    padding: 1.5rem 0;
    border: 1.5px dashed #1E2235;
    border-radius: 10px;
  }

  /* ── Task card ── */
  .task-card {
    background: #161929;
    border: 1px solid #1E2235;
    border-radius: 12px;
    padding: 0.875rem;
    cursor: grab;
    transition: border-color 0.15s, box-shadow 0.15s, transform 0.1s, opacity 0.15s;
    user-select: none;
  }

  .task-card:hover {
    border-color: #2D3148;
    box-shadow: 0 4px 16px rgba(0,0,0,0.4);
    transform: translateY(-1px);
  }

  .task-card.dragging {
    opacity: 0.4;
    transform: scale(0.97);
    cursor: grabbing;
  }

  .task-card.timing {
    border-color: rgba(236,72,153,0.35);
    box-shadow: 0 0 0 2px rgba(236,72,153,0.1);
  }

  .card-meta {
    display: flex;
    gap: 0.35rem;
    flex-wrap: wrap;
    margin-bottom: 0.6rem;
    min-height: 18px;
  }

  .card-title {
    font-size: 0.875rem;
    font-weight: 500;
    color: #CBD5E1;
    line-height: 1.45;
    margin-bottom: 0.75rem;
  }

  .done-title {
    text-decoration: line-through;
    color: #334155;
  }

  .card-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .card-time {
    font-size: 0.72rem;
    font-weight: 600;
    font-family: 'JetBrains Mono', monospace;
    color: #334155;
  }

  .card-time.live { color: #EC4899; }

  .card-actions {
    display: flex;
    gap: 0.3rem;
  }

  .card-btn {
    width: 26px;
    height: 26px;
    border-radius: 7px;
    border: 1px solid #252840;
    background: #1A1D2E;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #475569;
    transition: all 0.15s;
  }

  .card-btn:hover { border-color: #334155; color: #94A3B8; }

  .timer-btn:hover { border-color: #EC4899; color: #EC4899; background: rgba(236,72,153,0.1); }
  .timer-btn.active {
    border-color: #EC4899;
    color: #EC4899;
    background: rgba(236,72,153,0.12);
  }

  .del-btn:hover { border-color: #F43F5E; color: #F43F5E; background: rgba(244,63,94,0.08); }

  /* ── Priority badges ── */
  .pri-badge {
    font-size: 0.65rem;
    font-weight: 600;
    padding: 0.15rem 0.45rem;
    border-radius: 100px;
    letter-spacing: 0.03em;
  }

  .pri-low    { background: rgba(96,165,250,0.12);  color: #60A5FA; }
  .pri-medium { background: rgba(251,191,36,0.12);  color: #FBBF24; }
  .pri-high   { background: rgba(249,115,22,0.12);  color: #FB923C; }
  .pri-urgent {
    background: rgba(244,63,94,0.12);
    color: #F43F5E;
    animation: urgentGlow 1.5s ease infinite;
  }

  @keyframes urgentGlow {
    0%, 100% { box-shadow: 0 0 0 0 rgba(244,63,94,0.4); }
    50%       { box-shadow: 0 0 0 3px rgba(244,63,94,0); }
  }

  /* ── Due chips ── */
  .due-chip {
    font-size: 0.65rem;
    font-weight: 600;
    padding: 0.15rem 0.45rem;
    border-radius: 100px;
  }

  .due-overdue { background: rgba(244,63,94,0.12);  color: #F43F5E; }
  .due-today   { background: rgba(251,191,36,0.12); color: #FBBF24; }
  .due-soon    { background: rgba(167,139,250,0.12);color: #A78BFA; }
  .due-future  { background: #1A1D2E; color: #475569; }

  /* ── List view ── */
  .list-wrap {
    background: #111320;
    border: 1px solid #1E2235;
    border-radius: 14px;
    overflow: hidden;
  }

  .task-table {
    width: 100%;
    border-collapse: collapse;
  }

  .task-table thead th {
    background: #0D0F1A;
    padding: 0.65rem 0.875rem;
    text-align: left;
    font-size: 0.68rem;
    font-weight: 600;
    color: #334155;
    text-transform: uppercase;
    letter-spacing: 0.07em;
    border-bottom: 1px solid #1E2235;
    white-space: nowrap;
  }

  .th-check { width: 40px; }
  .th-actions { width: 40px; }
  .th-time { width: 100px; }
  .th-status { width: 140px; }
  .th-priority { width: 120px; }
  .th-due { width: 120px; }

  .task-row {
    border-bottom: 1px solid #1A1D2E;
    transition: background 0.1s;
  }

  .task-row:hover { background: #161929; }
  .task-row:last-child { border-bottom: none; }

  .task-row.row-done { opacity: 0.55; }

  .task-table td {
    padding: 0.7rem 0.875rem;
    vertical-align: middle;
  }

  .td-check, .td-actions { text-align: center; padding: 0.7rem 0.5rem; }

  /* Check button */
  .check-btn {
    width: 18px;
    height: 18px;
    border-radius: 50%;
    border: 1.5px solid #2D3148;
    background: transparent;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.15s;
    padding: 0;
    flex-shrink: 0;
  }

  .check-btn:hover { border-color: #EC4899; }
  .check-btn.checked { background: #34D399; border-color: #34D399; }

  /* Title cell */
  .title-text {
    font-size: 0.875rem;
    font-weight: 500;
    color: #CBD5E1;
    cursor: default;
  }

  .title-text.done-title { text-decoration: line-through; color: #334155; }

  .inline-edit {
    background: transparent;
    border: none;
    border-bottom: 1.5px solid #8B5CF6;
    outline: none;
    font-size: 0.875rem;
    font-weight: 500;
    font-family: inherit;
    color: #E2E8F0;
    width: 100%;
    padding: 0 0 2px;
  }

  /* Selects */
  .sel {
    background: transparent;
    border: none;
    outline: none;
    font-size: 0.8rem;
    font-weight: 600;
    font-family: inherit;
    cursor: pointer;
    padding: 0.2rem 0.35rem;
    border-radius: 6px;
    transition: background 0.1s;
    appearance: none;
    -webkit-appearance: none;
  }

  .sel:hover { background: #1A1D2E; }

  .status-todo        { color: #64748B; }
  .status-in_progress { color: #60A5FA; }
  .status-done        { color: #34D399; }

  .pri-sel-none   { color: #334155; }
  .pri-sel-low    { color: #60A5FA; }
  .pri-sel-medium { color: #FBBF24; }
  .pri-sel-high   { color: #FB923C; }
  .pri-sel-urgent { color: #F43F5E; }

  /* Due date pill */
  .due-pill {
    font-size: 0.75rem;
    font-weight: 600;
    padding: 0.2rem 0.55rem;
    border-radius: 100px;
  }

  .no-val { color: #2D3148; font-size: 0.8rem; }

  /* Time cell */
  .td-time { white-space: nowrap; }

  .time-mono {
    font-size: 0.78rem;
    font-weight: 600;
    font-family: 'JetBrains Mono', monospace;
    color: #334155;
    margin-right: 0.4rem;
  }

  .time-mono.live { color: #EC4899; }

  .row-timer {
    width: 22px;
    height: 22px;
    border-radius: 6px;
    border: 1px solid #252840;
    background: transparent;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    color: #475569;
    transition: all 0.15s;
    vertical-align: middle;
  }

  .row-timer:hover { border-color: #EC4899; color: #EC4899; background: rgba(236,72,153,0.08); }
  .row-timer.active { border-color: #EC4899; color: #EC4899; background: rgba(236,72,153,0.1); }

  .row-del {
    width: 24px;
    height: 24px;
    border-radius: 6px;
    border: none;
    background: transparent;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #2D3148;
    transition: all 0.15s;
    opacity: 0;
  }

  .task-row:hover .row-del { opacity: 1; }
  .row-del:hover { color: #F43F5E; background: rgba(244,63,94,0.08); }

  /* ── Modal ── */
  .backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.7);
    backdrop-filter: blur(6px);
    z-index: 200;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 1rem;
  }

  .modal {
    background: #161929;
    border: 1px solid #252840;
    border-radius: 18px;
    width: min(480px, 100%);
    box-shadow: 0 24px 60px rgba(0,0,0,0.7);
    overflow: hidden;
  }

  .modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1.25rem 1.5rem;
    border-bottom: 1px solid #1E2235;
  }

  .modal-title {
    font-size: 1rem;
    font-weight: 700;
    color: #F0F4FF;
  }

  .modal-close {
    width: 28px;
    height: 28px;
    border-radius: 8px;
    border: 1px solid #252840;
    background: transparent;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #475569;
    transition: all 0.15s;
  }

  .modal-close:hover { border-color: #334155; color: #94A3B8; }

  .modal-body {
    padding: 1.5rem;
    display: flex;
    flex-direction: column;
    gap: 1.1rem;
  }

  .field { display: flex; flex-direction: column; gap: 0.4rem; }

  .field-label {
    font-size: 0.75rem;
    font-weight: 600;
    color: #64748B;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .field-opt { font-weight: 400; text-transform: none; letter-spacing: 0; }

  .field-row { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }

  .field-input,
  .field-select {
    background: #1A1D2E;
    border: 1.5px solid #252840;
    border-radius: 10px;
    padding: 0.65rem 0.875rem;
    font-size: 0.875rem;
    font-family: inherit;
    color: #E2E8F0;
    outline: none;
    transition: border-color 0.15s, box-shadow 0.15s;
    appearance: none;
    -webkit-appearance: none;
    width: 100%;
  }

  .field-input::placeholder { color: #2D3148; }

  .field-input:focus,
  .field-select:focus {
    border-color: #8B5CF6;
    box-shadow: 0 0 0 3px rgba(139,92,246,0.12);
  }

  .field-select option { background: #1A1D2E; }

  .modal-footer {
    display: flex;
    justify-content: flex-end;
    gap: 0.625rem;
    padding: 1.1rem 1.5rem;
    border-top: 1px solid #1E2235;
  }

  .btn-cancel {
    padding: 0.6rem 1.1rem;
    background: transparent;
    border: 1px solid #252840;
    border-radius: 10px;
    font-size: 0.85rem;
    font-weight: 600;
    font-family: inherit;
    color: #64748B;
    cursor: pointer;
    transition: all 0.15s;
  }

  .btn-cancel:hover { border-color: #334155; color: #94A3B8; }

  .btn-create {
    padding: 0.6rem 1.25rem;
    background: linear-gradient(135deg, #EC4899, #8B5CF6);
    border: none;
    border-radius: 10px;
    font-size: 0.85rem;
    font-weight: 600;
    font-family: inherit;
    color: white;
    cursor: pointer;
    transition: opacity 0.15s, transform 0.1s;
  }

  .btn-create:hover:not(:disabled) { opacity: 0.9; transform: translateY(-1px); }
  .btn-create:active:not(:disabled) { transform: translateY(0); }
  .btn-create:disabled { opacity: 0.35; cursor: not-allowed; }

  /* ── Toast ── */
  .toast {
    position: fixed;
    bottom: 1.5rem;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 0.75rem;
    background: #F43F5E;
    color: white;
    font-size: 0.85rem;
    font-weight: 500;
    padding: 0.75rem 1rem;
    border-radius: 12px;
    box-shadow: 0 8px 24px rgba(244,63,94,0.4);
    z-index: 300;
    white-space: nowrap;
  }

  .toast button {
    background: none;
    border: none;
    cursor: pointer;
    color: white;
    opacity: 0.7;
    font-size: 0.9rem;
  }

  /* ── States ── */
  .state-center {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 1rem;
    min-height: 320px;
    color: #334155;
  }

  .spinner {
    width: 28px;
    height: 28px;
    border: 2.5px solid #1E2235;
    border-top-color: #8B5CF6;
    border-radius: 50%;
    animation: spin 0.7s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }

  .empty-icon {
    width: 52px;
    height: 52px;
    border-radius: 14px;
    background: #161929;
    border: 1px solid #1E2235;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #334155;
  }

  .state-text {
    font-size: 0.875rem;
    color: #334155;
  }

  .state-text strong { color: #64748B; }

  /* ── Responsive ── */
  @media (max-width: 900px) {
    .board { grid-template-columns: 1fr; }
    .timer-pill { display: none; }
    .stats-bar { gap: 1rem; }
  }

  @media (max-width: 600px) {
    .navbar { padding: 0 1rem; }
    .content { padding: 1rem; }
    .brand span:last-child { display: none; }
    .stat-divider { display: none; }
  }

  /* ── Filter bar ── */
  .filter-bar {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.75rem 1.5rem;
    background: #111320;
    border-bottom: 1px solid #1E2235;
    flex-wrap: wrap;
  }

  .search-wrap {
    position: relative;
    display: flex;
    align-items: center;
    flex: 0 0 200px;
  }

  .search-icon {
    position: absolute;
    left: 0.65rem;
    color: #334155;
    pointer-events: none;
  }

  .search-input {
    width: 100%;
    background: #1A1D2E;
    border: 1.5px solid #252840;
    border-radius: 9px;
    padding: 0.45rem 2rem 0.45rem 2.1rem;
    font-size: 0.82rem;
    font-family: inherit;
    color: #E2E8F0;
    outline: none;
    transition: border-color 0.15s;
  }

  .search-input::placeholder { color: #2D3148; }
  .search-input:focus { border-color: #8B5CF6; }

  .search-clear {
    position: absolute;
    right: 0.5rem;
    background: none;
    border: none;
    cursor: pointer;
    color: #334155;
    font-size: 0.75rem;
    padding: 0.15rem;
    transition: color 0.15s;
  }

  .search-clear:hover { color: #94A3B8; }

  .filter-chips { display: flex; gap: 0.35rem; }

  .chip {
    padding: 0.35rem 0.7rem;
    border-radius: 20px;
    border: 1.5px solid #252840;
    background: transparent;
    font-size: 0.75rem;
    font-weight: 500;
    font-family: inherit;
    color: #64748B;
    cursor: pointer;
    transition: all 0.15s;
    white-space: nowrap;
  }

  .chip:hover { border-color: #334155; color: #94A3B8; }
  .chip-active { background: rgba(139,92,246,0.15); border-color: #8B5CF6; color: #C4B5FD; }

  .filter-sel {
    background: #1A1D2E;
    border: 1.5px solid #252840;
    border-radius: 9px;
    padding: 0.4rem 0.7rem;
    font-size: 0.8rem;
    font-family: inherit;
    color: #94A3B8;
    outline: none;
    cursor: pointer;
    appearance: none;
    -webkit-appearance: none;
    transition: border-color 0.15s;
  }

  .filter-sel:focus { border-color: #8B5CF6; }
  .filter-sel option { background: #1A1D2E; }

  .overdue-toggle {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.8rem;
    color: #64748B;
    cursor: pointer;
    user-select: none;
  }

  .overdue-toggle input { accent-color: #EC4899; cursor: pointer; }

  .clear-filters {
    background: none;
    border: none;
    font-size: 0.78rem;
    font-family: inherit;
    color: #EC4899;
    cursor: pointer;
    padding: 0.3rem 0.5rem;
    border-radius: 6px;
    transition: background 0.15s;
    margin-left: auto;
  }

  .clear-filters:hover { background: rgba(236,72,153,0.1); }

  /* ── Card description ── */
  .card-desc {
    font-size: 0.75rem;
    color: #475569;
    line-height: 1.45;
    margin-top: 0.25rem;
  }

  /* ── Subtask progress bar (board cards) ── */
  .subtask-bar-wrap {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-top: 0.5rem;
  }

  .subtask-bar {
    flex: 1;
    height: 3px;
    background: #1E2235;
    border-radius: 2px;
    overflow: hidden;
  }

  .subtask-fill {
    height: 100%;
    background: linear-gradient(90deg, #EC4899, #8B5CF6);
    border-radius: 2px;
    transition: width 0.3s;
  }

  .subtask-count {
    font-size: 0.68rem;
    font-weight: 600;
    color: #475569;
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }

  /* ── Expand button (board card + list row) ── */
  .expand-btn, .row-expand {
    width: 24px;
    height: 24px;
    border-radius: 6px;
    border: 1px solid #252840;
    background: transparent;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    color: #475569;
    transition: all 0.15s;
    flex-shrink: 0;
  }

  .expand-btn:hover, .row-expand:hover { background: #1E2235; color: #8B5CF6; border-color: #8B5CF6; }
  .expand-btn.expanded, .row-expand.expanded { background: rgba(139,92,246,0.12); color: #8B5CF6; border-color: #8B5CF6; }

  .row-expand {
    width: 26px;
    height: 26px;
    margin-right: 0.25rem;
  }

  /* ── Subtask panel (card + list) ── */
  .subtask-panel {
    margin-top: 0.5rem;
    padding-top: 0.625rem;
    border-top: 1px solid #1E2235;
  }

  .subtask-expand-row td { padding: 0; }

  .subtask-expand-cell {
    padding: 0 1rem 0.75rem 3rem !important;
    background: #0D0F1A;
  }

  .subtask-list { display: flex; flex-direction: column; gap: 0.25rem; padding-top: 0.5rem; }

  .subtask-loading {
    font-size: 0.75rem;
    color: #334155;
    padding: 0.5rem 0;
  }

  .subtask-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.25rem 0;
  }

  .sub-check {
    width: 16px;
    height: 16px;
    border-radius: 4px;
    border: 1.5px solid #334155;
    background: transparent;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    flex-shrink: 0;
    transition: all 0.15s;
  }

  .sub-check.sub-done { background: #8B5CF6; border-color: #8B5CF6; }
  .sub-check:hover:not(.sub-done) { border-color: #8B5CF6; }

  .sub-title {
    flex: 1;
    font-size: 0.8rem;
    color: #94A3B8;
  }

  .sub-title-done {
    text-decoration: line-through;
    color: #334155;
  }

  .sub-del {
    background: none;
    border: none;
    cursor: pointer;
    font-size: 0.7rem;
    color: #334155;
    padding: 0.1rem 0.3rem;
    border-radius: 4px;
    transition: all 0.15s;
    flex-shrink: 0;
    opacity: 0;
  }

  .subtask-row:hover .sub-del { opacity: 1; }
  .sub-del:hover { background: rgba(244,63,94,0.15); color: #F43F5E; }

  .subtask-add {
    display: flex;
    gap: 0.4rem;
    margin-top: 0.35rem;
  }

  .subtask-input {
    flex: 1;
    background: #1A1D2E;
    border: 1px solid #252840;
    border-radius: 7px;
    padding: 0.35rem 0.6rem;
    font-size: 0.78rem;
    font-family: inherit;
    color: #E2E8F0;
    outline: none;
    transition: border-color 0.15s;
  }

  .subtask-input::placeholder { color: #2D3148; }
  .subtask-input:focus { border-color: #8B5CF6; }

  .subtask-add-btn {
    width: 26px;
    height: 26px;
    border-radius: 7px;
    border: none;
    background: linear-gradient(135deg, #EC4899, #8B5CF6);
    color: white;
    font-size: 1rem;
    font-weight: 600;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    transition: opacity 0.15s;
  }

  .subtask-add-btn:hover { opacity: 0.85; }

  /* ── List view title cell enhancements ── */
  .title-cell {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
  }

  .row-desc {
    font-size: 0.72rem;
    color: #475569;
    line-height: 1.3;
  }

  .row-subtask-badge {
    font-size: 0.68rem;
    font-weight: 500;
    color: #8B5CF6;
    background: rgba(139,92,246,0.1);
    border-radius: 4px;
    padding: 0.05rem 0.35rem;
    display: inline-block;
    width: fit-content;
  }

  /* ── Modal textarea ── */
  .field-textarea {
    resize: vertical;
    min-height: 70px;
    line-height: 1.5;
  }
</style>

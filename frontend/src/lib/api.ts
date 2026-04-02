const BASE_URL = '/api';

export type Status   = 'todo' | 'in_progress' | 'done';
export type Priority = 'none' | 'low' | 'medium' | 'high' | 'urgent';

export interface Todo {
  id: string;
  title: string;
  isComplete: boolean;
  timeSpent: number;      // seconds
  status: Status;
  priority: Priority;
  dueDate: string | null; // "YYYY-MM-DD" or null
  createdAt: string | null;
}

export interface TaskInput {
  title: string;
  isComplete?: boolean;
  timeSpent?: number;
  status?: Status;
  priority?: Priority;
  dueDate?: string | null;
}

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
  if (res.status === 204) return undefined as unknown as T;
  return res.json() as Promise<T>;
}

export const api = {
  list: () => request<Todo[]>('/todos'),

  create: (data: TaskInput) =>
    request<Todo>('/todos', {
      method: 'POST',
      body: JSON.stringify({
        title:     data.title,
        status:    data.status    ?? 'todo',
        priority:  data.priority  ?? 'none',
        dueDate:   data.dueDate   ?? null,
        timeSpent: 0,
      }),
    }),

  update: (id: string, data: TaskInput) =>
    request<Todo>(`/todos/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),

  delete: (id: string) =>
    request<void>(`/todos/${id}`, { method: 'DELETE' }),

  toggle: (todo: Todo) =>
    api.update(todo.id, {
      title:      todo.title,
      status:     todo.isComplete ? 'todo' : 'done',
      timeSpent:  todo.timeSpent,
      priority:   todo.priority,
    }),
};

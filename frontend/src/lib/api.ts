const BASE_URL = '/api';

export interface Todo {
  id: string;
  title: string;
  isComplete: boolean;
  createdAt: string | null;
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

  create: (title: string) =>
    request<Todo>('/todos', {
      method: 'POST',
      body: JSON.stringify({ title, isComplete: false }),
    }),

  update: (id: string, data: { title: string; isComplete: boolean }) =>
    request<Todo>(`/todos/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),

  delete: (id: string) =>
    request<void>(`/todos/${id}`, { method: 'DELETE' }),

  toggle: (todo: Todo) =>
    api.update(todo.id, { title: todo.title, isComplete: !todo.isComplete }),
};

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { api, type Todo } from './api';

const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

const fakeTodo: Todo = {
	id: 'abc-123',
	title: 'Test todo',
	isComplete: false,
	timeSpent: 0,
	status: 'todo',
	priority: 'none',
	dueDate: null,
	createdAt: null,
};

function makeResponse(data: unknown, status = 200) {
	return {
		ok: status >= 200 && status < 300,
		status,
		json: vi.fn(() => Promise.resolve(data)),
		text: vi.fn(() => Promise.resolve(typeof data === 'string' ? data : JSON.stringify(data))),
	};
}

beforeEach(() => mockFetch.mockReset());

describe('api.list', () => {
	it('fetches todos from /api/todos', async () => {
		mockFetch.mockResolvedValue(makeResponse([fakeTodo]));
		const todos = await api.list();
		expect(todos).toEqual([fakeTodo]);
		expect(mockFetch).toHaveBeenCalledWith('/api/todos', expect.any(Object));
	});

	it('throws with status on error', async () => {
		mockFetch.mockResolvedValue(makeResponse('Internal Server Error', 500));
		await expect(api.list()).rejects.toThrow('HTTP 500');
	});
});

describe('api.create', () => {
	it('posts to /api/todos and returns the new todo', async () => {
		mockFetch.mockResolvedValue(makeResponse(fakeTodo, 201));
		const todo = await api.create({ title: 'Test todo' });
		expect(todo).toEqual(fakeTodo);
		expect(mockFetch).toHaveBeenCalledWith(
			'/api/todos',
			expect.objectContaining({ method: 'POST', body: expect.stringContaining('Test todo') })
		);
	});

	it('throws HTTP 422 when server rejects the title', async () => {
		mockFetch.mockResolvedValue(makeResponse('Title cannot be empty', 422));
		await expect(api.create({ title: '' })).rejects.toThrow('HTTP 422');
	});
});

describe('api.update', () => {
	it('puts to /api/todos/:id', async () => {
		const updated = { ...fakeTodo, title: 'Updated' };
		mockFetch.mockResolvedValue(makeResponse(updated));
		const result = await api.update('abc-123', { title: 'Updated', status: 'todo' as const });
		expect(result.title).toBe('Updated');
		expect(mockFetch).toHaveBeenCalledWith('/api/todos/abc-123', expect.objectContaining({ method: 'PUT' }));
	});
});

describe('api.delete', () => {
	it('sends DELETE to /api/todos/:id', async () => {
		mockFetch.mockResolvedValue({ ok: true, status: 204 });
		await api.delete('abc-123');
		expect(mockFetch).toHaveBeenCalledWith('/api/todos/abc-123', expect.objectContaining({ method: 'DELETE' }));
	});

	it('throws on 404', async () => {
		mockFetch.mockResolvedValue(makeResponse('Not Found', 404));
		await expect(api.delete('missing')).rejects.toThrow('HTTP 404');
	});
});

describe('api.toggle', () => {
	it('flips todo to done (false → true)', async () => {
		const toggled = { ...fakeTodo, isComplete: true, status: 'done' as const };
		mockFetch.mockResolvedValue(makeResponse(toggled));
		const result = await api.toggle(fakeTodo);
		expect(result.isComplete).toBe(true);
		const body = JSON.parse(mockFetch.mock.calls[0][1].body);
		expect(body.status).toBe('done');
	});

	it('flips done to todo (true → false)', async () => {
		const completedTodo = { ...fakeTodo, isComplete: true, status: 'done' as const };
		const toggled = { ...fakeTodo, isComplete: false, status: 'todo' as const };
		mockFetch.mockResolvedValue(makeResponse(toggled));
		const result = await api.toggle(completedTodo);
		expect(result.isComplete).toBe(false);
		const body = JSON.parse(mockFetch.mock.calls[0][1].body);
		expect(body.status).toBe('todo');
	});
});

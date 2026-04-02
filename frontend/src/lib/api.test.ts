import { describe, it, expect, vi, beforeEach } from 'vitest';
import { api } from './api';

const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

const fakeTodo = { id: 'abc-123', title: 'Test todo', isComplete: false, createdAt: null };

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
		const todo = await api.create('Test todo');
		expect(todo).toEqual(fakeTodo);
		expect(mockFetch).toHaveBeenCalledWith(
			'/api/todos',
			expect.objectContaining({ method: 'POST', body: expect.stringContaining('Test todo') })
		);
	});

	it('throws HTTP 422 when server rejects the title', async () => {
		mockFetch.mockResolvedValue(makeResponse('Title cannot be empty', 422));
		await expect(api.create('')).rejects.toThrow('HTTP 422');
	});
});

describe('api.update', () => {
	it('puts to /api/todos/:id', async () => {
		const updated = { ...fakeTodo, title: 'Updated' };
		mockFetch.mockResolvedValue(makeResponse(updated));
		const result = await api.update('abc-123', { title: 'Updated', isComplete: false });
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
	it('flips isComplete from false to true', async () => {
		const toggled = { ...fakeTodo, isComplete: true };
		mockFetch.mockResolvedValue(makeResponse(toggled));
		const result = await api.toggle(fakeTodo);
		expect(result.isComplete).toBe(true);
		const body = JSON.parse(mockFetch.mock.calls[0][1].body);
		expect(body.isComplete).toBe(true);
	});

	it('flips isComplete from true to false', async () => {
		const completedTodo = { ...fakeTodo, isComplete: true };
		const toggled = { ...fakeTodo, isComplete: false };
		mockFetch.mockResolvedValue(makeResponse(toggled));
		const result = await api.toggle(completedTodo);
		expect(result.isComplete).toBe(false);
	});
});

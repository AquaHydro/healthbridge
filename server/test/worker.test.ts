import { exports } from 'cloudflare:workers';
import { describe, expect, it } from 'vitest';

// Contract boundaries: liveness, HEAD semantics, unsupported methods,
// and no accidental exposure of unimplemented health data routes.
describe('Worker HTTP boundary', () => {
  it('reports liveness without exposing configuration', async () => {
    const response = await exports.default.fetch(
      'https://example.test/healthz',
    );
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toBe('application/json');
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(await response.json()).toEqual({ status: 'ok' });
  });

  it('supports HEAD with no body', async () => {
    const response = await exports.default.fetch(
      'https://example.test/healthz',
      {
        method: 'HEAD',
      },
    );
    expect(response.status).toBe(200);
    expect(await response.text()).toBe('');
  });

  it('rejects writes to the liveness endpoint', async () => {
    const response = await exports.default.fetch(
      'https://example.test/healthz',
      {
        method: 'POST',
      },
    );
    expect(response.status).toBe(405);
    expect(response.headers.get('allow')).toBe('GET, HEAD');
    expect(await response.json()).toEqual({ error: 'method_not_allowed' });
  });

  it.each([
    ['GET', '/'],
    ['GET', '/v1/ping'],
    ['POST', '/v1/ingest'],
    ['DELETE', '/v1/data'],
    ['POST', '/mcp'],
    ['GET', '/healthz/nested'],
  ])('keeps unimplemented route %s %s closed', async (method, path) => {
    const response = await exports.default.fetch(
      `https://example.test${path}`,
      {
        method,
      },
    );
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: 'not_found' });
  });
});

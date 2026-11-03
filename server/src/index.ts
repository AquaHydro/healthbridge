import { clear, ingest, status } from './data';
import { mcp } from './mcp';
import { ingestSchema, typeSchema } from './schema';

const MAX_BODY = 10 * 1024 * 1024;
const json = (value: unknown, status = 200) =>
  Response.json(value, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
async function equal(a: string, b: string) {
  const encoder = new TextEncoder();
  const [x, y] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(a)),
    crypto.subtle.digest('SHA-256', encoder.encode(b)),
  ]);
  return crypto.subtle.timingSafeEqual(x, y);
}
async function body(request: Request) {
  if (Number(request.headers.get('content-length') ?? 0) > MAX_BODY)
    throw new RangeError();
  const reader = request.body?.getReader();
  if (!reader) return '';
  const decoder = new TextDecoder();
  let size = 0,
    text = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > MAX_BODY) {
      await reader.cancel();
      throw new RangeError();
    }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}
export default {
  async fetch(
    request: Request,
    env: Env,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url),
      path = url.pathname;
    if (
      !env.INGEST_TOKEN ||
      !env.MCP_TOKEN ||
      (await equal(env.INGEST_TOKEN, env.MCP_TOKEN))
    )
      return json({ error: 'server_not_configured' }, 503);
    const expected = path === '/mcp' ? env.MCP_TOKEN : env.INGEST_TOKEN;
    const auth = request.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ') || !(await equal(auth.slice(7), expected)))
      return json({ error: 'unauthorized' }, 401);
    const origin = request.headers.get('Origin');
    if (origin && origin !== url.origin)
      return json({ error: 'origin_not_allowed' }, 403);
    try {
      if (path === '/mcp') {
        if (request.method === 'POST') {
          const text = await body(request);
          request = new Request(request.url, {
            method: request.method,
            headers: request.headers,
            body: text,
          });
        }
        const response = await mcp(env.DB)(request, env, ctx);
        const headers = new Headers(response.headers);
        headers.set('Cache-Control', 'no-store');
        return new Response(response.body, {
          status: response.status,
          headers,
        });
      }
      if (
        path === '/healthz' &&
        (request.method === 'GET' || request.method === 'HEAD')
      )
        return request.method === 'HEAD'
          ? new Response(null, { headers: { 'Cache-Control': 'no-store' } })
          : json({ status: 'ok' });
      if (
        (path === '/v1/ping' || path === '/v1/status') &&
        request.method === 'GET'
      )
        return json({ ok: true, ...(await status(env.DB)) });
      if (path === '/v1/ingest' && request.method === 'POST') {
        if (
          !request.headers
            .get('content-type')
            ?.toLowerCase()
            .startsWith('application/json')
        )
          return json({ error: 'json_required' }, 415);
        let input: unknown;
        try {
          input = JSON.parse(await body(request));
        } catch (e) {
          if (e instanceof RangeError) throw e;
          return json({ error: 'invalid_json' }, 400);
        }
        if (
          typeof input === 'object' &&
          input !== null &&
          (('added' in input &&
            Array.isArray(input.added) &&
            input.added.length > 1000) ||
            ('deleted' in input &&
              Array.isArray(input.deleted) &&
              input.deleted.length > 5000))
        )
          return json({ error: 'batch_too_large' }, 413);
        const parsed = ingestSchema.safeParse(input);
        if (!parsed.success)
          return json(
            {
              error: 'invalid_batch',
              issues: parsed.error.issues.map((i) => ({
                path: i.path,
                code: i.code,
              })),
            },
            400,
          );
        const { added, deleted, types } = parsed.data;
        await ingest(env.DB, added, deleted, types);
        return json({ ok: true, added: added.length, deleted: deleted.length });
      }
      if (path === '/v1/data' && request.method === 'DELETE') {
        const type = url.searchParams.get('type');
        if (type !== null && !typeSchema.safeParse(type).success)
          return json({ error: 'invalid_type' }, 400);
        await clear(env.DB, type === null ? undefined : typeSchema.parse(type));
        return json({ ok: true });
      }
      return json({ error: 'not_found' }, 404);
    } catch (e) {
      return e instanceof RangeError
        ? json({ error: 'body_too_large' }, 413)
        : json({ error: 'temporarily_unavailable' }, 503);
    }
  },
} satisfies ExportedHandler<Env>;

/** Bootstrap only. Health data routes are added after authentication is implemented. */
export default {
  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path === '/healthz') {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return Response.json(
          { error: 'method_not_allowed' },
          { status: 405, headers: { Allow: 'GET, HEAD' } },
        );
      }
      return new Response(
        request.method === 'HEAD' ? null : JSON.stringify({ status: 'ok' }),
        {
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-store',
          },
        },
      );
    }
    return Response.json({ error: 'not_found' }, { status: 404 });
  },
} satisfies ExportedHandler;

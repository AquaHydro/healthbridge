import { type Sample, type SampleType, types, times } from './schema';

export async function ingest(
  db: D1Database,
  added: Sample[],
  deleted: string[],
  syncedTypes: SampleType[] = [],
) {
  const now = new Date().toISOString();
  // JSON table operations keep large batches within D1's per-invocation statement budget.
  const statements = [
    db
      .prepare(
        `INSERT OR REPLACE INTO samples
    SELECT lower(json_extract(value,'$.uuid')), json_extract(value,'$.type'), json_extract(value,'$.start_ms'),
    json_extract(value,'$.end_ms'), json_extract(value,'$.tz_min'), json_extract(value,'$.value'),
    json_extract(value,'$.unit'), json_extract(value,'$.source'), json_extract(value,'$.device') FROM json_each(?)`,
      )
      .bind(JSON.stringify(added)),
    db
      .prepare(
        'DELETE FROM samples WHERE uuid IN (SELECT lower(value) FROM json_each(?))',
      )
      .bind(JSON.stringify(deleted)),
    db
      .prepare("INSERT OR REPLACE INTO meta VALUES ('last_ingest_at', ?)")
      .bind(now),
  ];
  const touched = new Set([...added.map((s) => s.type), ...syncedTypes]);
  for (const type of touched)
    statements.push(
      db
        .prepare('INSERT OR REPLACE INTO meta VALUES (?, ?)')
        .bind(`last_ingest_at.${type}`, now),
    );
  await db.batch(statements);
}
export async function status(db: D1Database) {
  const [rows, meta] = await db.batch<Record<string, string | number | null>>([
    db.prepare(
      `SELECT s.type, COUNT(*) AS count, MAX(s.end_ms) AS last_sample_ms,
       (SELECT tz_min FROM samples latest WHERE latest.type=s.type ORDER BY latest.end_ms DESC, latest.uuid LIMIT 1) AS tz_min
       FROM samples s GROUP BY s.type`,
    ),
    db.prepare('SELECT key,value FROM meta'),
  ]);
  const metadata = Object.fromEntries(
    (meta!.results as { key: string; value: string }[]).map((r) => [
      r.key,
      r.value,
    ]),
  );
  const result = types.map((type) => {
    const row = rows!.results.find((r) => r.type === type);
    return {
      type,
      count: Number(row?.count ?? 0),
      last_sample: times(
        row ? Number(row.last_sample_ms) : null,
        Number(row?.tz_min ?? 0),
      ),
      last_ingest_at: metadata[`last_ingest_at.${type}`] ?? null,
    };
  });
  return {
    schema_version: 1,
    version: '0.1.0',
    last_ingest_at: metadata.last_ingest_at ?? null,
    types: result,
    counts: Object.fromEntries(result.map((r) => [r.type, r.count])),
  };
}
export async function timezone(db: D1Database, specified?: number) {
  if (specified !== undefined) return specified;
  const row = await db
    .prepare('SELECT tz_min FROM samples ORDER BY end_ms DESC, uuid LIMIT 1')
    .first<{ tz_min: number }>();
  return row?.tz_min ?? 0;
}
export async function clear(db: D1Database, type?: SampleType) {
  if (type)
    await db.batch([
      db.prepare('DELETE FROM samples WHERE type = ?').bind(type),
      db
        .prepare('DELETE FROM meta WHERE key = ?')
        .bind(`last_ingest_at.${type}`),
    ]);
  else
    await db.batch([
      db.prepare('DELETE FROM samples'),
      db.prepare('DELETE FROM meta'),
    ]);
}

/**
 * Thin client for the local DuckDB query API.
 *
 * The Vite dev server proxies /api/* to http://localhost:8000 so this works
 * with no CORS gymnastics. In production you'd front this with something more
 * substantial; for laptop use it's fine.
 */

export async function runQuery(sql) {
  const response = await fetch('/api/query', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sql }),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || `HTTP ${response.status}`);
  }
  return response.json();
}

export async function fetchHealth() {
  const response = await fetch('/api/health');
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

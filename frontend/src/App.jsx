import { useEffect, useState } from 'react';
import { fetchHealth, runQuery } from './api.js';
import { PRESETS } from './queries.js';
import ResultTable from './components/ResultTable.jsx';
import LineChart from './components/LineChart.jsx';

export default function App() {
  const [activePresetId, setActivePresetId] = useState(PRESETS[0].id);
  const [sql, setSql] = useState(PRESETS[0].sql);
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [stats, setStats] = useState(null);
  const [bucket, setBucket] = useState('');

  useEffect(() => {
    fetchHealth()
      .then((h) => setBucket(h.table_bucket_arn || ''))
      .catch((e) => setError(`API not reachable. Is the local server running? (${e.message})`));
  }, []);

  function chooseSql(preset) {
    setActivePresetId(preset.id);
    setSql(preset.sql);
    setResult(null);
    setError(null);
    setStats(null);
  }

  async function execute() {
    setRunning(true);
    setError(null);
    setResult(null);
    setStats(null);
    const started = performance.now();
    try {
      const data = await runQuery(sql);
      const elapsedMs = Math.round(performance.now() - started);
      setResult(data);
      setStats({ elapsedMs, rows: data.rows.length });
    } catch (e) {
      setError(e.message);
    } finally {
      setRunning(false);
    }
  }

  return (
    <div className="app">
      <header className="header">
        <h1>OpenAQ Lakehouse</h1>
        <span className="meta">{bucket || 'connecting...'}</span>
      </header>
      <div className="body">
        <aside className="sidebar">
          <h3>Pre-canned queries</h3>
          {PRESETS.map((p) => (
            <button
              key={p.id}
              className={p.id === activePresetId ? 'active' : ''}
              onClick={() => chooseSql(p)}
            >
              {p.label}
            </button>
          ))}
        </aside>
        <main className="main">
          <section className="editor-pane">
            <textarea value={sql} onChange={(e) => setSql(e.target.value)} spellCheck={false} />
          </section>
          <div className="toolbar">
            <button onClick={execute} disabled={running}>
              {running ? 'Running...' : 'Run query (Cmd+Enter)'}
            </button>
            {stats && (
              <span className="stats">
                {stats.rows.toLocaleString()} rows in {stats.elapsedMs} ms
              </span>
            )}
          </div>
          <section className="results-pane" onKeyDown={(e) => {
            if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') execute();
          }}>
            {error && <pre className="error">{error}</pre>}
            {!error && !result && <div className="empty">Pick a query and hit Run.</div>}
            {result && (
              <>
                <ResultTable columns={result.columns} rows={result.rows} />
                {activePresetId === 'pm25_trend' && (
                  <LineChart
                    rows={result.rows}
                    columns={result.columns}
                    xKey="day"
                    yKey="avg_pm25"
                  />
                )}
              </>
            )}
          </section>
        </main>
      </div>
    </div>
  );
}

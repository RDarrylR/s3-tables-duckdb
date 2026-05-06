/**
 * Minimal SVG line chart. Avoids dependencies for a "simple local frontend".
 */
export default function LineChart({ rows, xKey, yKey }) {
  if (!rows.length) return null;

  const width = 720;
  const height = 220;
  const margin = { top: 16, right: 24, bottom: 32, left: 56 };
  const innerW = width - margin.left - margin.right;
  const innerH = height - margin.top - margin.bottom;

  const xs = rows.map((r) => new Date(r[xKey]).getTime());
  const ys = rows.map((r) => Number(r[yKey])).filter((v) => Number.isFinite(v));
  if (!ys.length) return null;

  const xMin = Math.min(...xs);
  const xMax = Math.max(...xs);
  const yMin = Math.min(...ys);
  const yMax = Math.max(...ys);

  const xScale = (v) => margin.left + ((v - xMin) / Math.max(1, xMax - xMin)) * innerW;
  const yScale = (v) => margin.top + innerH - ((v - yMin) / Math.max(1e-9, yMax - yMin)) * innerH;

  const points = rows
    .filter((r) => Number.isFinite(Number(r[yKey])))
    .map((r) => `${xScale(new Date(r[xKey]).getTime())},${yScale(Number(r[yKey]))}`)
    .join(' ');

  return (
    <div className="chart">
      <svg width={width} height={height} role="img" aria-label={`Line chart of ${yKey} over ${xKey}`}>
        <line x1={margin.left} y1={margin.top + innerH} x2={margin.left + innerW} y2={margin.top + innerH} stroke="currentColor" strokeOpacity="0.2" />
        <line x1={margin.left} y1={margin.top} x2={margin.left} y2={margin.top + innerH} stroke="currentColor" strokeOpacity="0.2" />
        <text x={margin.left} y={margin.top - 4} fontSize="11" opacity="0.6">{yKey}</text>
        <text x={margin.left + innerW} y={margin.top + innerH + 18} fontSize="11" opacity="0.6" textAnchor="end">{xKey}</text>
        <text x={margin.left - 6} y={margin.top + innerH + 4} fontSize="10" opacity="0.6" textAnchor="end">{yMin.toFixed(1)}</text>
        <text x={margin.left - 6} y={margin.top + 10} fontSize="10" opacity="0.6" textAnchor="end">{yMax.toFixed(1)}</text>
        <polyline points={points} fill="none" stroke="#007cbd" strokeWidth="2" />
      </svg>
    </div>
  );
}

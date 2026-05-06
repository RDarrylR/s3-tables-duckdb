export default function ResultTable({ columns, rows }) {
  if (!rows.length) {
    return <div className="empty">No rows.</div>;
  }
  return (
    <table>
      <thead>
        <tr>
          {columns.map((c) => (
            <th key={c.name} className={isNumber(c.type) ? 'num' : ''}>
              {c.name}
              <span style={{ opacity: 0.4, marginLeft: 6, fontSize: 11 }}>{c.type}</span>
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.slice(0, 500).map((row, i) => (
          <tr key={i}>
            {columns.map((c) => (
              <td key={c.name} className={isNumber(c.type) ? 'num' : ''}>
                {formatCell(row[c.name], c.type)}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function isNumber(t) {
  return /int|float|double|decimal|long/i.test(t || '');
}

function formatCell(value, type) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'number') {
    if (Number.isInteger(value)) return value.toLocaleString();
    return value.toFixed(2);
  }
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}/.test(value)) {
    return value.replace('T', ' ').replace(/\.\d+/, '');
  }
  return String(value);
}

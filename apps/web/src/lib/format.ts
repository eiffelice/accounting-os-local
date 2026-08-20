export function formatThb(value: string | null | undefined) {
  if (value == null) return '-';
  const match = /^(-?)(\d+)(?:\.(\d+))?$/.exec(value);
  if (!match) throw new Error('invalid decimal money value');
  const [, sign, whole, rawFraction = ''] = match;
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const fraction = rawFraction.padEnd(2, '0').slice(0, 2);
  return `${sign}฿${grouped}.${fraction}`;
}

export function formatThaiDate(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) return value;
  const buddhistYear = String(Number(match[1]) + 543);
  return `${match[3]}/${match[2]}/${buddhistYear}`;
}

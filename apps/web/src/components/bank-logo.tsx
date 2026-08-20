type BankLogoProps = {
  slug?: string | null;
  color?: string | null;
  name?: string | null;
  kind?: string | null;
  small?: boolean;
};

const SAFE_SLUG = /^[a-z0-9]+$/;
const SAFE_COLOR = /^#[0-9a-f]{6}$/i;

function fallbackLabel(kind?: string | null) {
  if (kind === 'CASH') return '฿';
  if (kind === 'CREDIT_CARD') return 'CC';
  if (kind === 'E_WALLET') return 'W';
  return 'B';
}

function needsContrast(color: string) {
  const red = Number.parseInt(color.slice(1, 3), 16);
  const green = Number.parseInt(color.slice(3, 5), 16);
  const blue = Number.parseInt(color.slice(5, 7), 16);
  return (red * 299 + green * 587 + blue * 114) / 1000 > 190;
}

export function BankLogo({ slug, color, name, kind, small = false }: BankLogoProps) {
  const safeSlug = slug && SAFE_SLUG.test(slug) ? slug : null;
  const safeColor = color && SAFE_COLOR.test(color) ? color : '#ffffff';
  const sizeClass = small ? ' bankLogoSmall' : '';
  const contrastClass = needsContrast(safeColor) ? ' bankLogoNeedsContrast' : '';
  const classes = `accountIcon bankLogo${sizeClass}${contrastClass}`;

  if (!safeSlug) {
    return <span className={`${classes} bankLogoFallback`} aria-hidden="true">{fallbackLabel(kind)}</span>;
  }

  return (
    <span className={classes} style={{ backgroundColor: safeColor }} title={name ?? undefined}>
      <img
        src={`/bank-logos/${safeSlug}.svg`}
        alt={name ? `โลโก้ ${name}` : 'โลโก้ธนาคาร'}
        width={small ? 20 : 26}
        height={small ? 20 : 26}
        loading="lazy"
        decoding="async"
      />
    </span>
  );
}

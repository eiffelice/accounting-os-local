import { BankLogo } from './bank-logo';

type FinancialAccount = {
  id: string;
  kind: string;
  name: string;
  masked_number: string | null;
  bank_slug: string | null;
  bank_name: string | null;
  bank_brand_color: string | null;
};

export function FinancialAccountPicker({
  accounts,
  legend,
}: {
  accounts: FinancialAccount[];
  legend: string;
}) {
  return (
    <fieldset className="accountPicker">
      <legend>{legend}</legend>
      <div className="accountChoices">
        {accounts.map((account) => (
          <label className="accountChoice" key={account.id}>
            <input type="radio" name="financialAccountId" value={account.id} required/>
            <BankLogo
              slug={account.bank_slug}
              color={account.bank_brand_color}
              name={account.bank_name}
              kind={account.kind}
              small
            />
            <span>
              <b>{account.name}</b>
              <small>{account.bank_name ?? account.kind} · {account.masked_number ?? '-'}</small>
            </span>
          </label>
        ))}
        {accounts.length === 0 ? <span className="emptyState">ยังไม่มีบัญชีการเงิน</span> : null}
      </div>
    </fieldset>
  );
}

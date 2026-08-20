'use client';

import { useState } from 'react';
import { BankLogo } from './bank-logo';

type Bank = {
  slug: string;
  name: string;
  brand_color: string;
};

export function FinancialAccountForm({ companyId, banks }: { companyId: string; banks: Bank[] }) {
  const [kind, setKind] = useState('BANK');
  const [bankSlug, setBankSlug] = useState('');
  const selectedBank = banks.find((bank) => bank.slug === bankSlug);

  return (
    <form className="formStack" action="/api/companies/account" method="post">
      <input type="hidden" name="companyId" value={companyId}/>
      <label>ประเภท
        <select
          name="kind"
          value={kind}
          onChange={(event) => {
            const nextKind = event.target.value;
            setKind(nextKind);
            if (nextKind === 'CASH') setBankSlug('');
          }}
        >
          <option value="BANK">ธนาคาร</option>
          <option value="CASH">เงินสด</option>
          <option value="E_WALLET">E-Wallet</option>
          <option value="CREDIT_CARD">บัตรเครดิต</option>
        </select>
      </label>
      <label>ธนาคาร
        <span className="bankSelectRow">
          <BankLogo
            slug={selectedBank?.slug}
            color={selectedBank?.brand_color}
            name={selectedBank?.name}
            kind={kind}
          />
          <select
            name="bankSlug"
            value={bankSlug}
            onChange={(event) => setBankSlug(event.target.value)}
            required={kind === 'BANK'}
            disabled={kind === 'CASH'}
          >
            <option value="">ไม่ระบุ</option>
            {banks.map((bank) => (
              <option key={bank.slug} value={bank.slug}>{bank.name}</option>
            ))}
          </select>
        </span>
      </label>
      <label>ชื่อบัญชี<input name="name" required maxLength={160}/></label>
      <label>สถาบัน/ผู้ให้บริการอื่น
        <input
          name="institution"
          maxLength={120}
          disabled={Boolean(selectedBank)}
          placeholder={selectedBank?.name ?? undefined}
        />
      </label>
      <label>เลขที่ Mask แล้ว<input name="maskedNumber" placeholder="XXX-X-X1234-X" maxLength={80}/></label>
      <button className="primaryBtn" type="submit">เพิ่มบัญชี</button>
    </form>
  );
}

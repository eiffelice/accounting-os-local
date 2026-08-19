import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import * as z from 'zod/v4';

import {
  assertCompanyAccess,
  createExpenseDraft,
  getActorByEmail,
  listCompanies,
  listFinancialAccounts,
  recentJournals,
  trialBalance,
} from '@accounting-os/db';

const actorEmail =
  process.env.ACCOUNTING_ACTOR_EMAIL ?? 'owner@local.accounting';

async function actor() {
  const user = await getActorByEmail(actorEmail);
  if (!user) throw new Error(`Configured actor not found: ${actorEmail}`);
  return user;
}

function asText(data: unknown) {
  return {
    content: [{ type: 'text' as const, text: JSON.stringify(data, null, 2) }],
  };
}

function buildServer() {
  const server = new McpServer({
    name: 'accounting-os-local',
    version: '0.2.0',
  });

  server.registerTool(
    'company_list',
    {
      description:
        'List local companies the configured employee can read. Never invent company IDs.',
      inputSchema: z.object({}),
    },
    async () => {
      const u = await actor();
      const companies = await listCompanies();
      const allowed = [];
      for (const company of companies) {
        try {
          await assertCompanyAccess(u.id, company.id, 'read');
          allowed.push(company);
        } catch {}
      }
      return asText(allowed);
    }
  );

  server.registerTool(
    'financial_account_list',
    {
      description:
        'List masked bank/cash/e-wallet/credit-card accounts for one authorized company.',
      inputSchema: z.object({ companyId: z.string().uuid() }),
    },
    async ({ companyId }) => {
      const u = await actor();
      await assertCompanyAccess(u.id, companyId, 'read');
      return asText(await listFinancialAccounts(companyId));
    }
  );

  server.registerTool(
    'report_trial_balance',
    {
      description:
        'Return a trial balance derived only from the canonical posted ledger.',
      inputSchema: z.object({ companyId: z.string().uuid() }),
    },
    async ({ companyId }) => {
      const u = await actor();
      await assertCompanyAccess(u.id, companyId, 'read');
      return asText(await trialBalance(companyId));
    }
  );

  server.registerTool(
    'journal_recent',
    {
      description: 'List recent journals for one authorized company. Read-only.',
      inputSchema: z.object({
        companyId: z.string().uuid(),
        limit: z.number().int().min(1).max(50).default(10),
      }),
    },
    async ({ companyId, limit }) => {
      const u = await actor();
      await assertCompanyAccess(u.id, companyId, 'read');
      return asText(await recentJournals(companyId, limit));
    }
  );

  server.registerTool(
    'expense_create_draft',
    {
      description:
        'Create a balanced expense DRAFT locally. Never posts, pays, files tax, or reads secrets. Human approval is required.',
      inputSchema: z.object({
        companyId: z.string().uuid(),
        financialAccountId: z.string().uuid(),
        expenseAccountCode: z.string().min(1).max(30),
        amount: z.number().positive().max(1000000000),
        txnDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        description: z.string().min(1).max(500),
        idempotencyKey: z.string().min(8).max(200),
      }),
    },
    async (input) => {
      const u = await actor();
      const result = await createExpenseDraft({
        actorId: u.id,
        ...input,
        sourceType: 'AI_MCP_DRAFT',
      });
      return asText({
        ...result,
        status: 'DRAFT',
        approval: 'PENDING',
        warning: 'Human approval and human posting are required.',
      });
    }
  );

  return server;
}

void serveStdio(buildServer);
console.error('Accounting OS Local v0.2 MCP running over stdio');

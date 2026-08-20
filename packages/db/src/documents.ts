import { pool } from './base.ts';
import { assertCompanyAccess } from './access.ts';

export async function insertLocalDocument(
  actorId: string,
  companyId: string,
  input: {
    originalName: string;
    storedName: string;
    mimeType: string;
    sizeBytes: number;
    sha256: string;
    relativePath: string;
  }
) {
  await assertCompanyAccess(actorId, companyId, 'create_draft');
  const { rows } = await pool.query(
    `INSERT INTO local_documents(
       company_id, original_name, stored_name, mime_type, size_bytes, sha256,
       local_relative_path, uploaded_by
     ) VALUES($1,$2,$3,$4,$5,$6,$7,$8)
     RETURNING id`,
    [
      companyId, input.originalName, input.storedName, input.mimeType, input.sizeBytes,
      input.sha256, input.relativePath, actorId
    ]
  );
  await pool.query(
    `INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
     VALUES($1,$2,'DOCUMENT_UPLOADED','local_document',$3,$4::jsonb)`,
    [companyId, actorId, rows[0].id, JSON.stringify({
      originalName: input.originalName,
      sha256: input.sha256,
      sizeBytes: input.sizeBytes,
    })]
  );
  return rows[0].id as string;
}

export async function listLocalDocuments(companyId: string) {
  const { rows } = await pool.query(
    `SELECT d.id, d.original_name, d.mime_type, d.size_bytes, d.sha256, d.uploaded_at,
            u.display_name AS uploaded_by_name
     FROM local_documents d
     JOIN app_users u ON u.id=d.uploaded_by
     WHERE d.company_id=$1
     ORDER BY d.uploaded_at DESC`,
    [companyId]
  );
  return rows;
}

export async function listAuditEvents(companyId: string, limit = 100) {
  const { rows } = await pool.query(
    `SELECT ae.id, ae.event_type, ae.resource_type, ae.resource_id, ae.payload,
            ae.occurred_at, u.display_name AS actor_name, u.email AS actor_email
     FROM audit_events ae
     LEFT JOIN app_users u ON u.id=ae.actor_user_id
     WHERE ae.company_id=$1
     ORDER BY ae.occurred_at DESC
     LIMIT $2`,
    [companyId, Math.max(1, Math.min(500, limit))]
  );
  return rows;
}

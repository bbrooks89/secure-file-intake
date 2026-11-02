/**
 * Pure validation logic for partner eligibility files.
 * No AWS calls here, so it is fast to unit test.
 *
 * Expected format: CSV with a header row containing at least
 *   member_id,first_name,last_name,dob,plan_code
 */

export const REQUIRED_COLUMNS = ['member_id', 'first_name', 'last_name', 'dob', 'plan_code'] as const;
export const MAX_FILE_BYTES = 10 * 1024 * 1024; // 10 MB

export interface RowError {
  line: number; // 1-based line number in the file (header is line 1)
  message: string;
}

export interface ValidationResult {
  valid: boolean;
  rowCount: number; // data rows, excluding header
  errors: RowError[];
}

const MEMBER_ID = /^[A-Za-z0-9]{6,20}$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_REPORTED_ERRORS = 50;

function isRealDate(value: string): boolean {
  if (!ISO_DATE.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().startsWith(value) && d.getTime() <= Date.now();
}

export function validateCsv(content: string, sizeBytes: number = Buffer.byteLength(content)): ValidationResult {
  const errors: RowError[] = [];
  const fail = (line: number, message: string) => {
    if (errors.length < MAX_REPORTED_ERRORS) errors.push({ line, message });
  };

  if (sizeBytes === 0 || content.trim() === '') {
    return { valid: false, rowCount: 0, errors: [{ line: 0, message: 'File is empty' }] };
  }
  if (sizeBytes > MAX_FILE_BYTES) {
    return { valid: false, rowCount: 0, errors: [{ line: 0, message: `File exceeds ${MAX_FILE_BYTES} bytes` }] };
  }

  const lines = content.replace(/\r\n/g, '\n').split('\n').filter((l, i, all) => !(l === '' && i === all.length - 1));
  const header = lines[0].split(',').map((h) => h.trim().toLowerCase());

  const missing = REQUIRED_COLUMNS.filter((c) => !header.includes(c));
  if (missing.length > 0) {
    return { valid: false, rowCount: 0, errors: [{ line: 1, message: `Missing required columns: ${missing.join(', ')}` }] };
  }

  const idx = Object.fromEntries(REQUIRED_COLUMNS.map((c) => [c, header.indexOf(c)])) as Record<(typeof REQUIRED_COLUMNS)[number], number>;
  const seenIds = new Set<string>();
  let rowCount = 0;

  for (let i = 1; i < lines.length; i++) {
    const lineNo = i + 1;
    if (lines[i].trim() === '') {
      fail(lineNo, 'Blank line');
      continue;
    }
    rowCount++;
    const cols = lines[i].split(',').map((c) => c.trim());
    if (cols.length !== header.length) {
      fail(lineNo, `Expected ${header.length} columns, found ${cols.length}`);
      continue;
    }
    const memberId = cols[idx.member_id];
    if (!MEMBER_ID.test(memberId)) fail(lineNo, 'member_id must be 6-20 letters or digits');
    else if (seenIds.has(memberId)) fail(lineNo, 'Duplicate member_id');
    else seenIds.add(memberId);

    if (!cols[idx.first_name]) fail(lineNo, 'first_name is required');
    if (!cols[idx.last_name]) fail(lineNo, 'last_name is required');
    if (!isRealDate(cols[idx.dob])) fail(lineNo, 'dob must be a past date in YYYY-MM-DD format');
    if (!cols[idx.plan_code]) fail(lineNo, 'plan_code is required');
  }

  if (rowCount === 0) fail(1, 'File has a header but no data rows');

  return { valid: errors.length === 0, rowCount, errors };
}

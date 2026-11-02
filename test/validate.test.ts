import { validateCsv, MAX_FILE_BYTES } from '../lambda/validate';

const HEADER = 'member_id,first_name,last_name,dob,plan_code';

describe('validateCsv', () => {
  test('accepts a well-formed file', () => {
    const csv = `${HEADER}\nABC12345,Ana,Lopez,1980-04-12,PPO1\nXYZ98765,Sam,Lee,1975-11-30,HMO2\n`;
    const r = validateCsv(csv);
    expect(r.valid).toBe(true);
    expect(r.rowCount).toBe(2);
    expect(r.errors).toHaveLength(0);
  });

  test('handles Windows line endings', () => {
    const r = validateCsv(`${HEADER}\r\nABC12345,Ana,Lopez,1980-04-12,PPO1\r\n`);
    expect(r.valid).toBe(true);
  });

  test('rejects an empty file', () => {
    expect(validateCsv('').valid).toBe(false);
  });

  test('rejects a file over the size limit', () => {
    const r = validateCsv(`${HEADER}\nABC12345,Ana,Lopez,1980-04-12,PPO1`, MAX_FILE_BYTES + 1);
    expect(r.valid).toBe(false);
    expect(r.errors[0].message).toMatch(/exceeds/);
  });

  test('rejects a header missing required columns', () => {
    const r = validateCsv('member_id,first_name\nABC12345,Ana');
    expect(r.valid).toBe(false);
    expect(r.errors[0].message).toMatch(/last_name, dob, plan_code/);
  });

  test('rejects header-only files', () => {
    expect(validateCsv(`${HEADER}\n`).valid).toBe(false);
  });

  test('flags bad rows with line numbers', () => {
    const csv = [
      HEADER,
      'ABC12345,Ana,Lopez,1980-04-12,PPO1',
      'bad id!,Sam,Lee,1975-11-30,HMO2', // line 3: invalid member_id
      'XYZ98765,,Lee,1975-02-30,HMO2', // line 4: missing first_name, impossible date
      'ABC12345,Ana,Lopez,1980-04-12,PPO1', // line 5: duplicate
      'QQQ11111,Too,Few', // line 6: column count
    ].join('\n');
    const r = validateCsv(csv);
    expect(r.valid).toBe(false);
    const lines = r.errors.map((e) => e.line);
    expect(lines).toEqual(expect.arrayContaining([3, 4, 5, 6]));
    expect(r.errors.find((e) => e.line === 4 && /dob/.test(e.message))).toBeDefined();
    expect(r.errors.find((e) => e.line === 5 && /Duplicate/.test(e.message))).toBeDefined();
  });

  test('rejects future dates of birth', () => {
    const r = validateCsv(`${HEADER}\nABC12345,Ana,Lopez,2999-01-01,PPO1`);
    expect(r.valid).toBe(false);
  });
});

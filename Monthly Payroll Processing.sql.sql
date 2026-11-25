DROP SCHEMA IF EXISTS q6 CASCADE; CREATE SCHEMA q6; SET search_path TO q6;

CREATE TABLE employees (
  employee_id SERIAL PRIMARY KEY, full_name VARCHAR(100) NOT NULL,
  basic_salary NUMERIC(12,2) NOT NULL CHECK (basic_salary >= 0),
  allowance NUMERIC(12,2) NOT NULL CHECK (allowance >= 0),
  deduction NUMERIC(12,2) NOT NULL CHECK (deduction >= 0),
  active BOOLEAN NOT NULL DEFAULT TRUE);
CREATE TABLE payroll (
  payroll_id SERIAL PRIMARY KEY, employee_id INT NOT NULL REFERENCES employees,
  pay_month DATE NOT NULL CHECK (EXTRACT(DAY FROM pay_month) = 1),
  gross_pay NUMERIC(12,2) NOT NULL, net_pay NUMERIC(12,2) NOT NULL,
  CONSTRAINT uq_emp_month UNIQUE (employee_id, pay_month));
CREATE TABLE salary_audit (
  audit_id SERIAL PRIMARY KEY, employee_id INT NOT NULL REFERENCES employees,
  old_salary NUMERIC(12,2) NOT NULL, new_salary NUMERIC(12,2) NOT NULL,
  changed_at TIMESTAMP NOT NULL DEFAULT now());

CREATE FUNCTION fn_net_pay(p_employee_id INT) RETURNS NUMERIC AS $$
DECLARE b NUMERIC; a NUMERIC; d NUMERIC; n NUMERIC;
BEGIN
  SELECT basic_salary, allowance, deduction INTO b, a, d FROM employees WHERE employee_id = p_employee_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown employee %', p_employee_id; END IF;
  n := b + a - d;
  IF n < 0 THEN RAISE EXCEPTION 'Negative net pay % for employee %', n, p_employee_id; END IF;
  RETURN n;
END $$ LANGUAGE plpgsql STABLE;

CREATE PROCEDURE pr_process_payroll(p_month DATE) LANGUAGE plpgsql AS $$
DECLARE rec RECORD; v_net NUMERIC;
BEGIN
  IF p_month IS NULL OR EXTRACT(DAY FROM p_month) <> 1 THEN
    RAISE EXCEPTION 'p_month must be the first day of a month'; END IF;
  FOR rec IN SELECT employee_id, basic_salary, allowance FROM employees WHERE active ORDER BY employee_id LOOP
    v_net := fn_net_pay(rec.employee_id);
    INSERT INTO payroll(employee_id, pay_month, gross_pay, net_pay)
    VALUES (rec.employee_id, p_month, rec.basic_salary + rec.allowance, v_net)
    ON CONFLICT (employee_id, pay_month) DO NOTHING;
  END LOOP;
END $$;

CREATE FUNCTION trg_fn_salary_audit() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO salary_audit(employee_id, old_salary, new_salary)
  VALUES (OLD.employee_id, OLD.basic_salary, NEW.basic_salary);
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_salary_audit AFTER UPDATE ON employees FOR EACH ROW
WHEN (OLD.basic_salary IS DISTINCT FROM NEW.basic_salary) EXECUTE FUNCTION trg_fn_salary_audit();

INSERT INTO employees(full_name, basic_salary, allowance, deduction, active) VALUES
 ('Alinani Mushi',8000,1500,1200,TRUE), ('Brenda Kunda',6500,1000,900,TRUE),
 ('Charles Nyirenda',7200,800,1000,TRUE), ('Dorothy Lungu',5000,500,700,TRUE),
 ('Edwin Phiri',4000,300,500,FALSE);
CALL pr_process_payroll(DATE '2026-09-01');
CALL pr_process_payroll(DATE '2026-10-01');
UPDATE employees SET active = FALSE WHERE employee_id = 4;

CREATE VIEW v_payroll_report AS
SELECT e.full_name, p.pay_month, p.gross_pay, p.net_pay
  FROM payroll p JOIN employees e ON e.employee_id = p.employee_id;

CREATE INDEX idx_payroll_month ON payroll(pay_month);
EXPLAIN SELECT * FROM v_payroll_report WHERE pay_month = DATE '2026-10-01';

SELECT cron.schedule('q6_process_payroll', '0 2 1 * *',
  $$SET search_path TO q6;
    CALL pr_process_payroll((date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date)$$);
SELECT jobid, jobname, schedule, command, active FROM cron.job WHERE jobname = 'q6_process_payroll';
SELECT runid, status, return_message, start_time, end_time FROM cron.job_run_details
 WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'q6_process_payroll') ORDER BY start_time DESC;

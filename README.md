# Question 6: Monthly Payroll Processing

PostgreSQL. Run `solution.sql` from top to bottom. It creates its own schema `q6`.
Scheduled jobs use pg_cron.

## Index
`payroll(pay_month)`

The existing unique index is (employee_id, pay_month). pay_month is its second column, so it cannot efficiently serve a report filtered only by pay_month. A separate single-column index on pay_month fixes that without duplicating the unique index.

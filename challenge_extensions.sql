-- challenge_extensions.sql
-- Optional Challenge Extensions for Lab 3

-- ============================================================
-- Tier 1 — Complex Analytics Queries
-- ============================================================

-- 1) At-risk projects
-- Projects where total allocated hours exceed 80% of project budget
SELECT
    p.project_id,
    p.name AS project_name,
    p.budget,
    COALESCE(SUM(pa.hours_allocated), 0) AS total_allocated_hours,
    ROUND(
        (COALESCE(SUM(pa.hours_allocated), 0) * 100.0) / NULLIF(p.budget, 0),
        2
    ) AS utilization_pct
FROM projects p
LEFT JOIN project_assignments pa
    ON p.project_id = pa.project_id
GROUP BY p.project_id, p.name, p.budget
HAVING COALESCE(SUM(pa.hours_allocated), 0) > (p.budget * 0.8)
ORDER BY utilization_pct DESC;


-- 2) Cross-department analysis
-- NOTE:
-- Your actual schema does NOT have projects.department_id.
-- To support this extension exactly as requested, we add it first.

ALTER TABLE projects
ADD COLUMN IF NOT EXISTS department_id INT;

ALTER TABLE projects
DROP CONSTRAINT IF EXISTS projects_department_id_fkey;

ALTER TABLE projects
ADD CONSTRAINT projects_department_id_fkey
FOREIGN KEY (department_id) REFERENCES departments(department_id);

-- Example backfill for project ownership
-- You can adjust these mappings later if needed.
UPDATE projects
SET department_id = CASE name
    WHEN 'AI Recommendation Engine' THEN 7
    WHEN 'API Gateway Redesign' THEN 1
    WHEN 'Blockchain Pilot' THEN 7
    WHEN 'Cloud Infrastructure Migration' THEN 1
    WHEN 'Customer Feedback Analytics' THEN 5
    WHEN 'Customer Portal Redesign' THEN 8
    WHEN 'Cybersecurity Audit' THEN 6
    WHEN 'Data Warehouse Migration' THEN 7
    WHEN 'ERP System Upgrade' THEN 6
    WHEN 'Employee Training Portal' THEN 4
    WHEN 'Marketing Automation Platform' THEN 5
    WHEN 'Mobile App Launch' THEN 5
    WHEN 'Quantum Computing Research' THEN 7
    WHEN 'Regional Expansion Analytics' THEN 3
    WHEN 'Supply Chain Optimization' THEN 6
    ELSE department_id
END
WHERE department_id IS NULL;

-- Now the exact query becomes possible
SELECT
    e.employee_id,
    e.first_name,
    e.last_name,
    d_emp.name AS employee_department,
    p.name AS project_name,
    d_proj.name AS project_department,
    pa.role,
    pa.hours_allocated
FROM employees e
JOIN departments d_emp
    ON e.department_id = d_emp.department_id
JOIN project_assignments pa
    ON e.employee_id = pa.employee_id
JOIN projects p
    ON pa.project_id = p.project_id
JOIN departments d_proj
    ON p.department_id = d_proj.department_id
WHERE e.department_id <> p.department_id
ORDER BY e.last_name, e.first_name, p.name;


-- ============================================================
-- Tier 2 — Dynamic Reporting with Views and Functions
-- ============================================================

-- 1) Department summary view
CREATE OR REPLACE VIEW department_summary_view AS
SELECT
    d.department_id,
    d.name AS department_name,
    d.location,
    COUNT(e.employee_id) AS employee_count,
    COALESCE(SUM(e.salary), 0) AS total_salary,
    COALESCE(AVG(e.salary), 0) AS avg_salary
FROM departments d
LEFT JOIN employees e
    ON d.department_id = e.department_id
GROUP BY d.department_id, d.name, d.location;

SELECT * FROM department_summary_view
ORDER BY total_salary DESC;


-- 2) Project status view
CREATE OR REPLACE VIEW project_status_view AS
SELECT
    p.project_id,
    p.name AS project_name,
    p.start_date,
    p.end_date,
    p.budget,
    COUNT(pa.employee_id) AS employee_count,
    COALESCE(SUM(pa.hours_allocated), 0) AS total_hours_allocated,
    ROUND(
        (COALESCE(SUM(pa.hours_allocated), 0) * 100.0) / NULLIF(p.budget, 0),
        2
    ) AS utilization_pct,
    CASE
        WHEN COALESCE(SUM(pa.hours_allocated), 0) > p.budget * 0.8 THEN 'At Risk'
        WHEN COALESCE(SUM(pa.hours_allocated), 0) = 0 THEN 'Not Staffed'
        ELSE 'On Track'
    END AS project_status
FROM projects p
LEFT JOIN project_assignments pa
    ON p.project_id = pa.project_id
GROUP BY p.project_id, p.name, p.start_date, p.end_date, p.budget;

SELECT * FROM project_status_view
ORDER BY utilization_pct DESC;


-- 3) Materialized view example
DROP MATERIALIZED VIEW IF EXISTS department_summary_mv;

CREATE MATERIALIZED VIEW department_summary_mv AS
SELECT
    d.department_id,
    d.name AS department_name,
    d.location,
    COUNT(e.employee_id) AS employee_count,
    COALESCE(SUM(e.salary), 0) AS total_salary,
    COALESCE(AVG(e.salary), 0) AS avg_salary
FROM departments d
LEFT JOIN employees e
    ON d.department_id = e.department_id
GROUP BY d.department_id, d.name, d.location;

-- Refresh when needed
REFRESH MATERIALIZED VIEW department_summary_mv;

SELECT * FROM department_summary_mv
ORDER BY total_salary DESC;


-- 4) Function returning JSON
-- Requires projects.department_id to count projects by department
CREATE OR REPLACE FUNCTION get_department_snapshot(dept_name_input TEXT)
RETURNS JSON AS
$$
DECLARE
    result JSON;
BEGIN
    SELECT json_build_object(
        'department_name', d.name,
        'employee_count', COUNT(DISTINCT e.employee_id),
        'total_salary', COALESCE(SUM(e.salary), 0),
        'active_projects', COUNT(DISTINCT CASE
            WHEN p.end_date IS NULL OR p.end_date >= CURRENT_DATE THEN p.project_id
        END)
    )
    INTO result
    FROM departments d
    LEFT JOIN employees e
        ON d.department_id = e.department_id
    LEFT JOIN projects p
        ON d.department_id = p.department_id
    WHERE d.name = dept_name_input
    GROUP BY d.department_id, d.name;

    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Call from psql
SELECT get_department_snapshot('Engineering');


-- ============================================================
-- Tier 3 — Schema Evolution and Migration
-- ============================================================

-- 1) Salary history table
DROP TABLE IF EXISTS salary_history;

CREATE TABLE salary_history (
    salary_history_id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL,
    salary_amount NUMERIC(10,2) NOT NULL CHECK (salary_amount > 0),
    effective_date DATE NOT NULL,
    end_date DATE,
    change_reason VARCHAR(100) DEFAULT 'Initial Load',
    CONSTRAINT salary_history_employee_fk
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);

-- 2) Migration script
-- Populate one initial record per employee from current employees table
INSERT INTO salary_history (employee_id, salary_amount, effective_date, end_date, change_reason)
SELECT
    employee_id,
    salary,
    hire_date,
    NULL,
    'Initial Migration'
FROM employees;

-- 3) Add more realistic historical records (2–3 per employee sample)
-- Example for a subset; you can expand later if you want
INSERT INTO salary_history (employee_id, salary_amount, effective_date, end_date, change_reason)
VALUES
    (1, 90000, '2023-01-10', '2024-02-13', 'Annual Raise'),
    (1, 98000, '2024-02-14', NULL, 'Promotion'),
    (2, 85000, '2022-01-15', '2023-12-31', 'Initial Salary'),
    (2, 92000, '2024-01-01', NULL, 'Annual Raise'),
    (3, 65000, '2022-03-01', '2023-12-31', 'Initial Salary'),
    (3, 72000, '2024-01-01', NULL, 'Annual Raise');

-- Optional cleanup for overlapping records in the sample subset
-- Keep this commented unless you want stricter history control
-- UPDATE salary_history
-- SET end_date = '2022-01-14'
-- WHERE employee_id = 2 AND effective_date = '2022-01-15';


-- 4) Salary growth rate by department over time
WITH dept_salary_over_time AS (
    SELECT
        d.name AS department_name,
        DATE_TRUNC('year', sh.effective_date) AS salary_year,
        AVG(sh.salary_amount) AS avg_salary
    FROM salary_history sh
    JOIN employees e
        ON sh.employee_id = e.employee_id
    JOIN departments d
        ON e.department_id = d.department_id
    GROUP BY d.name, DATE_TRUNC('year', sh.effective_date)
),
salary_growth AS (
    SELECT
        department_name,
        salary_year,
        avg_salary,
        LAG(avg_salary) OVER (
            PARTITION BY department_name
            ORDER BY salary_year
        ) AS previous_avg_salary
    FROM dept_salary_over_time
)
SELECT
    department_name,
    salary_year,
    avg_salary,
    previous_avg_salary,
    ROUND(
        ((avg_salary - previous_avg_salary) * 100.0) / NULLIF(previous_avg_salary, 0),
        2
    ) AS growth_rate_pct
FROM salary_growth
ORDER BY department_name, salary_year;


-- 5) Employees due for salary review
-- No salary change in the last 12 months
WITH latest_salary_change AS (
    SELECT
        e.employee_id,
        e.first_name,
        e.last_name,
        d.name AS department_name,
        MAX(sh.effective_date) AS last_change_date
    FROM employees e
    JOIN departments d
        ON e.department_id = d.department_id
    JOIN salary_history sh
        ON e.employee_id = sh.employee_id
    GROUP BY e.employee_id, e.first_name, e.last_name, d.name
)
SELECT
    employee_id,
    first_name,
    last_name,
    department_name,
    last_change_date
FROM latest_salary_change
WHERE last_change_date < CURRENT_DATE - INTERVAL '12 months'
ORDER BY last_change_date ASC;


-- ============================================================
-- Tier 3 — Brief Analysis
-- ============================================================

-- Production migration notes:
-- 1. Create the new table first without disrupting existing reads/writes.
-- 2. Backfill historical data in batches to avoid locking and long-running transactions.
-- 3. Add indexes after initial load if large volume is expected.
-- 4. Validate row counts and salary totals after migration.
-- 5. Update application logic to write to both employees and salary_history during cutover.
-- 6. Risks include inconsistent backfill, duplicate history rows, incorrect effective dates,
--    and performance impact during migration.
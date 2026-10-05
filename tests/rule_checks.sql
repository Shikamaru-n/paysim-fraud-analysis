/*
===============================================================================
Rule Checks
===============================================================================
Script Purpose:
    This script proves that the frozen detection rules in 'gold.rule_flags'
    only use what they are allowed to use. It checks that:
    - The rule view reads no balance column, no mismatch flag and no fraud
      label, and reads nothing outside the four gold objects it is allowed to.
    - The objects it depends on are clean in the same way.
    - The flags equal the rules as written in plain English in
      docs/findings.md, when worked out again from scratch.
    - The destination history only counts transactions in strictly earlier
      steps: nothing from the same step, nothing from later steps.

Usage Notes:
    - Run these checks after: EXEC gold.load_gold;
    - Investigate and resolve any discrepancies found during the checks.
    - This is synthetic data.
===============================================================================
*/

-- ====================================================================
-- Checking what 'gold.rule_flags' reads
-- ====================================================================
-- sys.dm_sql_referenced_entities is SQL Server's own list of every object and
-- column a view reads. The checks below read that list.

-- For information: every object and column the rule view reads
-- Expectation: only the type, amount, zero amount flag, hour slot, destination
--              history and the keys needed to join them
SELECT
    referenced_schema_name AS schema_name,
    referenced_entity_name AS object_name,
    referenced_minor_name  AS column_name
FROM sys.dm_sql_referenced_entities('gold.rule_flags', 'OBJECT')
WHERE referenced_minor_name IS NOT NULL
ORDER BY schema_name, object_name, column_name;

-- Check the rule view reads only the objects it is allowed to
-- Anything else is a failure, including silver.paysim_transactions and
-- gold.fact_transaction_balances.
-- Expectation: No Results
SELECT DISTINCT
    referenced_schema_name AS schema_name,
    referenced_entity_name AS object_that_should_not_be_read
FROM sys.dm_sql_referenced_entities('gold.rule_flags', 'OBJECT')
WHERE referenced_schema_name != 'gold'
   OR referenced_entity_name NOT IN (
        'fact_transactions', 'fact_destination_history', 'dim_time', 'dim_transaction_type'
      );

-- Check the rule view reads no balance column, no mismatch flag and no label
-- is_fraud is the true label. is_flagged_fraud is the existing rule's verdict.
-- Expectation: No Results
SELECT
    referenced_entity_name AS object_name,
    referenced_minor_name  AS column_that_should_not_be_read
FROM sys.dm_sql_referenced_entities('gold.rule_flags', 'OBJECT')
WHERE referenced_minor_name LIKE '%balance%'
   OR referenced_minor_name LIKE '%mismatch%'
   OR referenced_minor_name IN ('is_fraud', 'is_flagged_fraud');

-- ====================================================================
-- Checking what the rule view depends on
-- ====================================================================
-- Check gold.fact_transactions reads no balance column or mismatch flag
-- It does carry is_fraud, which is needed to score rules. The check above
-- proves the rule view does not read it.
-- Expectation: No Results
SELECT
    referenced_entity_name AS object_name,
    referenced_minor_name  AS column_that_should_not_be_read
FROM sys.dm_sql_referenced_entities('gold.fact_transactions', 'OBJECT')
WHERE referenced_minor_name LIKE '%balance%'
   OR referenced_minor_name LIKE '%mismatch%';

-- Check gold.load_gold builds the gold tables without balances or labels
-- This covers gold.fact_destination_history, which the rules read.
-- Expectation: No Results
SELECT
    referenced_entity_name AS object_name,
    referenced_minor_name  AS column_that_should_not_be_read
FROM sys.dm_sql_referenced_entities('gold.load_gold', 'OBJECT')
WHERE referenced_minor_name LIKE '%balance%'
   OR referenced_minor_name LIKE '%mismatch%'
   OR referenced_minor_name IN ('is_fraud', 'is_flagged_fraud');

-- ====================================================================
-- Checking the flags against the documented rules
-- ====================================================================
-- The three rules are worked out again here from their plain-English
-- definitions in docs/findings.md, question 10. This is written independently
-- of the view: it reads the silver table directly, takes the hour slot
-- straight from the step, and decides "new destination" a different way.
--
-- New destination, the other way: find the first step in which each
-- destination account ever received anything. A transaction goes to a new
-- destination when its own step is that first step, because then nothing
-- reached the account in any earlier step.
--
-- The rules, as documented:
--   Chosen rule : a CASH_OUT of 800,000 or more, or of zero, or in hour slots
--                 0 to 6; or a TRANSFER to a new destination that is in hour
--                 slots 0 to 6 or is 5,000,000 or more
--   No-hour rule: a CASH_OUT of 800,000 or more, or of zero; or a TRANSFER to
--                 a new destination of 1,500,000 or more
--   Wider rule  : a CASH_OUT of 800,000 or more, or of zero, or in hour slots
--                 0 to 7; or a TRANSFER to a new destination
--
-- Expectation: 2,770,409 rows compared, and 0 in all three difference columns
SELECT
    COUNT(*) AS rows_compared,
    SUM(CASE WHEN r.is_flagged_chosen_rule  != e.expected_chosen_rule  THEN 1 ELSE 0 END) AS chosen_rule_differences,
    SUM(CASE WHEN r.is_flagged_no_hour_rule != e.expected_no_hour_rule THEN 1 ELSE 0 END) AS no_hour_rule_differences,
    SUM(CASE WHEN r.is_flagged_wider_rule   != e.expected_wider_rule   THEN 1 ELSE 0 END) AS wider_rule_differences
FROM gold.rule_flags r
INNER JOIN (
    SELECT
        transaction_id,
        CASE
            WHEN transaction_type = 'CASH_OUT' AND amount >= 800000                              THEN 1
            WHEN transaction_type = 'CASH_OUT' AND amount = 0                                    THEN 1
            WHEN transaction_type = 'CASH_OUT' AND hour_of_day BETWEEN 0 AND 6                   THEN 1
            WHEN transaction_type = 'TRANSFER' AND goes_to_new_destination = 1
                                               AND hour_of_day BETWEEN 0 AND 6                   THEN 1
            WHEN transaction_type = 'TRANSFER' AND goes_to_new_destination = 1
                                               AND amount >= 5000000                             THEN 1
            ELSE 0
        END AS expected_chosen_rule,
        CASE
            WHEN transaction_type = 'CASH_OUT' AND amount >= 800000                              THEN 1
            WHEN transaction_type = 'CASH_OUT' AND amount = 0                                    THEN 1
            WHEN transaction_type = 'TRANSFER' AND goes_to_new_destination = 1
                                               AND amount >= 1500000                             THEN 1
            ELSE 0
        END AS expected_no_hour_rule,
        CASE
            WHEN transaction_type = 'CASH_OUT' AND amount >= 800000                              THEN 1
            WHEN transaction_type = 'CASH_OUT' AND amount = 0                                    THEN 1
            WHEN transaction_type = 'CASH_OUT' AND hour_of_day BETWEEN 0 AND 7                   THEN 1
            WHEN transaction_type = 'TRANSFER' AND goes_to_new_destination = 1                   THEN 1
            ELSE 0
        END AS expected_wider_rule
    FROM (
        SELECT
            s.transaction_id,
            s.transaction_type,
            s.amount,
            (s.step - 1) % 24 AS hour_of_day,
            CASE
                WHEN s.step = d.first_step_received THEN 1
                ELSE 0
            END AS goes_to_new_destination
        FROM silver.paysim_transactions s
        INNER JOIN (
            SELECT
                destination_account,
                MIN(step) AS first_step_received
            FROM silver.paysim_transactions
            GROUP BY destination_account
        ) d
            ON d.destination_account = s.destination_account
        WHERE s.transaction_type IN ('TRANSFER', 'CASH_OUT')
    ) t
) e
    ON e.transaction_id = r.transaction_id;

-- ====================================================================
-- Checking 'gold.fact_destination_history' uses earlier steps only
-- ====================================================================
-- Cut-off check: the history is worked out again from data that stops at step
-- 360 (the end of the build period), and compared with the stored values for
-- steps 1 to 360. If any later transaction had influenced an earlier value,
-- taking the later transactions away would change it.
-- Expectation: 5,186,057 rows compared, 0 differences
SELECT
    COUNT(*) AS rows_compared,
    SUM(CASE WHEN h.destination_prior_transactions != c.prior_from_cut_off_data THEN 1 ELSE 0 END) AS differences
FROM gold.fact_destination_history h
INNER JOIN (
    SELECT
        transaction_id,
        RANK() OVER (PARTITION BY destination_account ORDER BY step) - 1 AS prior_from_cut_off_data
    FROM silver.paysim_transactions
    WHERE step <= 360
) c
    ON c.transaction_id = h.transaction_id;

-- Same-step check: when a destination receives several transactions in one
-- step, they must all carry the same count. If they did not, transactions in
-- the same step would be counting each other.
-- Expectation: No Results
SELECT
    s.destination_account,
    s.step,
    COUNT(*)                              AS transactions_in_step,
    MIN(h.destination_prior_transactions) AS lowest_count,
    MAX(h.destination_prior_transactions) AS highest_count
FROM silver.paysim_transactions s
INNER JOIN gold.fact_destination_history h
    ON h.transaction_id = s.transaction_id
GROUP BY s.destination_account, s.step
HAVING MIN(h.destination_prior_transactions) != MAX(h.destination_prior_transactions);

-- A third check, a sample recount done the slow and obvious way, is in
-- tests/quality_checks_gold.sql.

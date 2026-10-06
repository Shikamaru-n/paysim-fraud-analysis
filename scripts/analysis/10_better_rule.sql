/*
===============================================================================
Analysis 10: A Better Detection Rule
===============================================================================
Business Question:
    Can a better SQL rule catch more fraud without flagging too many honest
    customers?

Script Purpose:
    Part 1 scores candidate rules on the BUILD PERIOD ONLY (days 1 to 15), to
    choose a rule.

    Part 2, at the end of the script, scores the three frozen rules once on
    the test period (days 16 to 30).

    Selection criterion, decided before any rule was scored:
        Catch as much fraud as possible (highest recall) while flagging no
        more than 0.5% of honest TRANSFER and CASH_OUT transactions in the
        build period. The best rule at 0.1% and at 1% is also reported.

    Candidate rules:
        1. The existing flag (baseline)
        2. Amount only, CASH_OUT
        3. Hour only, both types
        4. Amount or hour
        5. Hour and amount together, as a grid of cells
        6. Rules that do not use the hour at all
        7. Destination history: how many transactions the destination account
           had received in strictly earlier steps
        8. A second operating point outside the 0.5% cap (not the
           recommendation)

    The three rules frozen from this work are defined in the view
    gold.rule_flags and scored by the view gold.report_rule_performance.

Usage Notes:
    - Run after the Gold Layer is created and loaded.
    - Rules are scored on TRANSFER and CASH_OUT transactions only, because
      these are the only types with fraud. The existing flag is scored on the
      same basis here, so the rules can be compared.
    - Every query in Part 1 reads build-period rows only. The test period is
      not touched in this part.
    - Rules use the transaction's own type, amount and hour, and for rule 7
      the destination's history from earlier steps. No balance columns, no
      fraud label, nothing from the same step or later steps.
    - The hour signal is probably an artifact of the simulation. See
      docs/findings.md, question 4.
    - This is synthetic data. The results describe a simulation.
===============================================================================
*/

SET NOCOUNT ON;

-- ====================================================================
-- Step 1: Build-period summary
-- ====================================================================
-- One scan of the fact, kept in a small temporary table, so every candidate
-- rule below can be scored without scanning 6.36 million rows again.
-- One row per type, hour slot, amount step and destination history group.
-- amount_floor is the bottom of the amount step the transaction falls in:
--     steps of 10,000 below 1 million       (0, 10000, 20000, ...)
--     steps of 100,000 from 1 to 10 million (1000000, 1100000, ...)
--     10000000 for 10 million and over
-- is_new_destination is 1 when the destination account had received nothing
-- in earlier steps.
IF OBJECT_ID('tempdb..#build_summary') IS NOT NULL
    DROP TABLE #build_summary;

SELECT
    transaction_type,
    hour_slot,
    amount_floor,
    is_zero_amount,
    is_new_destination,
    COUNT(*)                         AS total_transactions,
    SUM(is_fraud)                    AS fraud_transactions,
    SUM(is_flagged_fraud)            AS existing_flagged,
    SUM(is_flagged_fraud * is_fraud) AS existing_caught
INTO #build_summary
FROM (
    SELECT
        ty.transaction_type,
        dt.hour_slot,
        f.is_zero_amount,
        f.is_fraud,
        f.is_flagged_fraud,
        CASE
            WHEN h.destination_prior_transactions = 0 THEN 1
            ELSE 0
        END AS is_new_destination,
        CASE
            WHEN f.amount >= 10000000 THEN 10000000
            WHEN f.amount >= 1000000  THEN CAST(FLOOR(f.amount / 100000) * 100000 AS INT)
            ELSE CAST(FLOOR(f.amount / 10000) * 10000 AS INT)
        END AS amount_floor
    FROM gold.fact_transactions f
    LEFT JOIN gold.fact_destination_history h
        ON f.transaction_id = h.transaction_id
    LEFT JOIN gold.dim_time dt
        ON f.time_key = dt.time_key
    LEFT JOIN gold.dim_transaction_type ty
        ON f.transaction_type_key = ty.transaction_type_key
    WHERE dt.rule_period = 'build'
      AND ty.transaction_type IN ('TRANSFER', 'CASH_OUT')
) t
GROUP BY transaction_type, hour_slot, amount_floor, is_zero_amount, is_new_destination;

-- The totals every rule is measured against, and what each cap allows
DECLARE @build_fraud INT, @build_honest INT;

SELECT
    @build_fraud  = SUM(fraud_transactions),
    @build_honest = SUM(total_transactions) - SUM(fraud_transactions)
FROM #build_summary;

SELECT
    @build_fraud                       AS build_fraud_transactions,
    @build_honest                      AS build_honest_transactions,
    CAST(@build_honest * 0.001 AS INT) AS honest_allowed_at_0_1_pct,
    CAST(@build_honest * 0.005 AS INT) AS honest_allowed_at_0_5_pct,
    CAST(@build_honest * 0.010 AS INT) AS honest_allowed_at_1_pct;

-- ====================================================================
-- Step 2: Score the candidate rules
-- ====================================================================
-- Each rule adds one row per variant to #rule_scores: how many transactions it
-- flags and how many of those are fraud. The rates are worked out at the end.
IF OBJECT_ID('tempdb..#rule_scores') IS NOT NULL
    DROP TABLE #rule_scores;

CREATE TABLE #rule_scores (
    rule_name        NVARCHAR(200),
    flagged          INT,
    caught           INT,
    round_thresholds INT DEFAULT 0 -- 1 when every threshold is a multiple of 100,000 (only set for rule 6d)
);

-- Rule 1: the existing flag (baseline)
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '1: existing flag',
    SUM(existing_flagged),
    SUM(existing_caught)
FROM #build_summary;

-- Rule 2: amount only, CASH_OUT
-- Flag a cash-out when its amount is at or above a threshold, or is zero.
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '2: CASH_OUT >= ' + CAST(th.threshold AS NVARCHAR) + ' or zero',
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    VALUES (200000), (300000), (400000), (500000), (600000), (700000),
           (800000), (900000), (1000000), (2000000), (5000000)
) th (threshold)
WHERE s.transaction_type = 'CASH_OUT'
  AND (s.amount_floor >= th.threshold OR s.is_zero_amount = 1)
GROUP BY th.threshold;

-- Rule 3: hour only, both types
-- Flag every transfer and cash-out in hour slots 0 to k.
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '3: hour slot 0 to ' + CAST(hr.last_slot AS NVARCHAR),
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    VALUES (3), (4), (5), (6), (7), (8)
) hr (last_slot)
WHERE s.hour_slot <= hr.last_slot
GROUP BY hr.last_slot;

-- Rule 4: amount or hour
-- Flag when rule 2 or rule 3 would flag.
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '4: CASH_OUT >= ' + CAST(th.threshold AS NVARCHAR) + ' or zero, or hour slot 0 to ' + CAST(hr.last_slot AS NVARCHAR),
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    VALUES (400000), (500000), (600000), (700000), (800000), (900000), (1000000)
) th (threshold)
CROSS JOIN (
    VALUES (5), (6), (7), (8)
) hr (last_slot)
WHERE (s.transaction_type = 'CASH_OUT' AND (s.amount_floor >= th.threshold OR s.is_zero_amount = 1))
   OR s.hour_slot <= hr.last_slot
GROUP BY th.threshold, hr.last_slot;

-- ====================================================================
-- Rule 5: hour and amount together, as a grid of cells
-- ====================================================================
-- Each cell is one type, one group of hours and one coarse amount band.
-- To avoid fitting the rule to noise:
--     - the hour groups and amount bands are kept coarse
--     - a cell is only eligible if it has at least 30 fraud rows in the
--       build period
-- Eligible cells are taken in order of fraud rate, best first, and added up.
-- The rule for a cap is every cell down to the last row that stays within it.
-- The same cells are split by destination history as well, for rule 7 below.
IF OBJECT_ID('tempdb..#grid_cells') IS NOT NULL
    DROP TABLE #grid_cells;

SELECT
    transaction_type,
    hour_group,
    amount_band,
    is_new_destination,
    SUM(total_transactions)                           AS total_transactions,
    SUM(fraud_transactions)                           AS fraud_transactions,
    SUM(total_transactions) - SUM(fraud_transactions) AS honest_transactions
INTO #grid_cells
FROM (
    SELECT
        transaction_type,
        is_new_destination,
        total_transactions,
        fraud_transactions,
        CASE
            WHEN hour_slot <= 1  THEN '1: slots 0 to 1'
            WHEN hour_slot <= 5  THEN '2: slots 2 to 5'
            WHEN hour_slot <= 7  THEN '3: slots 6 to 7'
            WHEN hour_slot <= 19 THEN '4: slots 8 to 19'
            ELSE                      '5: slots 20 to 23'
        END AS hour_group,
        CASE
            WHEN amount_floor < 100000  THEN '1: under 100k'
            WHEN amount_floor < 500000  THEN '2: 100k to 500k'
            WHEN amount_floor < 1000000 THEN '3: 500k to 1m'
            ELSE                             '4: 1m and over'
        END AS amount_band
    FROM #build_summary
) t
GROUP BY transaction_type, hour_group, amount_band, is_new_destination;

-- Rule 5 cells: type, hour group and amount band (destination history ignored)
IF OBJECT_ID('tempdb..#grid_ranked') IS NOT NULL
    DROP TABLE #grid_ranked;

SELECT
    transaction_type,
    hour_group,
    amount_band,
    total_transactions,
    fraud_transactions,
    honest_transactions,
    CAST(fraud_transactions * 100.0 / total_transactions AS DECIMAL(7,4)) AS fraud_rate_pct,
    SUM(total_transactions) OVER (ORDER BY fraud_transactions * 1.0 / total_transactions DESC, total_transactions
                                  ROWS UNBOUNDED PRECEDING) AS running_flagged,
    SUM(fraud_transactions) OVER (ORDER BY fraud_transactions * 1.0 / total_transactions DESC, total_transactions
                                  ROWS UNBOUNDED PRECEDING) AS running_caught,
    SUM(honest_transactions) OVER (ORDER BY fraud_transactions * 1.0 / total_transactions DESC, total_transactions
                                   ROWS UNBOUNDED PRECEDING) AS running_honest
INTO #grid_ranked
FROM (
    SELECT
        transaction_type,
        hour_group,
        amount_band,
        SUM(total_transactions)  AS total_transactions,
        SUM(fraud_transactions)  AS fraud_transactions,
        SUM(honest_transactions) AS honest_transactions
    FROM #grid_cells
    GROUP BY transaction_type, hour_group, amount_band
) c
WHERE fraud_transactions >= 30;

-- Rule 5 at each cap: every eligible cell down to the last one within the cap
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '5: grid of hour and amount cells, cap ' + cap.label,
    MAX(g.running_flagged),
    MAX(g.running_caught)
FROM #grid_ranked g
CROSS JOIN (
    VALUES (0.001, '0.1%'), (0.005, '0.5%'), (0.010, '1%')
) cap (cap_share, label)
WHERE g.running_honest <= @build_honest * cap.cap_share
GROUP BY cap.label;

-- ====================================================================
-- Rule 6: rules that do not use the hour
-- ====================================================================
-- These are the rules to fall back on if the hour signal does not carry over
-- to real data. They use the amount only, and no destination history.
-- 6a: CASH_OUT at or above a threshold (or zero), with the threshold tried in
--     steps of 10,000 from 500,000 to 1,000,000
-- 6b: 6a, or a TRANSFER at or above a second threshold
-- 6c: 6a, or a TRANSFER under 10,000
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '6a: no hour, CASH_OUT >= ' + CAST(th.threshold AS NVARCHAR) + ' or zero',
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    SELECT DISTINCT amount_floor AS threshold
    FROM #build_summary
    WHERE amount_floor BETWEEN 500000 AND 1000000
) th
WHERE s.transaction_type = 'CASH_OUT'
  AND (s.amount_floor >= th.threshold OR s.is_zero_amount = 1)
GROUP BY th.threshold;

INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '6b: no hour, CASH_OUT >= ' + CAST(th.threshold AS NVARCHAR) + ' or zero, or TRANSFER >= ' + CAST(tt.threshold AS NVARCHAR),
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    SELECT DISTINCT amount_floor AS threshold
    FROM #build_summary
    WHERE amount_floor BETWEEN 500000 AND 1000000
) th
CROSS JOIN (
    VALUES (1000000), (2000000), (3000000), (5000000), (8000000), (10000000)
) tt (threshold)
WHERE (s.transaction_type = 'CASH_OUT' AND (s.amount_floor >= th.threshold OR s.is_zero_amount = 1))
   OR (s.transaction_type = 'TRANSFER' AND s.amount_floor >= tt.threshold)
GROUP BY th.threshold, tt.threshold;

INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '6c: no hour, CASH_OUT >= ' + CAST(th.threshold AS NVARCHAR) + ' or zero, or TRANSFER under 10000',
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    SELECT DISTINCT amount_floor AS threshold
    FROM #build_summary
    WHERE amount_floor BETWEEN 500000 AND 1000000
) th
WHERE (s.transaction_type = 'CASH_OUT' AND (s.amount_floor >= th.threshold OR s.is_zero_amount = 1))
   OR (s.transaction_type = 'TRANSFER' AND s.amount_floor < 10000)
GROUP BY th.threshold;

-- 6d: no hour, but with destination history
-- "No hour" does not mean "no history". This is 6a, or a TRANSFER to a new
-- destination at or above a second threshold. Destination history is explained
-- under rule 7 below.
INSERT INTO #rule_scores (rule_name, flagged, caught, round_thresholds)
SELECT
    '6d: no hour, CASH_OUT >= ' + CAST(th.threshold AS NVARCHAR) + ' or zero, or TRANSFER to a new destination >= ' + CAST(tt.threshold AS NVARCHAR),
    SUM(s.total_transactions),
    SUM(s.fraud_transactions),
    CASE WHEN th.threshold % 100000 = 0 THEN 1 ELSE 0 END
FROM #build_summary s
CROSS JOIN (
    SELECT DISTINCT amount_floor AS threshold
    FROM #build_summary
    WHERE amount_floor BETWEEN 500000 AND 1000000
) th
CROSS JOIN (
    VALUES (0), (100000), (200000), (300000), (400000), (500000), (600000), (700000), (800000),
           (900000), (1000000), (1500000), (2000000), (2500000), (3000000), (4000000), (5000000),
           (7500000), (10000000)
) tt (threshold)
WHERE (s.transaction_type = 'CASH_OUT' AND (s.amount_floor >= th.threshold OR s.is_zero_amount = 1))
   OR (s.transaction_type = 'TRANSFER' AND s.is_new_destination = 1 AND s.amount_floor >= tt.threshold)
GROUP BY th.threshold, tt.threshold;

-- ====================================================================
-- Rule 7: destination history
-- ====================================================================
-- First, what the feature looks like: fraud rate for new and known
-- destinations, by type.
SELECT
    transaction_type,
    CASE
        WHEN is_new_destination = 1 THEN 'new destination'
        ELSE 'received before'
    END                     AS destination_history,
    SUM(total_transactions) AS total_transactions,
    SUM(fraud_transactions) AS fraud_transactions,
    CAST(SUM(fraud_transactions) * 100.0 / SUM(total_transactions) AS DECIMAL(7,4)) AS fraud_rate_pct
FROM #build_summary
GROUP BY transaction_type, is_new_destination
ORDER BY transaction_type, is_new_destination DESC;

-- 7a: the feature alone
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '7a: TRANSFER to a new destination',
    SUM(total_transactions),
    SUM(fraud_transactions)
FROM #build_summary
WHERE transaction_type = 'TRANSFER'
  AND is_new_destination = 1;

INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '7a: TRANSFER or CASH_OUT to a new destination',
    SUM(total_transactions),
    SUM(fraud_transactions)
FROM #build_summary
WHERE is_new_destination = 1;

-- 7b: TRANSFER to a new destination, at or above an amount threshold
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '7b: TRANSFER to a new destination >= ' + CAST(th.threshold AS NVARCHAR),
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    VALUES (100000), (200000), (300000), (400000), (500000), (600000), (700000),
           (800000), (900000), (1000000), (2000000), (5000000)
) th (threshold)
WHERE s.transaction_type = 'TRANSFER'
  AND s.is_new_destination = 1
  AND s.amount_floor >= th.threshold
GROUP BY th.threshold;

-- 7c: the chosen rule, or 7b
-- Chosen rule: CASH_OUT >= 800000 or zero, or any transfer or cash-out in
-- hour slots 0 to 6.
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '7c: chosen rule, or TRANSFER to a new destination >= ' + CAST(th.threshold AS NVARCHAR),
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    VALUES (0), (100000), (200000), (300000), (400000), (500000), (600000), (700000),
           (800000), (900000), (1000000), (2000000), (5000000)
) th (threshold)
WHERE (s.transaction_type = 'CASH_OUT' AND (s.amount_floor >= 800000 OR s.is_zero_amount = 1))
   OR s.hour_slot <= 6
   OR (s.transaction_type = 'TRANSFER' AND s.is_new_destination = 1 AND s.amount_floor >= th.threshold)
GROUP BY th.threshold;

-- 7d: the no-hour rule, or 7b
-- No-hour rule: CASH_OUT >= 700000 or zero.
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '7d: no-hour rule, or TRANSFER to a new destination >= ' + CAST(th.threshold AS NVARCHAR),
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    VALUES (0), (100000), (200000), (300000), (400000), (500000), (600000), (700000),
           (800000), (900000), (1000000), (2000000), (5000000)
) th (threshold)
WHERE (s.transaction_type = 'CASH_OUT' AND (s.amount_floor >= 700000 OR s.is_zero_amount = 1))
   OR (s.transaction_type = 'TRANSFER' AND s.is_new_destination = 1 AND s.amount_floor >= th.threshold)
GROUP BY th.threshold;

-- 7e: the chosen rule with its hour part limited to new destinations for
-- transfers, or 7b
-- Transfers to a destination that has received before are almost never fraud,
-- so flagging them by hour alone spends the honest-customer allowance for
-- nothing. This variant stops doing that.
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '7e: CASH_OUT >= 800000 or zero, or CASH_OUT in slots 0 to 6, or TRANSFER to a new destination in slots 0 to 6 or >= ' + CAST(th.threshold AS NVARCHAR),
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    VALUES (0), (100000), (200000), (300000), (400000), (500000), (600000), (700000),
           (800000), (900000), (1000000), (2000000), (5000000)
) th (threshold)
WHERE (s.transaction_type = 'CASH_OUT' AND (s.amount_floor >= 800000 OR s.is_zero_amount = 1 OR s.hour_slot <= 6))
   OR (s.transaction_type = 'TRANSFER' AND s.is_new_destination = 1 AND (s.hour_slot <= 6 OR s.amount_floor >= th.threshold))
GROUP BY th.threshold;

-- 7f: the grid from rule 5, with every cell also split by destination history
-- Same coarse bands and the same minimum of 30 fraud rows per cell.
IF OBJECT_ID('tempdb..#history_ranked') IS NOT NULL
    DROP TABLE #history_ranked;

SELECT
    transaction_type,
    hour_group,
    amount_band,
    is_new_destination,
    total_transactions,
    fraud_transactions,
    honest_transactions,
    CAST(fraud_transactions * 100.0 / total_transactions AS DECIMAL(7,4)) AS fraud_rate_pct,
    SUM(total_transactions) OVER (ORDER BY fraud_transactions * 1.0 / total_transactions DESC, total_transactions
                                  ROWS UNBOUNDED PRECEDING) AS running_flagged,
    SUM(fraud_transactions) OVER (ORDER BY fraud_transactions * 1.0 / total_transactions DESC, total_transactions
                                  ROWS UNBOUNDED PRECEDING) AS running_caught,
    SUM(honest_transactions) OVER (ORDER BY fraud_transactions * 1.0 / total_transactions DESC, total_transactions
                                   ROWS UNBOUNDED PRECEDING) AS running_honest
INTO #history_ranked
FROM #grid_cells
WHERE fraud_transactions >= 30;

SELECT
    transaction_type,
    hour_group,
    amount_band,
    CASE
        WHEN is_new_destination = 1 THEN 'new destination'
        ELSE 'received before'
    END AS destination_history,
    total_transactions,
    fraud_transactions,
    fraud_rate_pct,
    running_caught,
    running_honest,
    CAST(running_caught * 100.0 / @build_fraud AS DECIMAL(7,4))  AS running_recall_pct,
    CAST(running_honest * 100.0 / @build_honest AS DECIMAL(7,4)) AS running_false_positive_rate_pct
FROM #history_ranked
ORDER BY running_flagged;

INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '7f: grid of hour, amount and destination history cells, cap ' + cap.label,
    MAX(g.running_flagged),
    MAX(g.running_caught)
FROM #history_ranked g
CROSS JOIN (
    VALUES (0.001, '0.1%'), (0.005, '0.5%'), (0.010, '1%')
) cap (cap_share, label)
WHERE g.running_honest <= @build_honest * cap.cap_share
GROUP BY cap.label;

-- ====================================================================
-- Rule 8: a second operating point, outside the 0.5% cap
-- ====================================================================
-- Rule 7 shows that most transfer fraud goes to new destinations, but flagging
-- all of those transfers costs far more than 0.5% of honest customers.
-- This rule takes that cost on purpose, to show what a looser cap of about 3%
-- would buy. It is NOT the recommended rule.
-- Flag: CASH_OUT at or above a threshold (or zero), or CASH_OUT in hour slots
-- 0 to k, or any TRANSFER to a new destination.
INSERT INTO #rule_scores (rule_name, flagged, caught)
SELECT
    '8: CASH_OUT >= ' + CAST(th.threshold AS NVARCHAR) + ' or zero, or CASH_OUT in slots 0 to ' + CAST(hr.last_slot AS NVARCHAR) + ', or any TRANSFER to a new destination',
    SUM(s.total_transactions),
    SUM(s.fraud_transactions)
FROM #build_summary s
CROSS JOIN (
    VALUES (500000), (600000), (700000), (800000), (900000), (1000000)
) th (threshold)
CROSS JOIN (
    VALUES (5), (6), (7), (8)
) hr (last_slot)
WHERE (s.transaction_type = 'CASH_OUT' AND (s.amount_floor >= th.threshold OR s.is_zero_amount = 1 OR s.hour_slot <= hr.last_slot))
   OR (s.transaction_type = 'TRANSFER' AND s.is_new_destination = 1)
GROUP BY th.threshold, hr.last_slot;

-- ====================================================================
-- Step 3: Compare the candidates
-- ====================================================================
-- precision           : of the rows the rule flagged, the share that are fraud
-- recall              : of the fraud rows, the share the rule flagged
-- false positive rate : of the honest rows, the share the rule flagged
IF OBJECT_ID('tempdb..#rule_results') IS NOT NULL
    DROP TABLE #rule_results;

SELECT
    rule_name,
    flagged,
    caught,
    flagged - caught                                                 AS honest_flagged,
    CAST(caught * 100.0 / NULLIF(flagged, 0) AS DECIMAL(7,4))        AS precision_pct,
    CAST(caught * 100.0 / @build_fraud AS DECIMAL(7,4))              AS recall_pct,
    CAST((flagged - caught) * 100.0 / @build_honest AS DECIMAL(7,4)) AS false_positive_rate_pct,
    CASE
        WHEN (flagged - caught) <= @build_honest * 0.001 THEN 'within 0.1%'
        WHEN (flagged - caught) <= @build_honest * 0.005 THEN 'within 0.5%'
        WHEN (flagged - caught) <= @build_honest * 0.010 THEN 'within 1%'
        ELSE 'over 1%'
    END                                                              AS cap_met,
    round_thresholds
INTO #rule_results
FROM #rule_scores;

-- Rules 1 to 5 and rule 7, every variant
SELECT
    rule_name, flagged, caught, honest_flagged, precision_pct, recall_pct, false_positive_rate_pct, cap_met
FROM #rule_results
WHERE rule_name NOT LIKE '6%'
  AND rule_name NOT LIKE '8%'
ORDER BY rule_name;

-- Rule 6d (no hour, with destination history): the three best within the 0.5% cap
SELECT TOP 3
    rule_name, flagged, caught, honest_flagged, precision_pct, recall_pct, false_positive_rate_pct
FROM #rule_results
WHERE rule_name LIKE '6d%'
  AND cap_met IN ('within 0.1%', 'within 0.5%')
ORDER BY caught DESC, flagged;

-- Rule 6d again, keeping only round thresholds (multiples of 100,000)
-- The tie-break is that the simpler rule wins if it is within one point of
-- recall of the best. A round threshold is simpler to state and less likely to
-- be fitted to noise than one picked from hundreds of 10,000 steps.
SELECT TOP 3
    rule_name, flagged, caught, honest_flagged, precision_pct, recall_pct, false_positive_rate_pct
FROM #rule_results
WHERE rule_name LIKE '6d%'
  AND round_thresholds = 1
  AND cap_met IN ('within 0.1%', 'within 0.5%')
ORDER BY caught DESC, flagged;

-- Rule 8 (second operating point): the five best with a false positive rate
-- of 3% or less
SELECT TOP 5
    rule_name, flagged, caught, honest_flagged, precision_pct, recall_pct, false_positive_rate_pct
FROM #rule_results
WHERE rule_name LIKE '8%'
  AND false_positive_rate_pct <= 3.0
ORDER BY caught DESC, flagged;

-- Rule 6 (no hour): the ten best variants within the 0.5% cap
-- Hundreds of thresholds were tried, so only the best are listed.
SELECT TOP 10
    rule_name, flagged, caught, honest_flagged, precision_pct, recall_pct, false_positive_rate_pct
FROM #rule_results
WHERE rule_name LIKE '6%'
  AND cap_met IN ('within 0.1%', 'within 0.5%')
ORDER BY caught DESC, flagged;

-- Rule 6a only (one CASH_OUT threshold, nothing else): the five best within 0.5%
SELECT TOP 5
    rule_name, flagged, caught, honest_flagged, precision_pct, recall_pct, false_positive_rate_pct
FROM #rule_results
WHERE rule_name LIKE '6a%'
  AND cap_met IN ('within 0.1%', 'within 0.5%')
ORDER BY caught DESC, flagged;

-- The best three rules at each cap, with and without destination history
SELECT
    cap_label, uses_history, rank_in_cap, rule_name, caught, honest_flagged, precision_pct, recall_pct, false_positive_rate_pct
FROM (
    SELECT
        cap.label AS cap_label,
        CASE WHEN r.rule_name LIKE '7%' THEN 'with history' ELSE 'without history' END AS uses_history,
        r.rule_name, r.caught, r.honest_flagged, r.precision_pct, r.recall_pct, r.false_positive_rate_pct,
        ROW_NUMBER() OVER (
            PARTITION BY cap.label, CASE WHEN r.rule_name LIKE '7%' THEN 1 ELSE 0 END
            ORDER BY r.caught DESC, r.flagged
        ) AS rank_in_cap
    FROM #rule_results r
    CROSS JOIN (
        VALUES (0.001, '0.1%'), (0.005, '0.5%'), (0.010, '1%')
    ) cap (cap_share, label)
    WHERE r.honest_flagged <= @build_honest * cap.cap_share
) t
WHERE rank_in_cap <= 3
ORDER BY cap_label, uses_history, rank_in_cap;

-- ====================================================================
-- Part 2: Score the frozen rules on the test period
-- ====================================================================
-- This part was run once, after the three rules in gold.rule_flags were
-- frozen and committed. Nothing above this line reads test-period rows, and no
-- rule was changed after this part was run.
-- The existing flag and the three frozen rules, build and test side by side.
-- TRANSFER and CASH_OUT only. Day 31 is excluded.
SELECT
    rule_name,
    rule_period,
    fraud_rate_pct,
    flagged_transactions,
    true_positives  AS fraud_caught,
    false_positives AS honest_flagged,
    precision_pct,
    recall_pct,
    false_positive_rate_pct,
    CASE
        WHEN false_positive_rate_pct <= 0.5 THEN 'within 0.5% cap'
        ELSE 'over 0.5% cap'
    END AS cap_check
FROM gold.report_rule_performance
ORDER BY rule_name, rule_period;

-- Did the destination history behave differently in the two periods?
-- The history starts at step 1, so every account looks new at the start of the
-- month and fewer do later on. This shows, for each period, how many honest
-- and fraud transfers went to a new destination.
SELECT
    dt.rule_period,
    CASE
        WHEN h.destination_prior_transactions = 0 THEN 'new destination'
        ELSE 'received before'
    END                                                        AS destination_history,
    COUNT(*)                                                   AS transfers,
    SUM(f.is_fraud)                                            AS fraud_transfers,
    COUNT(*) - SUM(f.is_fraud)                                 AS honest_transfers,
    CAST((COUNT(*) - SUM(f.is_fraud)) * 100.0
         / SUM(COUNT(*) - SUM(f.is_fraud)) OVER (PARTITION BY dt.rule_period) AS DECIMAL(7,4)) AS share_of_honest_transfers_pct
FROM gold.fact_transactions f
LEFT JOIN gold.fact_destination_history h
    ON f.transaction_id = h.transaction_id
LEFT JOIN gold.dim_time dt
    ON f.time_key = dt.time_key
LEFT JOIN gold.dim_transaction_type ty
    ON f.transaction_type_key = ty.transaction_type_key
WHERE ty.transaction_type = 'TRANSFER'
  AND dt.rule_period != 'excluded'
GROUP BY
    dt.rule_period,
    CASE
        WHEN h.destination_prior_transactions = 0 THEN 'new destination'
        ELSE 'received before'
    END
ORDER BY dt.rule_period, destination_history;

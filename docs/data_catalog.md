# Data Catalog

## Overview

This catalog describes every table and view in the three layers of the warehouse.

- **Bronze** holds the source file exactly as it arrived.
- **Silver** holds the same rows, cleaned, typed and flagged.
- **Gold** holds the star schema, the detection rules and the report views.

PaySim is synthetic data. Amounts are in the simulation's local currency, which the dataset
does not name.

Two things apply throughout:

- **Each step is one hour.** The data covers steps 1 to 743, which is 30 full days and a
  31st day of 23 hours.
- **Balance columns are not for detection rules.** The dataset's author notes that detected
  fraud transactions are cancelled, so the balances give the outcome away. The four balance
  columns and the two mismatch flags are marked below. They are for description only.

---

## Bronze Layer

### 1. **bronze.paysim_transactions**
- **Purpose:** The source CSV, unchanged. Column names and order match the file. 6,362,620 rows.
- **Columns:**

| Column Name    | Data Type    | Description                                                                                         |
|----------------|--------------|-----------------------------------------------------------------------------------------------------|
| step           | INT          | Hour of the simulation, from 1 to 743.                                                              |
| type           | NVARCHAR(50) | Transaction type: CASH_IN, CASH_OUT, DEBIT, PAYMENT or TRANSFER.                                    |
| amount         | FLOAT        | Amount of the transaction. FLOAT because some source values are written in scientific notation.     |
| nameOrig       | NVARCHAR(50) | Account that started the transaction. Always starts with 'C' (customer).                            |
| oldbalanceOrg  | FLOAT        | Origin account balance before the transaction. Not for detection rules.                             |
| newbalanceOrig | FLOAT        | Origin account balance after the transaction. Not for detection rules.                              |
| nameDest       | NVARCHAR(50) | Account that received the transaction. Starts with 'C' (customer) or 'M' (merchant).                |
| oldbalanceDest | FLOAT        | Destination account balance before the transaction. Not for detection rules.                        |
| newbalanceDest | FLOAT        | Destination account balance after the transaction. Not for detection rules.                         |
| isFraud        | INT          | The true label: 1 if the transaction is fraud, 0 if not.                                            |
| isFlaggedFraud | INT          | The existing rule's verdict: 1 if the company's current rule flagged the transaction, 0 if not.     |

---

## Silver Layer

### 2. **silver.paysim_transactions**
- **Purpose:** The same 6,362,620 rows, with readable names, exact money types, two time columns
  derived from the step, and flags on problem rows. No row is deleted.
- **Columns:**

| Column Name                     | Data Type     | Description                                                                                                   |
|---------------------------------|---------------|---------------------------------------------------------------------------------------------------------------|
| transaction_id                  | INT           | Id created at load time, 1 to 6,362,620. Rows are numbered in order of step, origin account and destination account. That combination is unique, so every reload gives each row the same id. |
| step                            | INT           | Hour of the simulation, from 1 to 743.                                                                        |
| day_number                      | INT           | Day of the month, 1 to 31. Calculated as (step - 1) / 24 + 1, using whole-number division.                    |
| hour_slot                       | INT           | Hour within the day, 0 to 23. Calculated as (step - 1) % 24. Slot 0 is the first hour of each day. The data does not say which clock hour that is. |
| transaction_type                | NVARCHAR(50)  | Transaction type, as in the source (bronze column `type`).                                                    |
| amount                          | DECIMAL(18,2) | Amount of the transaction.                                                                                    |
| origin_account                  | NVARCHAR(50)  | Account that started the transaction (bronze `nameOrig`).                                                     |
| origin_old_balance              | DECIMAL(18,2) | Origin balance before the transaction. Not for detection rules.                                               |
| origin_new_balance              | DECIMAL(18,2) | Origin balance after the transaction. Not for detection rules.                                                |
| destination_account             | NVARCHAR(50)  | Account that received the transaction (bronze `nameDest`).                                                    |
| destination_old_balance         | DECIMAL(18,2) | Destination balance before the transaction. Not for detection rules.                                          |
| destination_new_balance         | DECIMAL(18,2) | Destination balance after the transaction. Not for detection rules.                                           |
| is_fraud                        | TINYINT       | The true label: 1 if fraud, 0 if not.                                                                         |
| is_flagged_fraud                | TINYINT       | The existing rule's verdict: 1 if flagged, 0 if not.                                                          |
| is_merchant_destination         | TINYINT       | 1 if the destination account starts with 'M'. Every PAYMENT goes to a merchant, and no other type does.       |
| is_zero_amount                  | TINYINT       | 1 if the amount is 0.                                                                                         |
| is_origin_balance_mismatch      | TINYINT       | 1 if the origin's new balance is more than 0.01 away from the old balance minus the amount (plus the amount for CASH_IN). Not for detection rules. |
| is_destination_balance_mismatch | TINYINT       | 1 if the destination's new balance is more than 0.01 away from the old balance plus the amount (minus the amount for CASH_IN). Always 1 for merchants, whose balances are never recorded. Not for detection rules. |
| dwh_create_date                 | DATETIME2     | When the row was loaded into silver.                                                                          |

A gap of one cent or less between the balances is treated as rounding in the source, and is
not flagged as a mismatch.

---

## Gold Layer

### 3. **gold.dim_time**
- **Purpose:** One row per step (hour). The only place the build and test periods are defined.
  A table with 743 rows.
- **Columns:**

| Column Name | Data Type    | Description                                                                                       |
|-------------|--------------|---------------------------------------------------------------------------------------------------|
| time_key    | INT          | Surrogate key uniquely identifying each hour. Equal to the step, because no step is missing.      |
| step        | INT          | Hour of the simulation, from 1 to 743.                                                            |
| day_number  | INT          | Day of the month, 1 to 31.                                                                        |
| hour_slot   | INT          | Hour within the day, 0 to 23.                                                                     |
| rule_period | NVARCHAR(50) | 'build' for days 1 to 15, 'test' for days 16 to 30, 'excluded' for day 31.                        |

### 4. **gold.dim_transaction_type**
- **Purpose:** One row per transaction type. A table with 5 rows.
- **Columns:**

| Column Name           | Data Type    | Description                                                              |
|-----------------------|--------------|--------------------------------------------------------------------------|
| transaction_type_key  | INT          | Surrogate key uniquely identifying each transaction type.                |
| transaction_type      | NVARCHAR(50) | The source value (e.g., 'CASH_OUT').                                     |
| transaction_type_name | NVARCHAR(50) | A readable name (e.g., 'Cash out').                                      |

### 5. **gold.fact_transactions**
- **Purpose:** One row per transaction. This is the view detection rules are written against,
  so it has no balance columns and no mismatch flags. A view over silver.
- **Columns:**

| Column Name             | Data Type     | Description                                                             |
|-------------------------|---------------|-------------------------------------------------------------------------|
| transaction_id          | INT           | Id of the transaction, from silver.                                     |
| time_key                | INT           | Surrogate key linking to gold.dim_time.                                 |
| transaction_type_key    | INT           | Surrogate key linking to gold.dim_transaction_type.                     |
| origin_account          | NVARCHAR(50)  | Account that started the transaction.                                   |
| destination_account     | NVARCHAR(50)  | Account that received the transaction.                                  |
| amount                  | DECIMAL(18,2) | Amount of the transaction.                                              |
| is_fraud                | TINYINT       | The true label. Used to score rules, never inside a rule.               |
| is_flagged_fraud        | TINYINT       | The existing rule's verdict.                                            |
| is_merchant_destination | TINYINT       | 1 if the destination is a merchant.                                     |
| is_zero_amount          | TINYINT       | 1 if the amount is 0.                                                   |

### 6. **gold.fact_transaction_balances**
- **Purpose:** The balance columns and mismatch flags, kept apart from the main fact. For
  description only. Not for detection rules. A view over silver, joined to the fact on
  transaction_id.
- **Columns:**

| Column Name                     | Data Type     | Description                                                     |
|---------------------------------|---------------|-----------------------------------------------------------------|
| transaction_id                  | INT           | Id of the transaction, from silver.                             |
| time_key                        | INT           | Surrogate key linking to gold.dim_time.                         |
| transaction_type_key            | INT           | Surrogate key linking to gold.dim_transaction_type.             |
| origin_old_balance              | DECIMAL(18,2) | Origin balance before the transaction.                          |
| origin_new_balance              | DECIMAL(18,2) | Origin balance after the transaction.                           |
| destination_old_balance         | DECIMAL(18,2) | Destination balance before the transaction.                     |
| destination_new_balance         | DECIMAL(18,2) | Destination balance after the transaction.                      |
| is_merchant_destination         | TINYINT       | 1 if the destination is a merchant.                             |
| is_origin_balance_mismatch      | TINYINT       | 1 if the origin balances do not add up.                         |
| is_destination_balance_mismatch | TINYINT       | 1 if the destination balances do not add up.                    |

### 7. **gold.fact_destination_history**
- **Purpose:** One row per transaction, holding what was known about the destination account
  before the transaction happened. A table with 6,362,620 rows, joined to the fact on
  transaction_id.
- **Columns:**

| Column Name                    | Data Type | Description                                                                                          |
|--------------------------------|-----------|------------------------------------------------------------------------------------------------------|
| transaction_id                 | INT       | Id of the transaction, from silver.                                                                  |
| destination_prior_transactions | INT       | Number of transactions, of any type, the destination account had received in strictly earlier steps. Transactions in the same step and in later steps are never counted. 0 means a new destination. |

The count starts from step 1, because that is where the data starts. An account that was
active before the month began still shows 0 at first.

### 8. **gold.rule_flags**
- **Purpose:** The three frozen detection rules. One row per TRANSFER or CASH_OUT transaction
  (2,770,409 rows). The other types have no fraud and are never flagged. A view that reads only
  the type, amount, hour slot and destination history. It reads no balance column and no fraud
  label.
- **Columns:**

| Column Name             | Data Type | Description                                                                                         |
|-------------------------|-----------|-----------------------------------------------------------------------------------------------------|
| transaction_id          | INT       | Id of the transaction, from silver.                                                                 |
| is_flagged_chosen_rule  | INT       | 1 if the chosen rule flags it: a CASH_OUT of 800,000 or more, or of zero, or in hour slots 0 to 6; or a TRANSFER to a new destination that is in hour slots 0 to 6 or is 5,000,000 or more. |
| is_flagged_no_hour_rule | INT       | 1 if the no-hour rule flags it: a CASH_OUT of 800,000 or more, or of zero; or a TRANSFER to a new destination of 1,500,000 or more. |
| is_flagged_wider_rule   | INT       | 1 if the wider rule flags it: a CASH_OUT of 800,000 or more, or of zero, or in hour slots 0 to 7; or any TRANSFER to a new destination. This rule is outside the 0.5% cap and is not the recommendation. |

### 9. Report views

Each report view answers one question. All are views, and none has an order of its own, so
add an `ORDER BY` when querying them. Rates are percentages.

| View | Question it answers | Columns |
|---|---|---|
| gold.report_fraud_overview | How big is the fraud problem, in transactions and in money? | total_transactions, fraud_transactions, fraud_rate_pct, total_amount, fraud_amount, fraud_amount_pct |
| gold.report_fraud_by_type | Which transaction types does fraud happen in? | transaction_type, transaction_type_name, total_transactions, fraud_transactions, fraud_rate_pct, total_amount, fraud_amount, fraud_amount_pct |
| gold.report_fraud_by_day | How are fraud and normal transactions spread across the days? | day_number, rule_period, hours_in_day, total_transactions, normal_transactions, fraud_transactions, fraud_rate_pct |
| gold.report_fraud_by_hour | At what time of day is fraud most concentrated? | hour_slot, total_transactions, fraud_transactions, fraud_rate_pct |
| gold.report_fraud_by_amount_band | What amounts does fraud use, compared with normal transactions? | amount_band, total_transactions, fraud_transactions, fraud_rate_pct |
| gold.report_fraud_destinations | Do fraud transactions go to the same destination accounts repeatedly? | fraud_transactions_received, destination_accounts, fraud_transactions |
| gold.report_existing_rule_performance | How badly does the existing rule perform, per period, across all five types? | rule_period, total_transactions, fraud_transactions, fraud_rate_pct, flagged_transactions, true_positives, false_positives, false_negatives, precision_pct, recall_pct, false_positive_rate_pct |
| gold.report_missed_fraud | What does the fraud that the existing rule misses look like? | rule_period, transaction_type, amount_band, fraud_transactions, caught_by_existing_rule, missed_by_existing_rule, missed_fraud_amount |
| gold.report_fraud_by_type_and_hour | Within TRANSFER and CASH_OUT, does the hour separate fraud from normal? | rule_period, transaction_type, hour_slot, total_transactions, fraud_transactions, fraud_rate_pct |
| gold.report_fraud_by_type_and_amount_band | Within TRANSFER and CASH_OUT, does the amount separate fraud from normal? | rule_period, transaction_type, amount_band, total_transactions, fraud_transactions, fraud_rate_pct |
| gold.report_rule_performance | Can a better rule catch more fraud without flagging too many honest customers? | rule_period, rule_name, total_transactions, fraud_transactions, fraud_rate_pct, flagged_transactions, true_positives, false_positives, false_negatives, precision_pct, recall_pct, false_positive_rate_pct |
| gold.report_balance_quality | How often do the balances fail to add up, by type? Description only. | transaction_type, total_transactions, merchant_destination_transactions, origin_mismatch_transactions, origin_mismatch_pct, destination_mismatch_transactions, destination_mismatch_pct |

Terms used in the rule reports:

- **true_positives:** fraud transactions the rule flagged.
- **false_positives:** honest transactions the rule flagged.
- **false_negatives:** fraud transactions the rule missed.
- **precision_pct:** of the transactions the rule flagged, the share that are fraud.
- **recall_pct:** of the fraud transactions, the share the rule flagged.
- **false_positive_rate_pct:** of the honest transactions, the share the rule flagged.

`gold.report_rule_performance` covers TRANSFER and CASH_OUT only, and
`gold.report_existing_rule_performance` covers all five types, so their false positive rates
are not comparable. Both leave out day 31.

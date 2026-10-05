# Data Profiling Note: What Phase 4 Found

The key results from profiling the raw PaySim data in `bronze.paysim_transactions`, and the
build and test cutoff that was chosen because of them.

Every number here was produced by a query in
[scripts/bronze/profile_bronze.sql](../scripts/bronze/profile_bronze.sql). PaySim is
synthetic data, so these are findings about a simulation, not about real customers.

## Size and basic quality

| Check | Result |
|---|---|
| Rows | 6,362,620 |
| Steps (hours) | 1 to 743, none missing |
| NULLs | 0 in all 11 columns |
| Fully duplicated rows | 0 |
| Text values with leading or trailing spaces | 0 |
| Negative amounts or balances | 0 |
| Money values with more than 2 decimal places | 0 |
| Largest money value | 356,179,278.92 (`newbalanceDest`) |

The last two rows matter for silver. Bronze stores money as `FLOAT`, and silver casts it to
`DECIMAL(18,2)`. Nothing has more than 2 decimal places and the largest value fits easily, so
that cast rounds nothing and cannot overflow.

Each step is one hour. The steps stop at 743 rather than 744, so days 1 to 30 have 24 hours
and day 31 has 23.

## Transaction types and accounts

| Type | Rows | Share of rows | Fraud rows |
|---|---:|---:|---:|
| CASH_OUT | 2,237,500 | 35.17% | 4,116 |
| PAYMENT | 2,151,495 | 33.81% | 0 |
| CASH_IN | 1,399,284 | 21.99% | 0 |
| TRANSFER | 532,909 | 8.38% | 4,097 |
| DEBIT | 41,432 | 0.65% | 0 |

- Every origin account starts with `C` (customer).
- Destinations start with `C` (4,211,125 rows) or `M` (merchant, 2,151,495 rows).
- Every PAYMENT goes to a merchant, and no other type does.
- There are 6,353,307 distinct origin accounts in 6,362,620 rows, so almost every origin
  sends only once. A rule based on a sender's own history would have very little to work
  with. There are 2,722,362 distinct destination accounts.

## Fraud

- 8,213 rows are fraud, which is 0.1291% of all rows.
- Fraud appears only in TRANSFER and CASH_OUT. The other three types have none.
- 16 rows have an amount of zero, and all 16 are fraud.
- No fraud amount is larger than 10,000,000, and 287 fraud rows sit exactly on that value.
  Normal transfers go as high as 92,445,516.64.
- The average fraud amount is 1,467,967.30, against 178,197.04 for normal transactions.

Fraud rate by amount band:

| Amount | Rows | Fraud rows | Fraud rate |
|---|---:|---:|---:|
| Zero | 16 | 16 | 100.0000% |
| Under 1k | 142,626 | 42 | 0.0294% |
| 1k to 10k | 1,143,361 | 220 | 0.0192% |
| 10k to 100k | 2,239,253 | 1,429 | 0.0638% |
| 100k to 200k | 1,163,794 | 1,035 | 0.0889% |
| 200k to 500k | 1,333,286 | 1,607 | 0.1205% |
| 500k to 1m | 209,658 | 1,158 | 0.5523% |
| 1m to 10m | 124,976 | 2,419 | 1.9356% |
| 10m and over | 5,650 | 287 | 5.0796% |

## The existing fraud flag

`isFlaggedFraud` is the existing rule's verdict. It flagged 16 rows. All 16 are fraud and all
16 are transfers, so it raised no false alarms, but it caught 16 of the 8,213 fraud rows.

The dataset description says the flag marks transfers of more than 200,000. The data does
not behave that way. There are 409,110 transfers over 200,000, 2,740 of them fraud, and only
16 are flagged. The smallest flagged amount is 353,874.22 and the largest is 10,000,000.

## Time of day

Fraud is spread almost evenly across the 24 hour slots, between 274 and 375 fraud rows per
slot. Normal volume is not. It is very low in slots 0 to 7 and high from slot 8 onward. As a
result the fraud rate is about 22% in slots 3 and 4, and under 0.09% in slots 9 to 19.

Slot 0 is the first hour of each day (steps 1, 25, 49 and so on). The data does not say
which clock hour that is.

## The balance columns

These four columns are profiled here and are not used in detection rules.

- All PAYMENT rows have zero in both destination balance columns. Merchant balances are not
  recorded.
- The origin balance often does not add up. The share of rows where `newbalanceOrig` is more
  than 0.01 away from what `oldbalanceOrg` and `amount` say it should be:

| Type | Origin mismatch | Destination mismatch |
|---|---:|---:|
| CASH_IN | 0.00% (33 rows) | 26.25% |
| CASH_OUT | 88.54% | 9.46% |
| DEBIT | 28.45% | 8.31% |
| PAYMENT | 51.18% | 100.00% |
| TRANSFER | 95.24% | 10.90% |

  The 100% destination mismatch for PAYMENT is because merchant balances are never recorded
  (both columns are always zero), not because the data is broken.

  Origin mismatches are the normal case for TRANSFER and CASH_OUT, and affect about half of
  PAYMENT rows, so they are not a rare error. CASH_IN is the exception: its origin balance
  adds up in all but 33 rows. Destination mismatches are less common, between 8.31% and
  26.25% outside PAYMENT. Silver flags these rows and does not delete them.

  A gap of one cent or less is treated as rounding in the source and is not counted as a
  mismatch. The silver flags use the same rule, and a quality check confirms the silver flag
  counts equal the counts behind this table for every type.

  A correction: an earlier version of these two queries compared the `FLOAT` values from
  bronze directly, and reported higher figures (for example 7.22% for CASH_IN origin and
  37.57% for CASH_IN destination). Those were wrong. `FLOAT` cannot hold 0.01 exactly, so a
  row whose gap is really one cent can come out a hair above or below 0.01, and many such
  rows were counted as mismatches. The queries now cast every value to `DECIMAL(18,2)` before
  comparing, which makes the one cent line exact.
- The leak is visible. Among TRANSFER and CASH_OUT rows, the amount exactly equals the whole
  origin balance in 8,034 of the 8,213 fraud rows, and in none of the 2,762,196 normal rows
  (1 normal row comes within one cent). A rule
  using that would look excellent and would be using information that gives the answer
  away, which is why the balance columns stay out of the rules.

## Fraud and normal transactions per day

Day number is `(step - 1) / 24 + 1`. This uses whole-number division, which drops any
remainder, so step 25 gives day 2.

| Day | Hours | Rows | Normal | Fraud | Fraud rate |
|---:|---:|---:|---:|---:|---:|
| 1 | 24 | 574,255 | 573,984 | 271 | 0.0472% |
| 2 | 24 | 455,238 | 454,929 | 309 | 0.0679% |
| 3 | 24 | 1,070 | 760 | 310 | 28.9720% |
| 4 | 24 | 28,240 | 27,978 | 262 | 0.9278% |
| 5 | 24 | 9,789 | 9,537 | 252 | 2.5743% |
| 6 | 24 | 441,005 | 440,777 | 228 | 0.0517% |
| 7 | 24 | 420,583 | 420,311 | 272 | 0.0647% |
| 8 | 24 | 449,637 | 449,359 | 278 | 0.0618% |
| 9 | 24 | 417,919 | 417,664 | 255 | 0.0610% |
| 10 | 24 | 392,945 | 392,663 | 282 | 0.0718% |
| 11 | 24 | 417,859 | 417,597 | 262 | 0.0627% |
| 12 | 24 | 349,776 | 349,478 | 298 | 0.0852% |
| 13 | 24 | 428,583 | 428,341 | 242 | 0.0565% |
| 14 | 24 | 397,876 | 397,630 | 246 | 0.0618% |
| 15 | 24 | 401,282 | 401,032 | 250 | 0.0623% |
| 16 | 24 | 375,594 | 375,342 | 252 | 0.0671% |
| 17 | 24 | 425,766 | 425,446 | 320 | 0.0752% |
| 18 | 24 | 20,999 | 20,731 | 268 | 1.2763% |
| 19 | 24 | 11,300 | 11,044 | 256 | 2.2655% |
| 20 | 24 | 19,727 | 19,491 | 236 | 1.1963% |
| 21 | 24 | 24,593 | 24,321 | 272 | 1.1060% |
| 22 | 24 | 53,437 | 53,181 | 256 | 0.4791% |
| 23 | 24 | 51,012 | 50,796 | 216 | 0.4234% |
| 24 | 24 | 32,709 | 32,429 | 280 | 0.8560% |
| 25 | 24 | 57,853 | 57,613 | 240 | 0.4148% |
| 26 | 24 | 13,885 | 13,613 | 272 | 1.9589% |
| 27 | 24 | 8,578 | 8,298 | 280 | 3.2642% |
| 28 | 24 | 14,661 | 14,413 | 248 | 1.6916% |
| 29 | 24 | 54,890 | 54,630 | 260 | 0.4737% |
| 30 | 24 | 11,287 | 11,019 | 268 | 2.3744% |
| 31 | 23 | 272 | 0 | 272 | 100.0000% |

Two things stand out.

Fraud is steady and normal volume is not. Fraud stays between 216 and 320 rows every day.
Normal volume is between about 350,000 and 575,000 rows on days 1, 2 and 6 to 17, and
collapses on days 3 to 5 and from day 18 onward, where no day has more than 57,853 rows.

Day 31 holds 272 rows and every one is fraud. There are no normal transactions at all.

## Choosing the build and test cutoff

The detection rule is built on the earlier days and tested once on later days it has never
seen. The starting plan was to build on days 1 to 20 and test on days 21 to 31.

The table below counts TRANSFER and CASH_OUT rows only, because those are the only types
with any fraud, so they are the rows a rule is judged on.

| Cutoff | Build normal | Build fraud | Test normal | Test fraud |
|---|---:|---:|---:|---:|
| Days 1 to 20 / 21 to 31 | 2,630,906 | 5,349 | 131,290 | 2,864 |
| Days 1 to 15 / 16 to 31 | 2,260,881 | 4,017 | 501,315 | 4,196 |
| Days 1 to 10 / 11 to 31 | 1,395,598 | 2,719 | 1,366,598 | 5,494 |

The same comparison across all five types:

| Cutoff | Build normal | Build fraud | Test normal | Test fraud |
|---|---:|---:|---:|---:|
| Days 1 to 20 / 21 to 31 | 6,034,094 | 5,349 | 320,313 | 2,864 |
| Days 1 to 15 / 16 to 31 | 5,182,040 | 4,017 | 1,172,367 | 4,196 |
| Days 1 to 10 / 11 to 31 | 3,187,962 | 2,719 | 3,166,445 | 5,494 |

### The decision: build on days 1 to 15, test on days 16 to 30

The 20/21 cutoff was rejected because its test period falls entirely in the thin days. All of
the busy days would be in the build period, and the rule would be tested only on a stretch
where normal volume has collapsed: 131,290 normal TRANSFER and CASH_OUT rows against 2,864
fraud rows. A test like that says little about how many honest customers the rule would
flag on an ordinary busy day.

The 15/16 cutoff was chosen for three reasons:

1. The test period includes two busy days (16 and 17) as well as the thin days, so the rule
   is tested on both kinds of day.
2. Fraud is split almost evenly between the two periods, so recall is measured on a similar
   number of fraud rows in each.
3. The build period still holds 15 days and most of the busy ones, which is plenty to design
   a rule on.

The 10/11 cutoff would give an even larger test period, but it leaves only 2,719 fraud rows
to build the rule on, and three of its ten build days (3, 4 and 5) are thin ones.

### Day 31 is left out of rule evaluation

Day 31 stays in every layer and in profiling, but it is excluded when a rule is evaluated.
It has 272 fraud rows and no normal transactions, which is an artifact of the simulation. A
day with no honest customers cannot produce a false positive, so including it would add to
recall while saying nothing about false alarms.

The periods as finally chosen:

| Period | Steps | Rows | Normal | Fraud | Fraud rate |
|---|---|---:|---:|---:|---:|
| Build, days 1 to 15 | 1 to 360 | 5,186,057 | 5,182,040 | 4,017 | 0.0775% |
| Test, days 16 to 30 | 361 to 720 | 1,176,291 | 1,172,367 | 3,924 | 0.3336% |
| Excluded, day 31 | 721 to 743 | 272 | 0 | 272 | 100.0000% |

TRANSFER and CASH_OUT only:

| Period | Rows | Normal | Fraud | Fraud rate |
|---|---:|---:|---:|---:|
| Build, days 1 to 15 | 2,264,898 | 2,260,881 | 4,017 | 0.1774% |
| Test, days 16 to 30 | 505,239 | 501,315 | 3,924 | 0.7767% |
| Excluded, day 31 | 272 | 0 | 272 | 100.0000% |

### What this means for judging a rule

The fraud rate in the test period is still several times the rate in the build period,
because the test period contains most of the thin days. No day-based cutoff avoids this,
since normal volume drops and fraud does not.

That matters for precision. Precision is the share of flagged rows that are really fraud, so
it rises when fraud is more common, even if the rule has not changed. A rule will show
higher precision on the test period partly for that reason alone.

So each period is reported with four numbers: precision, recall, false positive rate, and
the period's fraud rate. Recall (the share of fraud caught) and false positive rate (the
share of normal transactions wrongly flagged) do not depend on how common fraud is, so they
are the fair comparison between build and test. Precision is always shown next to the
period's fraud rate so it can be read in context.

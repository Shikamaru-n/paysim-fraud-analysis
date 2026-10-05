# Findings

Answers to the business questions, one section per question.

Main business question: the company's current fraud rule catches almost none of the fraud.
Where does fraud happen, what does it look like, and can a better SQL-based rule catch more
of it without flagging too many honest customers?

Things to know before reading:

- PaySim is synthetic data. Every finding here describes a simulation, not real customers.
- Every number was produced by the script named under its heading, in `scripts/analysis/`.
- Questions 1 to 8 are descriptive and cover the whole month (6,362,620 transactions).
- Question 9 uses the build period only (days 1 to 15), because it feeds the rule design.
- Question 10 is answered in Phase 8.
- No finding uses the balance columns.
- The hour of the day is a strong signal in this data, but probably an artifact of the
  simulation. Fraud is spread evenly across the day while normal activity follows a daily
  rhythm, so a rule built on the hour would likely work much less well on real data. The
  data does not say which clock hour slot 0 is. See question 4.

## 1. How big is the fraud problem, in transactions and in money?

Script: `01_fraud_overview.sql`

| Measure | Value |
|---|---:|
| Transactions | 6,362,620 |
| Fraud transactions | 8,213 |
| Fraud's share of transactions | 0.1291% |
| Total amount | 1,144,392,944,759.77 |
| Fraud amount | 12,056,415,427.84 |
| Fraud's share of the money | 1.0535% |

Fraud is rare by count and much less rare by value. About 1 transaction in 800 is fraud, but
fraud takes about 1 unit of money in every 100. Fraud transactions are large ones.

## 2. Which transaction types does fraud happen in?

Script: `02_fraud_by_type.sql`

| Type | Transactions | Fraud | Fraud rate | Fraud's share of the type's money |
|---|---:|---:|---:|---:|
| CASH_OUT | 2,237,500 | 4,116 | 0.1840% | 1.5185% |
| TRANSFER | 532,909 | 4,097 | 0.7688% | 1.2502% |
| PAYMENT | 2,151,495 | 0 | 0.0000% | 0.0000% |
| CASH_IN | 1,399,284 | 0 | 0.0000% | 0.0000% |
| DEBIT | 41,432 | 0 | 0.0000% | 0.0000% |

Fraud happens in two types only, and is split almost evenly between them by count. The rate
is about four times higher in TRANSFER, because there are far fewer transfers. PAYMENT,
CASH_IN and DEBIT have no fraud at all, so a rule only needs to look at TRANSFER and CASH_OUT.

## 3. On which days does fraud happen, and how does it compare with normal volume?

Script: `03_fraud_by_day.sql`

Fraud happens every day at a steady level. Normal volume does not.

| Measure | Lowest day | Highest day | Average per day |
|---|---:|---:|---:|
| Fraud transactions | 216 | 320 | 264 |
| Normal transactions | 0 | 573,984 | 204,980 |

Calling a day thin when it has fewer than 100,000 normal transactions:

| Kind of day | Days | Normal | Fraud | Fraud rate |
|---|---:|---:|---:|---:|
| Busy | 14 | 5,944,553 | 3,765 | 0.0633% |
| Thin | 17 | 409,854 | 4,448 | 1.0736% |

The thin days are days 3 to 5 and days 18 to 31. Day 31 has 272 fraud transactions and no
normal ones.

Because the fraud count barely moves while normal volume swings, the fraud rate of a day is
set almost entirely by how busy the day is. This is the reason the fraud rate differs between
the build and test periods, and the reason precision has to be read next to the fraud rate.

## 4. At what time of day is fraud most concentrated?

Script: `04_fraud_by_hour.sql`

The same pattern appears inside the day. Fraud is spread evenly across the 24 hour slots,
between 274 and 375 fraud transactions per slot over the month. Normal activity is
concentrated in slots 8 to 22.

Calling an hour slot quiet when it has fewer than 100,000 transactions over the month:

| Kind of hour | Slots | Transactions | Fraud | Fraud rate |
|---|---|---:|---:|---:|
| Busy | 8 to 22 (15 slots) | 6,210,692 | 5,163 | 0.0831% |
| Quiet | 0 to 7 and 23 (9 slots) | 151,928 | 3,050 | 2.0075% |

The fraud rate peaks in slots 3 and 4, at 22.0790% and 22.3035%. Slot 0 is the first hour of
each day. The data does not say which clock hour that is.

Fraud is not more active in the quiet hours. Honest customers are less active, so the same
amount of fraud is a much larger share of what is left.

A caveat on this signal. It is probably an artifact of the simulation: PaySim spreads fraud
evenly across the day, while normal activity follows a daily rhythm. Real fraud is unlikely
to be spread that evenly, so a rule built on the hour would likely work much less well on
real data. The data also does not say which clock hour slot 0 is, so "quiet hours" cannot be
read as "night".

## 5. What amounts does fraud use, compared with normal transactions?

Script: `05_fraud_by_amount.sql`

| Amount | Transactions | Fraud | Fraud rate |
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

The fraud rate rises with the amount. Inside the two types that have fraud:

| Type | Kind | Transactions | Average amount | Largest amount |
|---|---|---:|---:|---:|
| CASH_OUT | Normal | 2,233,384 | 173,917.16 | 2,847,566.62 |
| CASH_OUT | Fraud | 4,116 | 1,455,102.59 | 10,000,000.00 |
| TRANSFER | Normal | 528,812 | 906,229.01 | 92,445,516.64 |
| TRANSFER | Fraud | 4,097 | 1,480,891.67 | 10,000,000.00 |

- A fraud cash-out is on average about eight times the size of a normal one. No normal
  cash-out is larger than 2,847,566.62.
- For transfers the gap is much smaller, and normal transfers go far higher than fraud ones.
- Fraud amounts are capped at 10,000,000. 287 fraud transactions sit exactly on that value
  and none is above it.
- All 16 zero-amount transactions are fraud.

## 6. Where does the fraud money go: repeated destination accounts, merchants?

Script: `06_fraud_destinations.sql`

These results describe how the fraud works. They use the fraud label and look across the
whole month, so none of them can be used as a detection rule.

- **Destination accounts are almost never reused.** 8,125 destination accounts received one
  fraud transaction and 44 received two. None received more than two.
- **No fraud goes to merchants.** All 8,213 fraud transactions go to customer accounts. None
  of the 2,151,495 transactions to merchants is fraud.
- **Fraud comes in pairs.** Grouping fraud transactions by step and amount, 3,997 groups hold
  exactly one transfer and one cash-out. That covers 7,994 of the 8,213 fraud transactions.
  The same amount is moved out by transfer and cashed out in the same hour.
- **The pair cannot be followed through the accounts.** Of the 4,097 fraud transfers, none
  goes to an account that then makes a fraud cash-out. The transfer and the cash-out of a
  pair use unrelated accounts in this data, so the two halves cannot be linked by account
  name.

## 7. How badly does the existing rule perform?

Script: `07_existing_rule_performance.sql`

Day 31 is excluded from rule evaluation, because it has no normal transactions.

| Period | Fraud rate | Fraud | Flagged | Caught | Precision | Recall | False positive rate |
|---|---:|---:|---:|---:|---:|---:|---:|
| Build (days 1 to 15) | 0.0775% | 4,017 | 3 | 3 | 100.0000% | 0.0747% | 0.0000% |
| Test (days 16 to 30) | 0.3336% | 3,924 | 10 | 10 | 100.0000% | 0.2548% | 0.0000% |

The existing rule is never wrong when it flags something, and it flags almost nothing. It
catches 3 of 4,017 fraud transactions in the build period and 10 of 3,924 in the test period.
Its perfect precision says nothing useful, because a rule that flags 13 transactions out of
more than 6 million can be precise and still useless.

The rule does not behave as described. The dataset description says it flags transfers of
more than 200,000. There are 409,110 such transfers, 2,740 of them fraud, and 16 are flagged
(3 in the build period, 10 in the test period and 3 on day 31). Every flagged transaction is
a transfer, with amounts from 353,874.22 to 10,000,000.00.

## 8. What does the fraud that the existing rule misses look like?

Script: `08_missed_fraud.sql`

It looks like all of the fraud. The rule misses 8,197 of the 8,213 fraud transactions
(99.8052%), worth 11,978,629,864.15.

| Type | Fraud | Caught | Missed | Missed amount |
|---|---:|---:|---:|---:|
| CASH_OUT | 4,116 | 0 | 4,116 | 5,989,202,243.83 |
| TRANSFER | 4,097 | 16 | 4,081 | 5,989,427,620.32 |

| Amount | Fraud | Caught | Missed |
|---|---:|---:|---:|
| Zero | 16 | 0 | 16 |
| Under 1k | 42 | 0 | 42 |
| 1k to 10k | 220 | 0 | 220 |
| 10k to 100k | 1,429 | 0 | 1,429 |
| 100k to 200k | 1,035 | 0 | 1,035 |
| 200k to 500k | 1,607 | 2 | 1,605 |
| 500k to 1m | 1,158 | 1 | 1,157 |
| 1m to 10m | 2,419 | 10 | 2,409 |
| 10m and over | 287 | 3 | 284 |

- The rule never looks at cash-outs, which are half of the fraud.
- It misses the largest fraud too. 284 of the 287 fraud transactions at 10,000,000 are not
  flagged.
- Most of the missed money is in the two largest bands.

## 9. Within the types where fraud happens, which signals separate fraud from normal?

Script: `09_fraud_signals_build_period.sql`

Build period only (days 1 to 15), TRANSFER and CASH_OUT only. These are the numbers the
Phase 8 rule is designed from. The test period was not looked at for this question.

Starting point in the build period:

| Type | Transactions | Fraud | Fraud rate |
|---|---:|---:|---:|
| CASH_OUT | 1,834,542 | 2,018 | 0.1100% |
| TRANSFER | 430,356 | 1,999 | 0.4645% |

### Signal 1: hour of the day

| Hour slot | CASH_OUT transactions | CASH_OUT fraud rate | TRANSFER transactions | TRANSFER fraud rate |
|---:|---:|---:|---:|---:|
| 0 | 2,975 | 3.0588% | 1,620 | 5.4938% |
| 1 | 814 | 9.9509% | 408 | 19.8529% |
| 2 | 214 | 31.7757% | 182 | 37.3626% |
| 3 | 132 | 45.4545% | 97 | 61.8557% |
| 4 | 135 | 57.0370% | 104 | 74.0385% |
| 5 | 245 | 33.4694% | 233 | 35.1931% |
| 6 | 1,230 | 6.5854% | 827 | 9.7944% |
| 7 | 6,217 | 1.3833% | 2,057 | 4.1808% |
| 8 | 80,701 | 0.1202% | 21,184 | 0.4626% |
| 9 to 19 | 124,642 to 205,916 | 0.0345% to 0.0774% | 29,438 to 41,317 | 0.1718% to 0.3261% |
| 20 | 56,376 | 0.1614% | 16,296 | 0.5523% |
| 21 | 34,743 | 0.2447% | 13,049 | 0.6437% |
| 22 | 20,940 | 0.4011% | 9,421 | 0.9022% |
| 23 | 9,538 | 0.7444% | 4,928 | 1.4407% |

The hour is a strong signal for both types. In slots 0 to 7 the fraud rate is many times the
type's average, and in slots 2 to 5 between 31% and 75% of these transactions are fraud. The
volumes in those slots are small, so flagging them would touch few honest customers.

The hour does not cover most of the fraud, though. Slots 0 to 7 hold 626 of the 2,018 fraud
cash-outs and 624 of the 1,999 fraud transfers. The rest falls in slots 8 to 23, where the
fraud rate never goes above 1.4407%.

### Signal 2: amount

| Amount | CASH_OUT transactions | CASH_OUT fraud | CASH_OUT fraud rate | TRANSFER transactions | TRANSFER fraud | TRANSFER fraud rate |
|---|---:|---:|---:|---:|---:|---:|
| Zero | 3 | 3 | 100.0000% | 0 | 0 | |
| Under 1k | 5,865 | 13 | 0.2217% | 433 | 13 | 3.0023% |
| 1k to 10k | 53,536 | 56 | 0.1046% | 4,389 | 56 | 1.2759% |
| 10k to 100k | 572,585 | 374 | 0.0653% | 44,825 | 367 | 0.8187% |
| 100k to 200k | 552,230 | 260 | 0.0471% | 49,661 | 255 | 0.5135% |
| 200k to 500k | 605,569 | 397 | 0.0656% | 119,964 | 388 | 0.3234% |
| 500k to 1m | 43,844 | 280 | 0.6386% | 107,558 | 280 | 0.2603% |
| 1m to 10m | 865 | 590 | 68.2081% | 98,253 | 595 | 0.6056% |
| 10m and over | 45 | 45 | 100.0000% | 5,273 | 45 | 0.8534% |

The amount works very differently for the two types.

- **CASH_OUT:** large amounts are a strong signal. Of the 910 cash-outs of 1,000,000 or more,
  635 are fraud. Normal customers almost never cash out that much. All 3 zero-amount
  cash-outs are fraud.
- **TRANSFER:** the amount is a weak signal. Large transfers are common among honest
  customers, so the fraud rate stays under 1% in every band from 10k upward. No amount
  threshold separates fraud transfers from normal ones.

### What this means for the rule

- A rule can catch much of the cash-out fraud with an amount threshold, and little of the
  transfer fraud that way.
- The hour of the day helps for both types, and is the main signal available for transfers.
  It is also the signal least likely to carry over to real data, because it probably comes
  from how the simulation spreads fraud across the day (see question 4). The data does not
  say which clock hour slot 0 is.
- Neither signal alone reaches most of the fraud. 1,383 of the 2,018 fraud cash-outs are
  under 1,000,000, and about two thirds of the fraud in each type falls outside slots 0 to 7.
  How much of that a rule can reach without flagging many honest customers is the question
  for Phase 8. These two signals have not yet been looked at in combination.

## 10. Can a better SQL rule catch more fraud without flagging too many honest customers?

Script: `10_better_rule.sql`. Rule definitions: the view `gold.rule_flags`. Scores: the view
`gold.report_rule_performance`.

**Status: the rules below are frozen. They were designed on the build period (days 1 to 15)
only. The test period (days 16 to 30) has not been looked at yet, so this section holds
build-period scores only. The test result will be added below without changing any rule.**

### How the rule was chosen

The selection criterion was fixed before any rule was scored:

> Catch as much fraud as possible (highest recall) while flagging no more than 0.5% of honest
> TRANSFER and CASH_OUT transactions in the build period. If two rules are within one
> percentage point of recall, the simpler one wins.

Scope: every rule, including the existing flag, is scored on TRANSFER and CASH_OUT
transactions only, because those are the only types with fraud. That makes the false positive
rates here stricter than, and not comparable with, the all-types figures under question 7.
Recall is the same on either basis. Day 31 is excluded.

The build period has 4,017 fraud and 2,260,881 honest TRANSFER and CASH_OUT transactions, so
the 0.5% cap allows 11,304 honest transactions to be flagged.

What the rules may use: the transaction's own type, amount and hour slot, and whether the
destination account had received any transaction in strictly earlier steps. They use no
balance column, no fraud label, and nothing from the same step or later steps.

### Candidates tried on the build period

| Rule family | Best variant within the 0.5% cap | Recall | False positive rate |
|---|---|---:|---:|
| 1. Existing flag | as it is | 0.0747% | 0.0000% |
| 2. Amount only, CASH_OUT | 620,000 or more, or zero | 20.6373% | 0.4877% |
| 3. Hour only | slots 0 to 6 | 26.8359% | 0.3599% |
| 4. Amount or hour | CASH_OUT of 800,000 or more or zero, or slots 0 to 6 | 40.1792% | 0.4169% |
| 5. Grid of hour and amount cells | 21 cells | 38.0632% | 0.4468% |
| 7. With destination history | the chosen rule below | 43.5151% | 0.3985% |

For the grid rules, hour slots were grouped into five groups and amounts into four bands, and
a cell was only eligible if it held at least 30 fraud rows in the build period. This keeps
the rule from being fitted to a handful of transactions.

### The destination history signal

A destination is "new" when it has received no transaction in any earlier step.

| Type | Destination | Transactions | Fraud | Fraud rate |
|---|---|---:|---:|---:|
| TRANSFER | New | 56,708 | 1,995 | 3.5180% |
| TRANSFER | Received before | 373,648 | 4 | 0.0011% |
| CASH_OUT | New | 290,571 | 551 | 0.1896% |
| CASH_OUT | Received before | 1,543,971 | 1,467 | 0.0950% |

In the build period, 1,995 of the 1,999 fraud transfers go to a new destination. It is the
strongest signal found for transfers. It does little for cash-outs.

One limit: the history starts at step 1, because that is where the data starts. Every account
looks new on day 1, and fewer do as the month goes on. So "new" is a weaker statement early
in the month than late in it.

### The three frozen rules

**1. Chosen rule (the recommendation).** Flag a transaction when:

- it is a CASH_OUT of 800,000 or more, or of zero, or in hour slots 0 to 6, or
- it is a TRANSFER to a new destination, and is in hour slots 0 to 6 or is 5,000,000 or more.

It has the highest recall of any rule within the 0.5% cap.

**2. No-hour rule (the fallback).** Flag a transaction when:

- it is a CASH_OUT of 800,000 or more, or of zero, or
- it is a TRANSFER to a new destination of 1,500,000 or more.

This is the best rule that does not use the hour of the day. The hour signal is probably an
artifact of the simulation (see question 4), so this is the rule more likely to carry over to
real data. The highest-scoring variant used a CASH_OUT threshold of 720,000 (recall 31.7152%).
The 800,000 version is within one point of it (30.7443%), so it wins as the simpler rule: a
round threshold, and the same one the chosen rule uses.

**3. Wider rule (a second operating point, not the recommendation).** Flag a transaction when:

- it is a CASH_OUT of 800,000 or more, or of zero, or in hour slots 0 to 7, or
- it is a TRANSFER to a new destination.

This rule is outside the 0.5% cap on purpose. It flags about 3% of honest customers, six
times the allowance. It is reported to show what a looser cap would buy, because most
transfer fraud can only be reached by flagging every transfer to a new destination.

### Build-period scores

Days 1 to 15, TRANSFER and CASH_OUT only. Fraud rate in this period: 0.1774%.

| Rule | Flagged | Fraud caught | Honest flagged | Precision | Recall | False positive rate |
|---|---:|---:|---:|---:|---:|---:|
| Existing flag | 3 | 3 | 0 | 100.0000% | 0.0747% | 0.0000% |
| Chosen rule | 10,758 | 1,748 | 9,010 | 16.2484% | 43.5151% | 0.3985% |
| No-hour rule | 10,377 | 1,235 | 9,142 | 11.9013% | 30.7443% | 0.4044% |
| Wider rule (outside the cap) | 70,462 | 3,130 | 67,332 | 4.4421% | 77.9188% | 2.9781% |

Reading these:

- The chosen rule catches 1,748 of the 4,017 fraud transactions, against 3 for the existing
  flag, while flagging about 1 honest customer in 250.
- About 5 of every 6 transactions it flags are honest. With fraud at 0.1774% of transactions,
  low precision is the price of any rule that catches a useful share of it.
- Taking the hour away costs about 13 points of recall.
- More than half of the fraud is still missed within the cap. The wider rule shows where it
  is: reaching it means flagging about 3 honest customers in 100.

### Test-period result

Not yet run. The frozen rules will be scored once on days 16 to 30 and the result added here.

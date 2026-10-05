# MAXERRORS Note: Why the Bronze Load Sets It to Zero

`BULK INSERT` will skip rows it cannot convert and still report success. By default it
tolerates up to 10 such rows. On a 6.36 million row load, a partial load that looks like a
clean one is a bad outcome, so the bronze procedure sets `MAXERRORS = 0`.

This note records how that was found, because the behaviour is quiet enough to miss.

## What the file contains

261,365 of the 6,362,620 data rows, about 4.1%, write money values in scientific notation
rather than as plain decimals. An example from row 86:

```
1,TRANSFER,379856.23,C1449772539,0.0,0.0,C1590550415,900180.0,1.916920493E7,0,0
```

That last balance, `1.916920493E7`, is 19,169,204.93. It appears in all five money columns,
not only the balances:

| Column | Rows using scientific notation |
|---|---:|
| amount | 5,650 |
| oldbalanceOrg | 140,970 |
| newbalanceOrig | 145,092 |
| oldbalanceDest | 107,345 |
| newbalanceDest | 118,988 |

## The silent failure

`BULK INSERT` cannot parse scientific notation into a `DECIMAL` column. Loading five rows
starting at row 86, with the money columns typed as `DECIMAL(18,2)`, gave this:

```
(3 rows affected)
>> DECIMAL(18,2) load SUCCEEDED
```

Three rows out of five. No error, no warning, and the `TRY` block saw nothing to catch. The
two rows holding `1.916920493E7` were dropped on the floor.

The same five rows with the money columns typed as `FLOAT`:

```
(5 rows affected)
>> FLOAT load SUCCEEDED
```

## Proving the cause

Re-running the `DECIMAL` version with `MAXERRORS = 0` turns the silence into an error:

```
>> DECIMAL with MAXERRORS=0 FAILED: Cannot fetch a row from OLE DB provider "BULK"
   for linked server "(null)".
```

So the rows were always failing. The default `MAXERRORS = 10` was absorbing the failures and
letting the statement report success.

## Why this matters beyond the type choice

The type problem is solved by using `FLOAT` in bronze and casting to `DECIMAL(18,2)` in
silver. But `MAXERRORS = 0` is kept anyway, for a different reason.

Phase 9 reconciles row counts across bronze, silver and gold against the 6,362,620 rows in
the file. If a future change to the source file or the table definition introduced conversion
failures, the default setting would let up to 10 rows vanish without a word, and the
reconciliation would be the first thing to notice. `MAXERRORS = 0` makes the load fail loudly
at the point the problem is introduced, which is where it is cheapest to fix.

## The two settings together

The bronze load therefore uses:

```sql
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '0x0a',
    MAXERRORS       = 0,
    BATCHSIZE       = 100000,
    TABLOCK
);
```

`BATCHSIZE` is there for a separate reason: it commits the load in batches of 100,000 rows
rather than as one transaction. The comment in the bronze procedure explains why.

`ROWTERMINATOR` is covered in [row_terminator_note.md](row_terminator_note.md). The two
problems are unrelated but were found in the same session, and both are the sort that look
like something else at first.

## On the float round trip

Using `FLOAT` in bronze does not lose precision at the two decimal places money needs. A
`FLOAT` column displays `379856.23` as `379856.22999999998`, which looks alarming, but casting
back recovers the exact value:

```sql
SELECT CAST(CAST('379856.23'     AS FLOAT) AS DECIMAL(18,2));  -- 379856.23
SELECT CAST(CAST('1.916920493E7' AS FLOAT) AS DECIMAL(18,2));  -- 19169204.93
```

Casting the text straight to `DECIMAL` does not work, which is why the `FLOAT` step is needed:

```sql
SELECT CAST('1.916920493E7' AS DECIMAL(18,2));      -- Error converting data type varchar to numeric
SELECT TRY_CAST('1.916920493E7' AS DECIMAL(18,2));  -- NULL
```

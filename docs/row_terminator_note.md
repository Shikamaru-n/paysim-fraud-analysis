# Row Terminator Note

Why the bronze load uses `ROWTERMINATOR = '0x0a'` instead of the default, and how that was
worked out. Worth a line in the README, because it is the kind of problem that looks like a
permissions failure and is not.

## The symptom

The first `BULK INSERT` of the PaySim CSV failed on the very first row:

```
Msg 4866, Level 16, State 8
The bulk load failed. The column is too long in the data file for row 1, column 11.
Verify that the field terminator and row terminator are specified correctly.
Msg 7301, Level 16, State 2
Cannot obtain the required interface ("IID_IColumnsInfo") from OLE DB provider "BULK"
for linked server "(null)".
```

The `WITH` clause at that point was the one the reference project uses:

```sql
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    TABLOCK
);
```

## The cause

The file uses LF line endings. `BULK INSERT` defaults to CRLF.

A byte dump of the end of the header row shows a bare `\n` with no `\r` in front of it:

```
F   r   a   u   d   ,   i   s   F   l   a   g   g   e   d   F
r   a   u   d  \n   1   ,   P   A   Y   M   E   N   T   ,   9
```

A whole-file count confirms it: the file holds 6,362,621 newline bytes and zero carriage
return bytes.

Because `BULK INSERT` was looking for `\r\n`, it never found an end of row. It kept reading
past the end of the first line, so column 11 (`isFlaggedFraud`, declared as `NVARCHAR(50)`)
swallowed the rest of the file until it overflowed. Hence "the column is too long".

The misleading part is the wording. "Column is too long" sounds like a column sizing problem
in the table definition. It is almost always a row terminator problem instead.

## Why '\n' does not fix it, and '0x0a' does

The obvious fix is to write `ROWTERMINATOR = '\n'`. That does not work.

`BULK INSERT` silently converts `'\n'` to `'\r\n'`. The same is true of `bcp`. So asking for
a line feed terminator in character form gives you exactly the CRLF behaviour you were trying
to get away from, and the error does not change. There is no warning, which is what makes it
confusing.

The way around it is to give the byte value rather than the escape sequence. `0x0a` is the
hexadecimal code for a line feed, and it is passed through literally with no conversion:

```sql
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '0x0a',
    TABLOCK
);
```

With that one line added, the same statement loaded cleanly.

## A note on the false lead

Before the test above, this was misdiagnosed as a file permissions problem. The evidence was
`xp_fileexist` returning zeros for the CSV and for its parent folders, which suggested the
SQL Server service account (`NT Service\MSSQL$SQLEXPRESS`) could not reach a file sitting
under a user profile.

That evidence was not relevant. `xp_fileexist` runs as the service account. `BULK INSERT` over
a Windows Authentication connection does not: it impersonates the Windows login that is
calling it. Confirming the login inside the failing session showed the Windows login running
sqlcmd, which has full access to the folder. The file was being read the whole time.

So no permission changes were made, and none are needed. If `BULK INSERT` is ever switched to
a SQL Server login rather than Windows Authentication, that changes: the service account would
then do the reading, and it would need its own access to the datasets folder.

## How to check this on another machine

Dump the last byte of the first line and look for `\r`:

```bash
head -c 200 datasets/PS_20174392719_1491204439457_log.csv | od -c
```

Or count carriage returns across the whole file. Zero means LF only, so use `0x0a`:

```bash
tr -cd '\r' < datasets/PS_20174392719_1491204439457_log.csv | wc -c
```

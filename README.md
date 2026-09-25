# pygrametl example programs: Jython vs. CPython

The example ETL programs from the paper *"Easy and Effective Parallel Programmable ETL"*
(C. Thomsen and T. B. Pedersen, DOLAP 2011), made runnable today on both **Jython**
(as in the paper) and **CPython 3**, with scripts to run and time them.

The programs load test results for web pages into a small star schema in PostgreSQL
(`starschema.sql`): a slowly changing `page` dimension, a `test` and a `date` dimension,
and the fact table `testresults`.

## Contents

| File | What it is |
|---|---|
| `pygrametl1.py` | Original sequential program (Jython, JDBC) |
| `pygrametl2.py` | Original parallel program (Jython, JDBC): `ProcessSource`, `DecoupledDimension`, `DimensionPartitioner`, `DecoupledFactTable`, shared connection |
| `pygrametl1_cpython.py` | CPython 3 version of `pygrametl1.py` (psycopg2) |
| `pygrametl2_cpython.py` | CPython 3 version of `pygrametl2.py` (psycopg2) |
| `starschema.sql` | Creates the `pygrametlexa` schema and its tables |
| `datagenerator/` | Generates the input CSV files; `params-N.py` are the data set sizes |
| `run_jython.sh` | Runs the Jython programs |
| `run_cpython.sh` | Runs the CPython programs |
| `pdi-1-conn.ktr`, `pdi-2-conns.ktr` | The same ETL flow in Pentaho Data Integration, used for comparison in the paper |

The CPython versions only change the platform-specific lines (database driver, bulk loader,
`open()` instead of `file()`); they are marked with `# CPython:` in the code.

## Requirements (macOS)

```bash
brew install openjdk postgresql@18
brew services start postgresql@18
```

Everything else is downloaded by the scripts on first use: Jython 2.7.4, the PostgreSQL JDBC
driver, pygrametl 2.9 and psycopg2 (into `.venv`).

The programs connect to `jdbc:postgresql://localhost/chr?user=chr` (hard-coded by the original
author), so the scripts create a PostgreSQL user and database called `chr` if they are missing.

## Running

```bash
chmod +x run_jython.sh run_cpython.sh    # once

./run_jython.sh both                     # Jython: sequential + parallel
./run_cpython.sh both                    # CPython: sequential + parallel
```

Options (environment variables, put them before the command):

| Variable | Meaning | Default |
|---|---|---|
| `SIZE` | `small`, or `5`, `25`, `50`, `100` for `datagenerator/params-N.py` | `small` |
| `RUNS` | how many times to run each program | `1` |
| `REGEN` | `1` = regenerate the CSV files | `0` |

Example: the paper's smallest data set (1 million downloads, 5 million facts), three runs each:

```bash
SIZE=5 RUNS=3 ./run_jython.sh both
SIZE=5 RUNS=3 ./run_cpython.sh both
```

Every run prints its wall-clock and CPU time and the loaded row counts, and is appended to
`run/results.csv` (columns: `timestamp, runtime, program, size, run, real_s, user_s, sys_s,
page_versions, facts, total_errors`). The row counts must be identical for all four programs
on the same data set.

With the default `small` data set, the expected result is 801 page versions, 6000 facts
and 33385 total errors.


## Credits and license

`pygrametl1.py`, `pygrametl2.py`, `datagenerator/`, `starschema.sql` and the `.ktr` files are the
example programs by Christian Thomsen from the [pygrametl](https://github.com/chrthomsen/pygrametl)
repository. `pygrametl2.py` and the data generator are licensed under the GNU General Public
License version 2; the CPython versions are derived from them. pygrametl itself is BSD-licensed.

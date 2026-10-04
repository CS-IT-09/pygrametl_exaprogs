# Without CLEAR_CACHE run 1 SIZE = 5

## Jython

| Run | pygrametl1.py | pygrametl2.py |
| --- | ------------- | ------------- |
| 1   | 212.66s       | 102.91s       |
| 2   | 214.04s       | 94.47s        |
| 3   | 214.54s       | 94.28s        |
| 4   | 226.42s       | 96.17s        |
| 5   | 222.29s       | 96.10s        |
| 6   | 211.11s       | 104.68s       |
| 7   | 212.49s       | 102.94s       |
| --- | ------------- | ------------- |
| --- | Avg           | Avg           |
| --- | 215.20s       | 98.52s        |



## Cpython

| Run | pygrametl1.py | pygrametl2.py |
| --- | ------------- | ------------- |
| 1   | 127.28s       | 102.97s       |
| 2   | 124.84s       | 101.64s       |
| 3   | 129.51s       | 99.96s        |
| 4   | 125.43s       | 101.24s       |
| 5   | 124.66s       | 101.88s       |
| 6   | 125.06s       | 104.86s       |
| 7   | 124.76s       | 104.66s       |
| --- | ------------- | ------------- |
| --- | Avg           | Avg           |
| --- | 125.47s       | 102.48s       |



# Without CLEAR_CACHE run 2 SIZE = 5


## Jython

| Run | pygrametl1.py | pygrametl2.py |
| --- | ------------- | ------------- |
| 1   | 212.57s       | 91.02s        |
| 2   | 187.91s       | 89.83s        |
| 3   | 209.61s       | 90.10s        |
| 4   | 209.24s       | 105.41s       |
| 5   | 190.80s       | 99.14s        |
| 6   | 214.52s       | 93.21s        |
| 7   | 211.79s       | 92.66s        |
| --- | ------------- | ------------- |
| --- | Avg           | Avg           |
| --- | 206.80s       | 93.23s        |



## Cpython

| Run | pygrametl1.py | pygrametl2.py |
| --- | ------------- | ------------- |
| 1   | 120.68s       | 97.50s        |
| 2   | 157.66s       | 104.84s       |
| 3   | 121.00s       | 100.93s       |
| 4   | 115.71s       | 96.11s        |
| 5   | 111.80s       | 95.55s        |
| 6   | 113.00s       | 97.35s        |
| 7   | 112.02s       | 96.18s        |
| --- | ------------- | ------------- |
| --- | Avg           | Avg           |
| --- | 116.48s       | 97.61s        |



=== pygrametl1_cpython.py  (run 4 of 7) ===
Time:     real 125.43s   CPU 53.28s user + 8.51s sys
Memory:   peak 199.6 MB (all processes), largest process 199.1 MB
Disk:     0 reads / 0 writes (I/O operations), data warehouse 605.5 MB
Result:   599059 page versions, 5000000 facts, 26862851 total errors


=== sequential jinthon
Time:     real 226.42s   CPU 113.43s user + 12.98s sys
Memory:   peak 1066.7 MB (all processes), largest process 1066.4 MB
Disk:     0 reads / 0 writes (I/O operations), data warehouse 605.5 MB
Result:   599059 page versions, 5000000 facts, 26862851 total errors



# SIZE=25 (5 million downloads, 25 million facts)

Runtimes: Jython 2.7.4 on Java 26 with `JAVA_OPTS=-Xmx5g`; CPython 3.14.7 free-threaded (uv).


## Baseline: PostgreSQL default settings

max_wal_size=1GB
shared_buffers=128MB

### Jython

| Run | pygrametl1.py | pygrametl2.py |
| --- | ------------- | ------------- |
| 1   | 1450.70s      | 973.76s       |
| 2   | 1503.08s      | 966.36s       |
| 3   | 1530.46s      | 794.94s       |
| --- | ------------- | ------------- |
| --- | Avg           | Avg           |
| --- | 1494.75s      | 911.69s       |

### Cpython

| Run | pygrametl1.py | pygrametl2.py |
| --- | ------------- | ------------- |
| 1   | 824.21s       | 816.65s       |
| 2   | 823.56s       | 874.93s       |
| 3   | 885.53s       | 818.61s       |
| --- | ------------- | ------------- |
| --- | Avg           | Avg           |
| --- | 844.43s       | 836.73s       |

### Measurements (mean of the 3 runs)

|                                     | Jython seq | Jython par | CPython seq | CPython par |
| ----------------------------------- | ---------- | ---------- | ----------- | ----------- |
| Wall-clock time                     | 1494.8s    | 911.7s     | 844.4s      | 836.7s      |
| ETL program CPU (user + sys)        | 550.4s     | 1361.2s    | 265.4s      | 758.0s      |
| Peak memory (all processes)         | 1845 MB    | 2793 MB    | 256 MB      | 380 MB      |
| DB connection busy                  | 31.5%      | 49.0%      | 39.1%       | 54.1%       |
| DB connection waiting for the ETL   | 68.5%      | 51.0%      | 60.9%       | 45.9%       |
| SQL statement time                  | 620.8s     | 475.9s     | 358.5s      | 421.2s      |
| PostgreSQL CPU time                 | 620.6s     | 264.7s     | 240.8s      | 274.1s      |
| WAL written                         | 12.4 GB    | 12.5 GB    | 12.4 GB     | 12.6 GB     |
| Checkpoints (all forced by WAL)     | 23.3       | 24.0       | 23.3        | 23.7        |


- database grows faster than the data


## Tuned

max_wal_size=4GB
shared_buffers=1GB


### Jython

| Run | pygrametl1.py | pygrametl2.py |
| --- | ------------- | ------------- |
| 1   | 1013.22s      | 638.64s       |
| 2   | 1067.13s      | 606.76s       |
| 3   | 1085.74s      | 604.04s       |
| --- | ------------- | ------------- |
| --- | Avg           | Avg           |
| --- | 1055.36s      | 616.48s       |

2500000 -  445.28s - 4.56x time
500000 -  97.61s  

### Cpython

| Run | pygrametl1.py | pygrametl2.py |
| --- | ------------- | ------------- |
| 1   | 515.28s       | 444.72s       |
| 2   | 515.69s       | 445.89s       |
| 3   | 511.36s       | 445.23s       |
| --- | ------------- | ------------- |
| --- | Avg           | Avg           |
| --- | 514.11s       | 445.28s       |

### Measurements (mean of the 3 runs) and change from the baseline

|                                     | Jython seq         | Jython par        | CPython seq       | CPython par       |
| ----------------------------------- | ------------------ | ----------------- | ----------------- | ----------------- |
| Wall-clock time                     | 1055.4s            | 616.5s            | 514.1s            | 445.3s            |
| ETL program CPU (user + sys)        | 533.4s             | 1599.5s           | 263.6s            | 763.2s            |
| Peak memory (all processes)         | 1749 MB            | 2682 MB           | 256 MB            | 380 MB            |
| DB connection busy                  | 9.8% (was 31.5%)   | 36.3% (was 49.0%) | 11.5% (was 39.1%) | 26.2% (was 54.1%) |
| DB connection waiting for the ETL   | 90.2%              | 63.7%             | 88.5%             | 73.8%             |
| SQL statement time                  | 268.1s             | 204.0s            | 109.9s            | 125.2s            |
| PostgreSQL CPU time                 | 491.4s             | 256.4s            | 208.4s            | 239.2s            |
| WAL written                         | 5.7 GB (was 12.4)  | 5.5 GB (was 12.5) | 5.3 GB (was 12.4) | 5.5 GB (was 12.6) |
| Checkpoints (forced)                | 3.0 (0)            | 2.3 (2.3)         | 2.0 (2.0)         | 2.3 (2.3)         |



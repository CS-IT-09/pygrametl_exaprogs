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


=== sequential jython
Time:     real 226.42s   CPU 113.43s user + 12.98s sys
Memory:   peak 1066.7 MB (all processes), largest process 1066.4 MB
Disk:     0 reads / 0 writes (I/O operations), data warehouse 605.5 MB
Result:   599059 page versions, 5000000 facts, 26862851 total errors





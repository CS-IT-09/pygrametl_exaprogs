# TCP vs Unix Socket

pygrametl2_pg3.py, 3 measured runs in SIZE = 25 over TCP (host = 'localhost')
pygrametl2_pg3_socket.py, 3 measured runs in SIZE = 25 over the Unix socket (host = '/tmp')

Or we can use 
PGHOST=/tmp python ../bench.py python -X gil=0 ../pygrametl2_pg3.py
PGHOST=localhost python ../bench.py python -X gil=0 ../pygrametl2_pg3.py


| Connection | Wall per run (s) | Mean wall (s) | User (s) | Sys (s) | CPU (s) | PostgreSQL (s) | Cores busy |
|---|---|---|---|---|---|---|---|
| TCP (localhost) | 364.39 / 356.76 / 358.44 | 359.9 | 439.1 | 101.8 | 540.9 | 154.6 | 1.50 |
| **Unix socket (/tmp)** | 298.74 / 303.23 / 287.09 | **296.4** | 433.4 | 70.2 | 503.6 | 158.9 | 1.70 |


### Disadvantages

The Unix socket can't be used when:
- the database is on another machine
- PostgreSQL runs in docker or a virtual machine

When the database is remote, the waiting can only be reduced by sending fewer round trips, i.e. pipelining, batching or more caching.
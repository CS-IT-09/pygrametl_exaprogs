# CPython 3 version of pygrametl2.py (the parallel example program).
#
# The ETL logic and the parallel constructs (ProcessSource, DecoupledDimension,
# DimensionPartitioner, DecoupledFactTable, shared connection and sequence) are
# identical to pygrametl2.py. Only the platform-specific parts are changed:
#   - psycopg2 (a PEP 249 driver) + ConnectionWrapper instead of JDBC
#   - the bulk loader uses psycopg2's copy_from instead of the JDBC CopyManager
#   - open() instead of the Python 2 builtin file()
# Lines that differ from pygrametl2.py are marked with "# CPython:".
#
# On Jython the parallel parts run as threads in one JVM. On CPython they run
# as separate processes (because of the GIL); pygrametl.parallel switches the
# multiprocessing start method to "fork" for this.

#  Copyright (c) 2011 Christian Thomsen (chr@cs.aau.dk)
#
#  This file is free software: you may copy, redistribute and/or modify it
#  under the terms of the GNU General Public License version 2
#  as published by the Free Software Foundation.


import datetime
import sys
import time

import psycopg2                                         # CPython: instead of java.lang

import pygrametl
from pygrametl import ConnectionWrapper                 # CPython: instead of JDBCConnectionWrapper
from pygrametl.datasources import CSVSource, MergeJoiningSource, ProcessSource,\
    TransformingSource
from pygrametl.tables import CachedDimension, SnowflakedDimension,\
    SlowlyChangingDimension, BulkFactTable, FactTable, \
    DecoupledDimension, DecoupledFactTable, DimensionPartitioner
from pygrametl.parallel import shareconnectionwrapper,\
     getsharedsequencefactory


BATCHSIZE = 500


def pgbulkloader(name, atts, fieldsep, rowsep, nullval, filename):
    # Runs inside the process of the shared connection wrapper
    global rawconn
    with open(filename, 'r') as filehandle:             # CPython: COPY ... FROM STDIN via psycopg2
        cursor = rawconn.cursor()
        cursor.copy_from(file=filehandle, table=name, sep=fieldsep,
                         null=str(nullval), columns=atts)

# Connection to target DW:
rawconn = psycopg2.connect(host='localhost', dbname='chr', user='chr')  # CPython
shrdconn = shareconnectionwrapper(ConnectionWrapper(rawconn), 10,      # CPython
                                   (pgbulkloader,))
shrdconn.execute('set search_path to pygrametlexa')



def datehandling(row, namemapping):
    # This method is called from ensure(row) when the lookup of a date fails.
    # We have to calculate all date related fields and add them to the row.
    date = pygrametl.getvalue(row, 'date', namemapping)
    (year, month, day, hour, minute, second, weekday, dayinyear, dst) = \
        time.strptime(date, "%Y-%m-%d")
    (isoyear, isoweek, isoweekday) = \
        datetime.date(year, month, day).isocalendar()
    # We could use row[namemapping.get('day') or 'day'] = X to support name map.
    row['day'] = day
    row['month'] = month
    row['year'] = year
    row['week'] = isoweek
    row['weekyear'] = isoyear
    row['dateid'] = dayinyear + 366 * (year - 1990) #Allow dates from 1990-01-01
    return row


def extractdomaininfo(row):
    # Take the 'www.domain.org' part from 'http://www.domain.org/page.html'
    # We also the host name ('www') in the domain in this example.
    domaininfo = row['url'].split('/')[-2]
    row['domain'] = domaininfo
    # Take the top level which is the last part of the domain
    row['topleveldomain'] = domaininfo.split('.')[-1]

def extractserverinfo(row):
    # Find the server name from a string like "ServerName/Version"
    row['server'] = row['serverversion'].split('/')[0]


def convertsize(row):
    row['size'] = pygrametl.getint(row['size'])

# Dimension and fact table objects

def getpagediminstances():
    global shrdconn
    idfactory = getsharedsequencefactory(0)
    for i in range(2):
        yield DecoupledDimension(
            SlowlyChangingDimension(
            name='page',
            key='pageid',
            attributes=['url', 'size', 'domain', 'topleveldomain',
                        'serverversion', 'server',
                        'validfrom', 'validto', 'version'],
            lookupatts=['url'],
            versionatt='version',
            fromatt='validfrom',
            toatt='validto',
            srcdateatt='lastmoddate',
            cachesize=-1,
            prefill=True,
            idfinder=idfactory(),
            targetconnection=shrdconn.copy()),
            batchsize=BATCHSIZE, queuesize=10
            )

pagedim = DimensionPartitioner([pd for pd in getpagediminstances()])

testdim = CachedDimension(
    name='test',
    key='testid',
    attributes=['testname', 'testauthor'],
    lookupatts=['testname'],
    prefill=True,
    defaultidvalue=-1,
    targetconnection=shrdconn.copy())

datedim = CachedDimension(
    name='date',
    key='dateid',
    attributes=['date', 'day', 'month', 'year', 'week', 'weekyear'],
    lookupatts=['date'],
    rowexpander=datehandling,
    prefill=True,
    targetconnection=shrdconn.copy())

facttbl = DecoupledFactTable(
    BulkFactTable(
        name='testresults',
        keyrefs=['pageid', 'testid', 'dateid'],
        measures=['errors'],
        bulksize=250000,
        bulkloader=shrdconn.copy().pgbulkloader,
        usefilename=True),
    batchsize=BATCHSIZE, queuesize=10,
    consumes=pagedim.parts,
    returnvalues=False
    )


# Data sources - change the path if you have your files somewhere else
downloadlog = CSVSource(open('DownloadLog.csv', 'r'),   # CPython: open() instead of file()
                        delimiter='\t')


testresults = CSVSource(open('TestResults.csv', 'r'),   # CPython: open() instead of file()
                        delimiter='\t')


joineddata = MergeJoiningSource(downloadlog, 'localfile', testresults,
                                'localfile')

transformeddata = TransformingSource(joineddata, extractdomaininfo,
                                     extractserverinfo, convertsize)


inputdata = ProcessSource(transformeddata, batchsize=BATCHSIZE, queuesize=10)

def main():
    for row in inputdata:
        fact = {'errors':row['errors']}
        fact['pageid'] = pagedim.scdensure(row)
        fact['dateid'] = datedim.ensure(row, {'date':'downloaddate'})
        fact['testid'] = testdim.lookup(row, {'testname':'test'})
        facttbl.insert(fact)
    shrdconn.commit()
    # CPython: commit a second time. The decoupled page dimensions send their
    # INSERTs to the shared connection through multiprocessing queues, which
    # are written asynchronously by a feeder thread in each process. The first
    # commit() can therefore reach the shared connection before the last
    # INSERTs from the other processes, and those would be lost. The first
    # commit() does wait for all queued operations to be executed, so the
    # second commit() makes them permanent. (Not needed on Jython, where the
    # workers are threads sharing an in-memory queue.)
    shrdconn.commit()

if __name__ == '__main__':
    main()

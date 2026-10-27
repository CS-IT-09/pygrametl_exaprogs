begin;

-- drop old tables, SQL has no schema
drop table if exists testresults;
drop table if exists page;
drop table if exists test;
drop table if exists date;


-- tables
create table page(
   pageid int primary key,
   url varchar,
   size int,
   domain varchar,
   topleveldomain varchar,
   serverversion varchar,
   server varchar,
   validfrom date,
   validto date,
   version int
);

create table test(
   testid int primary key,
   testname varchar,
   testauthor varchar
);
insert into test values (0, 'Test0', 'Joe Doe'), (1, 'Test1', 'Joe Doe'), 
(2, 'Test2', 'Joe Doe'), (3, 'Test3', 'Joe Doe'), (4, 'Test4', 'Joe Doe'),
(-1, 'Unknown test', 'Unknown author');


create table date(
   dateid int primary key,
   date date,
   day int,
   month int,
   year int,
   week int,
   weekyear int
);

create table testresults(
   pageid int,
   testid int,
   dateid int,
   errors int,
   primary key(pageid, testid, dateid)
);



-- indexes
create index url_version_idx on page(url, version desc);

commit;
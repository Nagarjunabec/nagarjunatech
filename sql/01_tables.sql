-- =====================================================================================
-- 01_tables.sql  (NEW INSTALL ONLY - run FIRST in Supabase > SQL Editor)   Nagarjuna Tech Academy v14
--
-- !! WARNING: this file starts from scratch. It DELETES every old table and function
-- !! (students, subjects, leaves, sessions ...) and everything stored in them.
-- !! Run it on a new project, or when you are happy to lose all data.
-- !! Already running v12?  Do NOT run this file - run 02, 03 and 04 only (see README).
-- New install order:  01_tables.sql  ->  02_functions.sql  ->  03_admin_seed.sql
-- =====================================================================================
create extension if not exists pgcrypto with schema extensions;

-- ---- 1. remove everything from the old versions ----
do $$ declare r record; begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' loop
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop; end $$;

drop table if exists mark_values, mark_sheets, notifications, leaves, videos, email_log, login_attempts, hidden, shares, activity, sessions, labs, notices,
  materials, enrollments, cr_subjects, crs, students, classes, subjects, admins cascade;
drop policy if exists mat_ins on storage.objects;
drop policy if exists mat_del on storage.objects;

-- ---- 2. tables ----
create table admins(
  id uuid primary key default gen_random_uuid(),
  username text unique not null,                 -- admin login (e-mail, lower-case)
  name text, password_hash text not null,
  photo text);                                   -- profile photo (small JPEG as data URL)

create table subjects(                           -- one row per  SUBJECT + ACADEMIC YEAR,  e.g. DS-2026-2027
  id uuid primary key default gen_random_uuid(),
  code text unique not null,                     -- DS-2026-2027
  name text not null,                            -- DS
  year int not null,                             -- 2026  (the academic year starts in 2026 and ends in 2027)
  full_name text,                                -- Data Structures (optional)
  kind text not null default 'theory' check (kind in ('theory','lab')),   -- theory = theory only, lab = theory + lab
  created_at timestamptz default now());

create table students(
  id uuid primary key default gen_random_uuid(),
  regno text unique not null check (regno ~ '^[A-Z0-9]{5,15}$'),
  name text not null,
  email text not null,
  year smallint not null check (year between 1 and 4),   -- study year 1-4
  password_hash text not null,
  pw text not null,                              -- readable copy: only admin functions return it
  semester smallint check (semester between 1 and 8),   -- semester 1-8 (empty only for old students)
  mobile text, parent_mobile text,               -- 10-digit mobile numbers
  photo text,                                    -- profile photo (small JPEG as data URL)
  created_by text default 'admin',               -- admin / cr
  created_at timestamptz default now());

create table crs(                                -- class representatives, e.g. CSE-CR
  id uuid primary key default gen_random_uuid(),
  username text unique not null,
  name text, email text,
  password_hash text not null, pw text not null,
  photo text,
  created_at timestamptz default now());

create table cr_subjects(
  cr_id uuid references crs(id) on delete cascade,
  subject_id uuid references subjects(id) on delete cascade,
  primary key(cr_id, subject_id));

create table enrollments(                        -- which students belong to which subject
  subject_id uuid references subjects(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  primary key(subject_id, student_id));

create table materials(                          -- Google Drive links
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  category text not null check (category in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks')),
  title text not null, link text not null,
  created_at timestamptz default now());

create table videos(                             -- video lessons (links)
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  title text not null, link text not null,
  created_at timestamptz default now());

create table notices(
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  title text not null, message text, due_date date, due_time time,
  created_at timestamptz default now());

create table labs(                               -- lab experiments / assignments (Drive link and/or program text)
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  exp_no text, title text not null, task text, program text,
  lab_date date, lab_time time, link text,
  created_at timestamptz default now());

create table notifications(                      -- in-app bell notifications
  id bigint generated always as identity primary key,
  role text not null, user_id uuid not null,
  subject_id uuid references subjects(id) on delete cascade,
  kind text, title text, body text, link text,
  seen boolean not null default false,
  created_at timestamptz default now());
create index notif_user on notifications(role, user_id, id desc);

create table sessions(
  token text primary key,
  role text not null check (role in ('admin','cr','student')),
  user_id uuid not null,
  expires_at timestamptz not null default now() + interval '3 days');

create table email_log(
  id bigint generated always as identity primary key,
  kind text, to_email text, name text, subject text, status text, error text, message text,
  created_at timestamptz default now());

create table activity(id bigint generated always as identity primary key, msg text, created_at timestamptz default now());

create table login_attempts(key text primary key, fails int not null default 0,
  first_fail timestamptz not null default now(), locked_until timestamptz);

-- ---- 3. lock every table: the website can only use the functions in 02 ----
alter table admins enable row level security;      alter table subjects enable row level security;
alter table students enable row level security;    alter table crs enable row level security;
alter table cr_subjects enable row level security; alter table enrollments enable row level security;
alter table materials enable row level security;   alter table notices enable row level security;
alter table labs enable row level security;        alter table sessions enable row level security;
alter table email_log enable row level security;   alter table activity enable row level security;
alter table login_attempts enable row level security;
alter table videos enable row level security;      alter table notifications enable row level security;

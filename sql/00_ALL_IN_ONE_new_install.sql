-- =====================================================================================
-- 00_ALL_IN_ONE_new_install.sql      Nagarjuna Tech Academy   (v29)
-- Paste this WHOLE file in Supabase > SQL Editor > New query > Run.
-- It is ONE single file with EVERYTHING up to v28:  01 tables + 02 functions + 03 admin + 08 notices / lab programs
--   + 09 to 15 marks (tables, formula rules, column maximum + description, AB absent, CR view, row colors).
-- Old files 01 ... 15 are NOT needed for a new install.
-- USE IT FOR: a new / empty project, or when you want to start again from zero.
-- !! It DELETES all tables and data first. Do NOT run it on a project that has real data
--    (use 04_update_existing_database.sql + 02 + 03 for that, see README).
-- Result: all tables, all functions, admin  nagarjunabec2009@gmail.com  /  nagarjuna@2009
-- =====================================================================================



-- ############################ STEP 1 of 5 - tables (wipes everything) ############################
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

drop table if exists lab_batch_members, mark_values, mark_sheets, notifications, leaves, videos, email_log, login_attempts, hidden, shares, activity, sessions, labs, notices,
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


-- ############################ STEP 2 of 5 - functions ############################
-- =====================================================================================
-- 02_functions.sql  (new install: run SECOND.  existing v12 database: run 04_update_existing_database.sql first, then this)
-- Nagarjuna Tech Academy v14.  Safe to run again (create or replace). Deletes no data.
-- Every action of the website is one of these functions. Each one checks the login token,
-- so students can only read their own subjects, CRs can only add students, admin can do all.
-- v14: subject code DS-2026-2027, subject type (theory / theory + lab), marks share + lab sheet,
--      profile photos, student password = Reg No by default (admin can type another one, the student can change it),
--      CR password only by admin, forgot password (Reg No only), edit CR, e-mail recipients for content posts.
-- =====================================================================================

drop function if exists subject_add(text, text, int, text);        -- old signatures (v12), replaced below
drop function if exists subject_edit(text, uuid, text, int, text);

-- ---------- internal helpers (not callable from the website) ----------
create or replace function _s(t text) returns sessions language plpgsql security definer set search_path=public as $$
declare k sessions; begin select * into k from sessions where token=t and expires_at>now();
  if k.token is null then raise exception 'unauthorized'; end if; return k; end $$;

create or replace function _admin(t text) returns uuid language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t); if k.role<>'admin' then raise exception 'Only the admin can do this'; end if; return k.user_id; end $$;

-- returns 'admin' | 'cr' | 'student' if this login may open the subject, else raises
create or replace function _access(t text, sid uuid) returns text language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if k.role='admin' then return 'admin'; end if;
  if k.role='cr' and exists(select 1 from cr_subjects where cr_id=k.user_id and subject_id=sid) then return 'cr'; end if;
  if k.role='student' and exists(select 1 from enrollments where student_id=k.user_id and subject_id=sid) then return 'student'; end if;
  raise exception 'Not allowed'; end $$;

create or replace function _mysubs(k sessions) returns setof uuid language sql stable security definer set search_path=public as $$
  select id from subjects where k.role='admin'
  union select subject_id from cr_subjects where k.role='cr' and cr_id=k.user_id
  union select subject_id from enrollments where k.role='student' and student_id=k.user_id $$;

create or replace function _taken(u text) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from admins where upper(username)=upper(u)) or exists(select 1 from crs where upper(username)=upper(u))
      or exists(select 1 from students where upper(regno)=upper(u)) $$;

create or replace function _cleanup() returns void language sql security definer set search_path=public as $$
  delete from sessions where expires_at<now()
     or (role='student' and user_id not in (select id from students))
     or (role='cr' and user_id not in (select id from crs));
  delete from notifications where created_at < now()-interval '90 days'
     or (role='student' and user_id not in (select id from students))
     or (role='cr' and user_id not in (select id from crs)) $$;

-- notify every student and CR of a subject (the bell icon)
create or replace function _notify_subject(sid uuid, kd text, ti text, bd text, lk text) returns void language sql security definer set search_path=public as $$
  insert into notifications(role,user_id,subject_id,kind,title,body,link)
  select 'student', e.student_id, sid, kd, ti, bd, lk from enrollments e where e.subject_id=sid
  union all select 'cr', c.cr_id, sid, kd, ti, bd, lk from cr_subjects c where c.subject_id=sid $$;

-- login lock: 5 wrong tries within 15 minutes lock that ID for 15 minutes
create or replace function _throttle_check(k text) returns void language plpgsql security definer set search_path=public as $$
declare l login_attempts; begin select * into l from login_attempts where key=k;
  if l.locked_until is not null and l.locked_until>now() then
    raise exception 'Too many wrong attempts. Try again in % minute(s).', ceil(extract(epoch from (l.locked_until-now()))/60); end if; end $$;
create or replace function _throttle_fail(k text) returns void language plpgsql security definer set search_path=public as $$
declare l login_attempts; begin select * into l from login_attempts where key=k;
  if l.key is null or l.first_fail < now()-interval '15 minutes' then
    insert into login_attempts(key,fails,first_fail,locked_until) values(k,1,now(),null)
      on conflict (key) do update set fails=1, first_fail=now(), locked_until=null;
  else update login_attempts set fails=fails+1, locked_until=case when fails+1>=5 then now()+interval '15 minutes' end where key=k; end if; end $$;
create or replace function _throttle_ok(k text) returns void language sql security definer set search_path=public as $$ delete from login_attempts where key=k $$;

revoke all on function _s(text), _admin(text), _access(text,uuid), _mysubs(sessions), _taken(text), _cleanup(),
  _throttle_check(text), _throttle_fail(text), _throttle_ok(text), _notify_subject(uuid,text,text,text,text) from public, anon, authenticated;

-- ---------- login (admin e-mail, CR id or student Reg No in ONE box) ----------
-- Student password = Reg No: typing it in CAPS, small or Mixed letters all work.
create or replace function unified_login(u text, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare a admins; c crs; s students; k text; kk text;
begin
  kk:='login:'||lower(trim(coalesce(u,''))); perform _throttle_check(kk); perform _cleanup();
  k:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');

  select * into a from admins where username=lower(trim(u));
  if a.id is not null and a.password_hash=crypt(p,a.password_hash) then
    perform _throttle_ok(kk); insert into sessions(token,role,user_id,expires_at) values(k,'admin',a.id,now()+interval '8 hours');
    return json_build_object('role','admin','token',k,'name',coalesce(a.name,'Admin'),'sub','Admin','photo',a.photo); end if;

  select * into c from crs where username=upper(trim(u));
  if c.id is not null and (c.password_hash=crypt(p,c.password_hash) or c.password_hash=crypt(upper(btrim(p)),c.password_hash)) then
    perform _throttle_ok(kk); insert into sessions(token,role,user_id,expires_at) values(k,'cr',c.id,now()+interval '2 days');
    return json_build_object('role','cr','token',k,'name',coalesce(nullif(c.name,''),c.username),'sub','CR · '||c.username,'photo',c.photo); end if;

  select * into s from students where regno=upper(trim(u));
  if s.id is not null and (s.password_hash=crypt(p,s.password_hash) or s.password_hash=crypt(upper(btrim(p)),s.password_hash)) then
    perform _throttle_ok(kk); insert into sessions(token,role,user_id,expires_at) values(k,'student',s.id,now()+interval '3 days');
    return json_build_object('role','student','token',k,'name',s.name,'sub',s.regno||' · Year '||s.year,'photo',s.photo); end if;

  perform _throttle_fail(kk); return json_build_object('error','Invalid ID or password'); end $$;

-- Forgot password (login page): Reg No only. The password becomes the Reg No again (no e-mail, no random password).
create or replace function forgot_password(rg text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare s students; r text; kk text;
begin r:=upper(btrim(coalesce(rg,''))); kk:='forgot:'||r; perform _throttle_check(kk);
  select * into s from students where regno=r;
  if s.id is null then perform _throttle_fail(kk); return json_build_object('error','Reg No not found. Check it, or ask your admin.'); end if;
  update students set password_hash=crypt(r,gen_salt('bf',8)), pw=r where id=s.id;
  perform _throttle_ok(kk);
  return json_build_object('ok',true,'name',s.name); end $$;

create or replace function logout(t text) returns void language sql security definer set search_path=public as $$ delete from sessions where token=t $$;

-- ---------- subjects ----------
create or replace function subjects_list(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  return (select coalesce(json_agg(x order by x.year desc, x.code),'[]') from (
    select s.id, s.code, s.name, s.year, s.full_name, s.kind,
      (select count(*) from enrollments e where e.subject_id=s.id) as students,
      (select count(*) from materials m where m.subject_id=s.id and m.category not in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan')) as materials,
      (select count(*) from notices n where n.subject_id=s.id) as notices,
      (select count(*) from labs l where l.subject_id=s.id) as labs,
      (select count(*) from videos v where v.subject_id=s.id) as videos
    from subjects s where s.id in (select * from _mysubs(k))) x); end $$;

create or replace function dashboard(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  return json_build_object('role',k.role,
    'events',(select coalesce(json_agg(e order by e."date", e."time"),'[]') from (
        select 'Notice' as kind, n.title, s.code, n.due_date as "date", n.due_time as "time" from notices n join subjects s on s.id=n.subject_id
          where n.due_date is not null and n.subject_id in (select * from _mysubs(k))
        union all
        select 'Lab', trim('Exp '||coalesce(l.exp_no,'')||' '||l.title), s.code, l.lab_date, l.lab_time from labs l join subjects s on s.id=l.subject_id
          where l.lab_date is not null and l.subject_id in (select * from _mysubs(k))) e),
    'stats',case when k.role='admin' then json_build_object(
        'subjects',(select count(*) from subjects),'students',(select count(*) from students),'crs',(select count(*) from crs),
        'materials',(select count(*) from materials where category not in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan')),'videos',(select count(*) from videos),'notices',(select count(*) from notices),'labs',(select count(*) from labs),
        'emails_sent',(select count(*) from email_log where status='sent'),'emails_failed',(select count(*) from email_log where status='failed')) end,
    'activity',case when k.role='admin' then (select coalesce(json_agg(a),'[]') from (select msg,created_at from activity order by id desc limit 8) a) end); end $$;

-- k = 'theory' (theory only) or 'lab' (theory + lab).  The code is NAME-YEAR-NEXTYEAR, e.g. DS-2026-2027
create or replace function subject_add(t text, n text, y int, f text, k text) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); n:=upper(trim(coalesce(n,'')));
  if n !~ '^[A-Z0-9]{1,12}$' then raise exception 'Subject name: 1-12 letters/digits, no spaces (example: DS)'; end if;
  if coalesce(y,0) not between 2000 and 2100 then raise exception 'Enter a valid year (example: 2026)'; end if;
  if coalesce(k,'') not in ('theory','lab') then raise exception 'Choose: Theory only, or Theory + Lab'; end if;
  insert into subjects(code,name,year,full_name,kind) values(n||'-'||y||'-'||(y+1), n, y, nullif(trim(f),''), k);
  insert into activity(msg) values('Subject '||n||'-'||y||'-'||(y+1)||' created ('||case k when 'lab' then 'theory + lab' else 'theory only' end||')');
exception when unique_violation then raise exception 'This subject and year already exist'; end $$;

create or replace function subject_edit(t text, sid uuid, n text, y int, f text, k text) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); n:=upper(trim(coalesce(n,'')));
  if n !~ '^[A-Z0-9]{1,12}$' then raise exception 'Subject name: 1-12 letters/digits, no spaces (example: DS)'; end if;
  if coalesce(y,0) not between 2000 and 2100 then raise exception 'Enter a valid year (example: 2026)'; end if;
  if coalesce(k,'') not in ('theory','lab') then raise exception 'Choose: Theory only, or Theory + Lab'; end if;
  update subjects set name=n, year=y, code=n||'-'||y||'-'||(y+1), full_name=nullif(trim(coalesce(f,'')),''), kind=k where id=sid;
  if not found then raise exception 'Subject not found'; end if;
  insert into activity(msg) values('Subject '||n||'-'||y||'-'||(y+1)||' edited');
exception when unique_violation then raise exception 'This subject and year already exist'; end $$;

create or replace function subject_del(t text, sid uuid) returns void language plpgsql security definer set search_path=public as $$
declare ss uuid[]; cc uuid[]; cd text; begin perform _admin(t);
  select array_agg(student_id) into ss from enrollments where subject_id=sid;
  select array_agg(cr_id) into cc from cr_subjects where subject_id=sid;
  select code into cd from subjects where id=sid;
  delete from subjects where id=sid;
  delete from students where id=any(ss) and not exists(select 1 from enrollments e where e.student_id=students.id);
  delete from crs where id=any(cc) and not exists(select 1 from cr_subjects x where x.cr_id=crs.id);
  perform _cleanup(); insert into activity(msg) values('Subject '||coalesce(cd,'')||' deleted'); end $$;

create or replace function subject_content(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; begin r:=_access(t,sid);
  return json_build_object('role',r,
    'subject',(select json_build_object('id',id,'code',code,'name',name,'year',year,'full_name',full_name,'kind',kind) from subjects where id=sid),
    'materials',(select coalesce(json_agg(json_build_object('id',m.id,'category',m.category,'title',m.title,'link',m.link,'created_at',m.created_at)
        order by array_position(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks'],m.category), m.created_at),'[]') from materials m where m.subject_id=sid),
    'videos',(select coalesce(json_agg(v order by v.created_at desc),'[]') from videos v where v.subject_id=sid),
    'notices',(select coalesce(json_agg(n order by n.created_at desc),'[]') from notices n where n.subject_id=sid),
    'labs',(select coalesce(json_agg(l order by l.lab_date nulls last, l.lab_time nulls last, l.created_at),'[]') from labs l where l.subject_id=sid),
    'admin',(select json_build_object('name',coalesce(nullif(name,''),'Admin'),'photo',photo) from admins order by username limit 1),
    'crs',(select coalesce(json_agg(json_build_object('name',coalesce(nullif(c.name,''),c.username),'photo',c.photo) order by c.username),'[]') from crs c join cr_subjects x on x.cr_id=c.id where x.subject_id=sid)); end $$;

-- ---------- students (admin and CR can add; only admin can see passwords / change anything) ----------
-- Password of a new student: the one the admin / Excel gives, or empty = the Reg No (capitals). No random passwords.
-- The student can change it later (password_change). A password chosen by the student is NOT readable by the admin.
create or replace function subject_students(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; begin r:=_access(t,sid); if r='student' then raise exception 'Not allowed'; end if;
  return (select coalesce(json_agg(json_build_object('id',s.id,'regno',s.regno,'name',s.name,'email',s.email,'year',s.year,'semester',s.semester,'mobile',s.mobile,'parent_mobile',s.parent_mobile,
      'pw',case when r='admin' then s.pw end,'photo',s.photo) order by s.regno),'[]')
    from students s join enrollments e on e.student_id=s.id where e.subject_id=sid); end $$;

-- mobile number check: 10 digits (6-9 first). "+91", "91", "0", spaces and dashes in front are ignored. Returns the clean 10 digits.
create or replace function _mobile(m text, lbl text) returns text language plpgsql immutable as $$
declare d text; begin d:=regexp_replace(coalesce(m,''),'[^0-9]','','g');
  if length(d)=12 and left(d,2)='91' then d:=substr(d,3); elsif length(d)=11 and left(d,1)='0' then d:=substr(d,2); end if;
  if d !~ '^[6-9][0-9]{9}$' then raise exception '% must be a 10-digit mobile number', lbl; end if;
  return d; end $$;

create or replace function students_add(t text, sid uuid, rw jsonb) returns json language plpgsql security definer set search_path=public,extensions as $$
declare r text; x jsonb; rg text; nm text; em text; pwd text; ex students; nid uuid; sm int; mb text; pm text;
        added jsonb:='[]'; had jsonb:='[]'; bad jsonb:='[]';
begin r:=_access(t,sid); if r='student' then raise exception 'Not allowed'; end if;
  for x in select * from jsonb_array_elements(rw) loop
    rg:=upper(trim(coalesce(x->>'regno','')));
    begin
      if rg !~ '^[A-Z0-9]{5,15}$' then raise exception 'Reg No must be 5-15 letters/digits'; end if;
      select * into ex from students where regno=rg;
      if ex.id is not null then            -- already has an account: only add to this subject
        insert into enrollments(subject_id,student_id) values(sid,ex.id) on conflict do nothing;
        had:=had||jsonb_build_array(rg);
      else
        nm:=trim(coalesce(x->>'name','')); em:=trim(coalesce(x->>'email',''));
        if exists(select 1 from admins where upper(username)=rg) or exists(select 1 from crs where username=rg) then raise exception 'This ID is reserved'; end if;
        if length(nm)<2 then raise exception 'Name is required'; end if;
        if em !~ '^\S+@\S+\.\S+$' then raise exception 'Valid email is required'; end if;
        if coalesce(x->>'year','') !~ '^[1-4]$' then raise exception 'Year must be 1, 2, 3 or 4'; end if;
        if coalesce(x->>'semester','') !~ '^[1-8]$' then raise exception 'Semester must be 1 to 8'; end if;
        sm:=(x->>'semester')::int; mb:=_mobile(x->>'mobile','Mobile number'); pm:=_mobile(x->>'parent_mobile','Parent mobile number');
        pwd:=btrim(coalesce(x->>'password',''));
        if pwd='' or upper(pwd)=rg then pwd:=rg; end if;       -- empty or = Reg No (any letter case) -> the Reg No in capitals
        if length(pwd)<5 then raise exception 'Password must be at least 5 characters'; end if;
        insert into students(regno,name,email,year,semester,mobile,parent_mobile,password_hash,pw,created_by)
          values(rg,nm,em,(x->>'year')::int,sm,mb,pm,crypt(pwd,gen_salt('bf',8)),pwd,case when r='admin' then 'admin' else 'cr' end) returning id into nid;
        insert into enrollments(subject_id,student_id) values(sid,nid);
        added:=added||jsonb_build_array(jsonb_build_object('regno',rg,'name',nm,'email',em));
      end if;
    exception when others then bad:=bad||jsonb_build_array(jsonb_build_object('regno',rg,'why',sqlerrm)); end;
  end loop;
  if jsonb_array_length(added)>0 then insert into activity(msg) values(jsonb_array_length(added)||' student(s) added to '||(select code from subjects where id=sid)||' by '||r); end if;
  return json_build_object('added',added,'existing',had,'skipped',bad); end $$;

drop function if exists student_edit(text, uuid, text, text, text, int);
create or replace function student_edit(t text, i uuid, rg text, n text, e text, y int, sm int, mb text, pm text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare s students; begin perform _admin(t); rg:=upper(trim(coalesce(rg,'')));
  if rg !~ '^[A-Z0-9]{5,15}$' then raise exception 'Reg No must be 5-15 letters/digits'; end if;
  if exists(select 1 from admins where upper(username)=rg) or exists(select 1 from crs where username=rg) then raise exception 'This ID is reserved'; end if;
  if length(trim(coalesce(n,'')))<2 then raise exception 'Name is required'; end if;
  if trim(coalesce(e,'')) !~ '^\S+@\S+\.\S+$' then raise exception 'Valid email is required'; end if;
  if coalesce(y,0) not between 1 and 4 then raise exception 'Year must be 1-4'; end if;
  if coalesce(sm,0) not between 1 and 8 then raise exception 'Semester must be 1 to 8'; end if;
  mb:=_mobile(mb,'Mobile number'); pm:=_mobile(pm,'Parent mobile number');
  update students set regno=rg, name=trim(n), email=trim(e), year=y, semester=sm, mobile=mb, parent_mobile=pm where id=i returning * into s;
  if s.id is null then raise exception 'Student not found'; end if;
  return json_build_object('regno',s.regno,'name',s.name,'email',s.email,'year',s.year,'semester',s.semester,'mobile',s.mobile,'parent_mobile',s.parent_mobile,'password',s.pw);
exception when unique_violation then raise exception 'That Reg No is already used'; end $$;

-- p = the new password; send the Reg No itself to reset it to the default
-- p = the new password; send the Reg No itself to reset it to the default
create or replace function student_reset(t text, i uuid, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare s students; begin perform _admin(t);
  select * into s from students where id=i; if s.id is null then raise exception 'Student not found'; end if;
  p:=btrim(coalesce(p,''));
  if upper(p)=s.regno then p:=s.regno; end if;
  if length(p)<5 then raise exception 'Password must be at least 5 characters'; end if;
  update students set password_hash=crypt(p,gen_salt('bf',8)), pw=p where id=i returning * into s;
  delete from sessions where user_id=i;
  return json_build_object('regno',s.regno,'name',s.name,'email',s.email,'year',s.year,'password',s.pw); end $$;

-- removes the student from this subject; the account is deleted when no subject is left
create or replace function student_remove(t text, sid uuid, ids uuid[]) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  delete from enrollments where subject_id=sid and student_id=any(ids);
  delete from students where id=any(ids) and not exists(select 1 from enrollments e where e.student_id=students.id);
  perform _cleanup(); end $$;

create or replace function students_all(t text) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(json_build_object('id',s.id,'regno',s.regno,'name',s.name,'email',s.email,'year',s.year,'semester',s.semester,'mobile',s.mobile,'parent_mobile',s.parent_mobile,'pw',s.pw,'photo',s.photo,
      'created_by',s.created_by,'created_at',s.created_at,
      'subjects',(select coalesce(json_agg(json_build_object('id',sb.id,'code',sb.code) order by sb.code),'[]')
                  from enrollments e join subjects sb on sb.id=e.subject_id where e.student_id=s.id)) order by s.regno),'[]')
    from students s); end $$;

create or replace function student_delete(t text, ids uuid[]) returns int language plpgsql security definer set search_path=public as $$
declare n int; begin perform _admin(t);
  delete from students where id=any(ids); get diagnostics n = row_count;
  perform _cleanup(); insert into activity(msg) values(n||' student account(s) deleted'); return n; end $$;

-- ---------- CR accounts (admin only). Password: set by admin; the form suggests the CR ID itself ----------
create or replace function cr_list(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(json_build_object('id',c.id,'username',c.username,'name',c.name,'email',c.email,'pw',c.pw,'photo',c.photo) order by c.username),'[]')
    from crs c join cr_subjects x on x.cr_id=c.id where x.subject_id=sid); end $$;

create or replace function cr_add(t text, sid uuid, u text, n text, e text, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare c crs; ex boolean:=false; begin perform _admin(t); u:=upper(trim(coalesce(u,'')));
  if u !~ '^[A-Z0-9-]{3,20}$' then raise exception 'CR ID: 3-20 letters, digits or - (example: CSE-CR)'; end if;
  select * into c from crs where username=u;
  if c.id is not null then ex:=true;     -- same CR for one more subject
  else
    if _taken(u) then raise exception 'This ID is already used'; end if;
    p:=coalesce(nullif(btrim(coalesce(p,'')),''),u);
    if length(p)<3 then raise exception 'Password must be at least 3 characters'; end if;
    if trim(coalesce(e,''))<>'' and trim(e) !~ '^\S+@\S+\.\S+$' then raise exception 'Enter a valid email'; end if;
    insert into crs(username,name,email,password_hash,pw) values(u,nullif(trim(n),''),nullif(trim(e),''),crypt(p,gen_salt('bf',8)),p) returning * into c;
  end if;
  insert into cr_subjects(cr_id,subject_id) values(c.id,sid) on conflict do nothing;
  insert into activity(msg) values('CR '||u||' assigned to '||(select code from subjects where id=sid));
  return json_build_object('username',c.username,'name',c.name,'email',c.email,'password',c.pw,'existing',ex); end $$;

-- edit a CR: ID, name, e-mail, password
create or replace function cr_edit(t text, i uuid, u text, n text, e text, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare c crs; o crs; begin perform _admin(t); u:=upper(trim(coalesce(u,'')));
  select * into o from crs where id=i; if o.id is null then raise exception 'CR not found'; end if;
  if u !~ '^[A-Z0-9-]{3,20}$' then raise exception 'CR ID: 3-20 letters, digits or - (example: CSE-CR)'; end if;
  if u<>o.username and _taken(u) then raise exception 'This ID is already used'; end if;
  p:=btrim(coalesce(p,''));
  if length(p)<3 then raise exception 'Password must be at least 3 characters'; end if;
  if trim(coalesce(e,''))<>'' and trim(e) !~ '^\S+@\S+\.\S+$' then raise exception 'Enter a valid email'; end if;
  update crs set username=u, name=nullif(trim(coalesce(n,'')),''), email=nullif(trim(coalesce(e,'')),'') where id=i;
  if p<>o.pw then update crs set password_hash=crypt(p,gen_salt('bf',8)), pw=p where id=i; delete from sessions where user_id=i; end if;
  select * into c from crs where id=i;
  insert into activity(msg) values('CR '||c.username||' edited');
  return json_build_object('username',c.username,'name',c.name,'email',c.email,'password',c.pw);
exception when unique_violation then raise exception 'This ID is already used'; end $$;

-- reset a CR password to p (the form sends the CR ID itself)
create or replace function cr_reset(t text, i uuid, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare c crs; begin perform _admin(t);
  p:=btrim(coalesce(p,''));
  if length(p)<3 then raise exception 'Password must be at least 3 characters'; end if;
  update crs set password_hash=crypt(p,gen_salt('bf',8)), pw=p where id=i returning * into c;
  if c.id is null then raise exception 'CR not found'; end if;
  delete from sessions where user_id=i;
  return json_build_object('username',c.username,'name',c.name,'email',c.email,'password',c.pw); end $$;

create or replace function cr_remove(t text, sid uuid, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from cr_subjects where subject_id=sid and cr_id=i;
  delete from crs where id=i and not exists(select 1 from cr_subjects x where x.cr_id=crs.id); perform _cleanup(); end $$;

-- ---------- posting (admin) – every post also creates a bell notification; the website e-mails the students ----------
create or replace function material_add(t text, sid uuid, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare x jsonb; n int:=0; ti text; cd text; kd text; begin perform _admin(t);
  select kind into kd from subjects where id=sid; if kd is null then raise exception 'Subject not found'; end if;
  for x in select * from jsonb_array_elements(rw) loop
    if x->>'category' in ('Lab Marks','Lab Syllabus','Lab Lesson Plan') and kd<>'lab' then raise exception 'Lab Syllabus, Lab Lesson Plan and Lab Sheet are only for Theory + Lab subjects'; end if;
    if coalesce(x->>'category','') <> all(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks']) then raise exception 'Choose a valid category'; end if;
    if coalesce(x->>'link','') !~* '^https?://\S+$' then raise exception 'Every row needs a valid link (starting with https://)'; end if;
    ti:=coalesce(nullif(trim(x->>'title'),''), x->>'category');
    insert into materials(subject_id,category,title,link) values(sid,x->>'category',ti,trim(x->>'link')); n:=n+1;
  end loop;
  select code into cd from subjects where id=sid;
  insert into activity(msg) values(n||' material(s) added to '||cd);
  perform _notify_subject(sid,'material',cd||' · new upload',n||' item(s) added',
    'subject/'||cd||'/'||case when (rw->0->>'category') in ('Theory Syllabus','Lab Syllabus') then 'syllabus' when (rw->0->>'category') in ('Theory Lesson Plan','Lab Lesson Plan') then 'lessonplan' when (rw->0->>'category') in ('Mid 1','Mid 2','AAT1','AAT2') then 'marks' when (rw->0->>'category')='Lab Marks' then 'labsheet' else 'materials' end); return n; end $$;

create or replace function material_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from materials where id=i; end $$;

create or replace function video_add(t text, sid uuid, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare x jsonb; n int:=0; cd text; begin perform _admin(t);
  for x in select * from jsonb_array_elements(rw) loop
    if coalesce(x->>'link','') !~* '^https?://\S+$' then raise exception 'Every row needs a valid video link (starting with https://)'; end if;
    insert into videos(subject_id,title,link) values(sid,coalesce(nullif(trim(x->>'title'),''),'Lesson'),trim(x->>'link')); n:=n+1;
  end loop;
  select code into cd from subjects where id=sid;
  insert into activity(msg) values(n||' video lesson(s) added to '||cd);
  perform _notify_subject(sid,'video',cd||' · new video lesson',n||' video(s) added','subject/'||cd||'/videos'); return n; end $$;

create or replace function video_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from videos where id=i; end $$;

create or replace function notice_add(t text, sid uuid, ti text, msg text, d text, tm text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; begin perform _admin(t); if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter a title'; end if;
  insert into notices(subject_id,title,message,due_date,due_time) values(sid,trim(ti),nullif(trim(msg),''),nullif(trim(coalesce(d,'')),'')::date,nullif(trim(coalesce(tm,'')),'')::time);
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Notice posted in '||cd);
  perform _notify_subject(sid,'notice',cd||' · '||trim(ti),nullif(trim(msg),''),'subject/'||cd||'/notices'); end $$;

create or replace function notice_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from notices where id=i; end $$;

create or replace function lab_add(t text, sid uuid, ex text, ti text, task text, prog text, d text, tm text, lk text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; begin perform _admin(t);
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab programs are only for Theory + Lab subjects'; end if;
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter the experiment title'; end if;
  if coalesce(trim(prog),'')='' and coalesce(trim(lk),'')='' then raise exception 'Add a Drive link or paste the program (at least one of the two)'; end if;
  if coalesce(trim(lk),'')<>'' and trim(lk) !~* '^https?://\S+$' then raise exception 'The link must start with https://'; end if;
  if length(coalesce(prog,''))>30000 then raise exception 'Program text is too long (use a Drive link)'; end if;
  insert into labs(subject_id,exp_no,title,task,program,lab_date,lab_time,link)
    values(sid,nullif(trim(ex),''),trim(ti),nullif(trim(task),''),nullif(trim(prog),''),nullif(trim(coalesce(d,'')),'')::date,nullif(trim(coalesce(tm,'')),'')::time,nullif(trim(lk),''));
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Lab program posted in '||cd);
  perform _notify_subject(sid,'lab',cd||' · Lab '||coalesce(nullif(trim(ex),'')||' ','')||trim(ti),nullif(trim(task),''),'subject/'||cd||'/labs'); end $$;

create or replace function lab_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from labs where id=i; end $$;

-- ---------- e-mail ----------
-- students (with a valid e-mail) of the given subjects; sids = null means every subject
create or replace function email_recipients(t text, sids uuid[]) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(x),'[]') from (select distinct on (lower(s.email)) s.name, s.email, s.regno
    from students s join enrollments e on e.student_id=s.id
    where (sids is null or e.subject_id=any(sids)) and s.email ~ '^\S+@\S+\.\S+$' order by lower(s.email)) x); end $$;

create or replace function email_log_add(t text, rw jsonb) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t); if k.role='student' then raise exception 'Not allowed'; end if;
  insert into email_log(kind,to_email,name,subject,status,error,message)
  select x->>'kind',x->>'to_email',x->>'name',x->>'subject',x->>'status',x->>'error',x->>'message' from jsonb_array_elements(rw) x; end $$;

create or replace function email_log(t text, n int) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(x),'[]') from (select id,created_at,to_email,name,kind,subject,status,error,message from email_log order by id desc limit n) x); end $$;

create or replace function email_log_del(t text, ids bigint[]) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from email_log where id=any(ids); end $$;

create or replace function email_log_clear(t text) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from email_log; end $$;

-- ---------- profile photo + own password ----------
-- the photo is a small JPEG (about 5-10 KB) stored as a data URL; p = null removes it
create or replace function profile_get(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if k.role='admin' then return (select json_build_object('role','admin','name',coalesce(name,'Admin'),'id',username,'photo',photo) from admins where id=k.user_id); end if;
  if k.role='cr' then return (select json_build_object('role','cr','name',coalesce(nullif(name,''),username),'id',username,'photo',photo) from crs where id=k.user_id); end if;
  return (select json_build_object('role','student','name',name,'id',regno,'photo',photo) from students where id=k.user_id); end $$;

create or replace function profile_photo_set(t text, p text) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if p is not null and (p !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(p)>120000) then raise exception 'This photo cannot be used. Choose another one.'; end if;
  if k.role='admin' then update admins set photo=p where id=k.user_id;
  elsif k.role='cr' then update crs set photo=p where id=k.user_id;
  else update students set photo=p where id=k.user_id; end if; end $$;

-- a STUDENT changes his / her own password (CR and admin passwords are changed only by the admin)
create or replace function password_change(t text, old text, nw text) returns void language plpgsql security definer set search_path=public,extensions as $$
declare k sessions; s students; kk text; begin k:=_s(t);
  if k.role<>'student' then raise exception 'Only the admin can change this password'; end if;
  select * into s from students where id=k.user_id; kk:='pwchg:'||s.regno; perform _throttle_check(kk);
  if not (s.password_hash=crypt(coalesce(old,''),s.password_hash) or s.password_hash=crypt(upper(btrim(coalesce(old,''))),s.password_hash)) then
    perform _throttle_fail(kk); raise exception 'The current password is wrong'; end if;
  perform _throttle_ok(kk);
  nw:=btrim(coalesce(nw,''));
  if upper(nw)=s.regno then nw:=s.regno; end if;
  if length(nw)<5 then raise exception 'New password must be at least 5 characters'; end if;
  update students set password_hash=crypt(nw,gen_salt('bf',8)),
         pw=case when nw=s.regno then s.regno else '(set by the student)' end where id=s.id;
  delete from sessions where user_id=s.id and token<>t; end $$;

-- ---------- notifications (bell icon, for whoever is logged in) ----------
create or replace function notif_list(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  return (select coalesce(json_agg(x),'[]') from (select id,kind,title,body,link,seen,created_at from notifications
    where role=k.role and user_id=k.user_id order by id desc limit 60) x); end $$;

create or replace function notif_count(t text) returns int language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  return (select count(*) from notifications where role=k.role and user_id=k.user_id and not seen); end $$;

create or replace function notif_read(t text, ids bigint[]) returns void language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  update notifications set seen=true where role=k.role and user_id=k.user_id and (ids is null or id=any(ids)); end $$;

-- =====================================================================================
-- permissions + refresh  (keep at the END of this file)
-- The website (anon key) may call the functions above. The internal helpers stay private.
-- =====================================================================================
grant usage on schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
revoke all on function _s(text), _admin(text), _access(text,uuid), _mysubs(sessions), _taken(text), _cleanup(),
  _throttle_check(text), _throttle_fail(text), _throttle_ok(text), _notify_subject(uuid,text,text,text,text), _mobile(text,text) from public, anon, authenticated;
notify pgrst, 'reload schema';      -- Supabase reloads its function list ("Could not find the function ... in the schema cache")


-- ############################ STEP 3 of 5 - admin login ############################
-- =====================================================================================
-- 03_admin_seed.sql  (run LAST, after 01 and 02).  Safe to run again at any time.
--   Admin login   : nagarjunabec2009@gmail.com
--   Admin password: nagarjuna@2009
--   Admin name    : T Nagarjuna
-- The old admin (nextgencoders2024@gmail.com) is removed. Running this file again resets the
-- admin password to the value below. To change the login or password, edit the two values
-- here and run this file again. The password is stored only as a bcrypt hash.
-- =====================================================================================
delete from admins where username <> 'nagarjunabec2009@gmail.com';

insert into admins(username, name, password_hash)
values ('nagarjunabec2009@gmail.com', 'T Nagarjuna', extensions.crypt('nagarjuna@2009', extensions.gen_salt('bf', 8)))
on conflict (username) do update set password_hash = excluded.password_hash, name = excluded.name;

delete from sessions where role = 'admin';      -- everybody has to log in again

notify pgrst, 'reload schema';



-- ############################ STEP 4 of 5 - notices / lab programs (v26) ############################
-- =====================================================================================
-- 08_notice_labs_update.sql   (v26)    Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
--
-- NOTICES   : the "time" field is gone (date only). The message can now be formatted text
--             (bold, italic, underline, alignment, bullets, numbers). It is stored as safe HTML in notices.message;
--             old plain-text notices still display correctly.
-- LAB PROGRAMS : new columns  slot (9.00-11.30 / 11.30-2.00 / 2.00-4.30)  and  location (lab room).
--             Lab number is a number / "Lab 1 ... Lab 50" (any text up to 10 characters is accepted).
--             The program is a Drive link and / or code (at least one). Title is optional now.
-- =====================================================================================

alter table public.labs add column if not exists slot text;
alter table public.labs add column if not exists location text;

-- ---------- notices: date only, formatted message ----------
drop function if exists notice_add(text, uuid, text, text, text, text);
create or replace function notice_add(t text, sid uuid, ti text, msg text, d text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; begin perform _admin(t);
  if length(trim(coalesce(ti,'')))<1 then raise exception 'Enter a title'; end if;
  if length(coalesce(msg,''))>30000 then raise exception 'The notice is too long'; end if;
  insert into notices(subject_id,title,message,due_date,due_time)
    values(sid,trim(ti),nullif(trim(coalesce(msg,'')),''),nullif(trim(coalesce(d,'')),'')::date,null);
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Notice posted in '||cd);
  perform _notify_subject(sid,'notice',cd||' · '||trim(ti),null,'subject/'||cd||'/notices'); end $$;

-- ---------- lab programs: number, date, slot, location, Drive link and / or code ----------
drop function if exists lab_add(text, uuid, text, text, text, text, text, text, text);
create or replace function lab_add(t text, sid uuid, ex text, ti text, task text, prog text, d text, slot text, loc text, lk text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; n text; begin perform _admin(t);
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab programs are only for Theory + Lab subjects'; end if;
  n:=nullif(trim(coalesce(ex,'')),'');
  if n is null then raise exception 'Choose the lab number'; end if;
  if length(n)>10 then raise exception 'Lab number is too long'; end if;
  if coalesce(trim(prog),'')='' and coalesce(trim(lk),'')='' then raise exception 'Add a Drive link or paste the code (at least one of the two)'; end if;
  if coalesce(trim(lk),'')<>'' and trim(lk) !~* '^https?://\S+$' then raise exception 'The link must start with https://'; end if;
  if length(coalesce(prog,''))>30000 then raise exception 'The code is too long (use a Drive link)'; end if;
  insert into labs(subject_id,exp_no,title,task,program,lab_date,lab_time,link,slot,location)
    values(sid,n,coalesce(nullif(trim(ti),''),'Lab '||n),nullif(trim(task),''),nullif(trim(prog),''),nullif(trim(coalesce(d,'')),'')::date,null,nullif(trim(lk),''),nullif(trim(slot),''),nullif(trim(loc),''));
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Lab program posted in '||cd);
  perform _notify_subject(sid,'lab',cd||' · Lab '||n,nullif(trim(task),''),'subject/'||cd||'/labs'); end $$;

grant execute on function notice_add(text,uuid,text,text,text), lab_add(text,uuid,text,text,text,text,text,text,text,text) to anon, authenticated;
notify pgrst, 'reload schema';

-- ############################ STEP 5 of 5 - marks tables + marks functions (v26 to v28, final versions) ############################
-- =====================================================================================
-- MARKS SHARE (Theory Marks) and LAB MARKS, one sheet per subject
--   mark_sheets : the columns of the sheet (name, type 'marks' or 'formula', formula text, optional max marks) + Lab row colors
--   mark_values : one row per student, all his / her marks as JSON { columnId : number or "AB" }
-- ADMIN  : create / edit / delete columns, enter / edit / clear every row, row colors (Lab), download Excel / PDF / Word
-- CR     : sees the marks of every student of the assigned subjects (view only)
-- STUDENT: sees ONLY his / her own row
-- Theory Marks must always have the column "AAT 1".  A mark is a number (0 to the column maximum) or the text AB (absent).
-- =====================================================================================

create table if not exists public.mark_sheets(
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  kind text not null check (kind in ('theory','lab')),          -- theory = Marks Share, lab = Lab Marks
  cols jsonb not null default '[]'::jsonb,                      -- [{id,name,type:'marks'|'formula',f:'=SUM([A],[B])',max:10}]
  row_colors jsonb,                                             -- Lab Marks row colors (v28): {on,col,rows:[{from,color}]}  empty = defaults
  updated_at timestamptz default now(),
  unique(subject_id, kind));

create table if not exists public.mark_values(
  sheet_id uuid not null references public.mark_sheets(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  vals jsonb not null default '{}'::jsonb,                      -- { columnId : number }
  updated_at timestamptz default now(),
  primary key(sheet_id, student_id));

alter table public.mark_sheets enable row level security;       -- the website can only use the functions below
alter table public.mark_values enable row level security;

-- read: admin and CR = every student row, student = own row only (+ the Lab row color rules)
create or replace function marks_get(t text, sid uuid, kd text) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; sh mark_sheets; begin r:=_access(t,sid); k:=_s(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  select * into sh from mark_sheets where subject_id=sid and mark_sheets.kind=kd;
  return json_build_object('cols',coalesce(sh.cols,'[]'::jsonb),'row_colors',sh.row_colors,
    'rows',(select coalesce(json_agg(json_build_object('student_id',s.id,'regno',s.regno,'name',s.name,'vals',coalesce(v.vals,'{}'::jsonb)) order by s.regno),'[]')
        from students s join enrollments e on e.student_id=s.id and e.subject_id=sid
        left join mark_values v on v.student_id=s.id and v.sheet_id=sh.id
        where r in ('admin','cr') or s.id=k.user_id)); end $$;

-- admin: save the columns (create / rename / delete / formulas / maximum marks / description)
create or replace function marks_cols_save(t text, sid uuid, kd text, cols jsonb) returns void language plpgsql security definer set search_path=public as $$
declare sh uuid; keep text[]; c jsonb; ids text[]:='{}'; nm text; has_aat boolean:=false; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  if jsonb_typeof(cols)<>'array' or jsonb_array_length(cols)>60 then raise exception 'Too many columns (maximum 60)'; end if;
  for c in select * from jsonb_array_elements(cols) loop
    if jsonb_typeof(c)<>'object' then raise exception 'Wrong column data'; end if;
    if coalesce(c->>'id','') !~ '^[A-Za-z0-9]{1,20}$' or (c->>'id')=any(ids) then raise exception 'Wrong column id'; end if;
    ids:=ids||(c->>'id');
    nm:=btrim(coalesce(c->>'name',''));
    if length(nm) not between 1 and 40 or nm ~ '[\[\]]' then raise exception 'Column name: 1-40 characters, without [ or ]'; end if;
    if coalesce(c->>'type','') not in ('marks','formula') then raise exception 'Column type must be marks or formula'; end if;
    if c ? 'desc' and (jsonb_typeof(c->'desc')<>'string' or length(c->>'desc')>200) then raise exception 'Description of column "%" must be text of at most 200 characters', nm; end if;
    if c->>'type'='formula' then
      if coalesce(c->>'f','') !~ '^\s*=' then raise exception 'Formula of column "%" must start with =', nm; end if;
      if length(c->>'f')>300 then raise exception 'Formula of column "%" is too long (maximum 300 characters)', nm; end if;
      if (c->>'f') !~ '^[A-Za-z0-9_ \[\]()+\-*/^%,:.$<>=\"&]*$' then raise exception 'Formula of column "%" has a character that is not allowed', nm; end if;
    else
      if c ? 'max' and (jsonb_typeof(c->'max')<>'number' or (c->>'max')::numeric <= 0 or (c->>'max')::numeric > 1000) then
        raise exception 'Maximum marks of column "%" must be a number from 1 to 1000', nm; end if;
      if kd='theory' and lower(nm)='aat 1' then has_aat:=true; end if;
    end if;
  end loop;
  if kd='theory' and not has_aat then raise exception 'The column "AAT 1" is mandatory in Theory Marks'; end if;
  insert into mark_sheets(subject_id,kind,cols) values(sid,kd,cols)
    on conflict (subject_id,kind) do update set cols=excluded.cols, updated_at=now() returning id into sh;
  select array_agg(x->>'id') into keep from jsonb_array_elements(cols) x;       -- marks of deleted columns are removed
  update mark_values set vals=(select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(mark_values.vals) where key=any(coalesce(keep,'{}'))) where sheet_id=sh; end $$;

-- admin: save marks.  rw = [{student_id, vals:{colId:number or "AB"}}]   (only students of this subject)
create or replace function marks_save(t text, sid uuid, kd text, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare sh uuid; x jsonb; n int:=0; cl jsonb; e record; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  insert into mark_sheets(subject_id,kind) values(sid,kd) on conflict (subject_id,kind) do nothing;
  select id, cols into sh, cl from mark_sheets where subject_id=sid and kind=kd;
  for x in select * from jsonb_array_elements(rw) loop
    if jsonb_typeof(x->'vals')<>'object' or length((x->'vals')::text)>6000 then raise exception 'Wrong marks data'; end if;
    for e in select key, value from jsonb_each(x->'vals') loop
      if jsonb_typeof(e.value)='string' then
        if upper(btrim(e.value#>>'{}'))<>'AB' then raise exception 'A mark must be a number or AB (absent)'; end if;
      elsif jsonb_typeof(e.value)<>'number' or (e.value#>>'{}')::numeric < 0 then raise exception 'Marks must be numbers (or AB), not negative';
      elsif exists(select 1 from jsonb_array_elements(coalesce(cl,'[]'::jsonb)) k where k->>'id'=e.key and k ? 'max' and (k->>'max')::numeric < (e.value#>>'{}')::numeric) then
        raise exception 'A mark is above the maximum marks of its column';
      end if;
    end loop;
    if exists(select 1 from enrollments where subject_id=sid and student_id=(x->>'student_id')::uuid) then
      insert into mark_values(sheet_id,student_id,vals) values(sh,(x->>'student_id')::uuid,x->'vals')
        on conflict (sheet_id,student_id) do update set vals=excluded.vals, updated_at=now(); n:=n+1; end if;
  end loop; return n; end $$;

-- admin: delete the marks of one student row
create or replace function marks_row_clear(t text, sid uuid, kd text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  delete from mark_values where student_id=i and sheet_id=(select id from mark_sheets where subject_id=sid and kind=kd); end $$;

-- admin: delete the whole sheet (columns + all marks)
create or replace function marks_sheet_del(t text, sid uuid, kd text) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from mark_sheets where subject_id=sid and kind=kd; end $$;

-- admin: Lab Marks row colors  (null = back to the default colors)
create or replace function marks_rules_save(t text, sid uuid, kd text, rc jsonb) returns void language plpgsql security definer set search_path=public as $$
declare x jsonb; froms numeric[]:='{}'; f numeric; begin perform _admin(t);
  if kd<>'lab' then raise exception 'Row colors are only for Lab Marks'; end if;
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  if rc is not null and jsonb_typeof(rc)<>'null' then
    if jsonb_typeof(rc)<>'object' or coalesce(jsonb_typeof(rc->'on'),'')<>'boolean' then raise exception 'Wrong color data'; end if;
    if coalesce(rc->>'col','') !~ '^[A-Za-z0-9]{1,20}$' then raise exception 'Choose the column that decides the color'; end if;
    if coalesce(jsonb_typeof(rc->'rows'),'')<>'array' then raise exception 'Give 1 to 10 color ranges'; end if;
    if jsonb_array_length(rc->'rows') not between 1 and 10 then raise exception 'Give 1 to 10 color ranges'; end if;
    for x in select * from jsonb_array_elements(rc->'rows') loop
      if jsonb_typeof(x)<>'object' then raise exception 'Wrong color data'; end if;
      if coalesce(jsonb_typeof(x->'from'),'')<>'number' then raise exception 'Every color range needs a "from" number'; end if;
      f:=(x->>'from')::numeric;
      if f<0 or f>1000 then raise exception 'A "from" mark must be between 0 and 1000'; end if;
      if f=any(froms) then raise exception 'Two color ranges start at the same mark (%)', f; end if;
      froms:=froms||f;
      if coalesce(x->>'color','') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'A color must look like #16a34a'; end if;
    end loop;
  else rc:=null; end if;
  insert into mark_sheets(subject_id,kind,row_colors) values(sid,kd,rc)
    on conflict (subject_id,kind) do update set row_colors=excluded.row_colors, updated_at=now(); end $$;

grant execute on function marks_get(text,uuid,text), marks_cols_save(text,uuid,text,jsonb), marks_save(text,uuid,text,jsonb),
  marks_row_clear(text,uuid,text,uuid), marks_sheet_del(text,uuid,text), marks_rules_save(text,uuid,text,jsonb) to anon, authenticated;
notify pgrst, 'reload schema';


-- =====================================================================================
-- v30: LAB BATCHES (same content as 16_lab_batches.sql)
-- =====================================================================================
-- =====================================================================================
-- 16_lab_batches.sql   (v30)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- Run it AFTER 08 (and the other files up to 15).   Old SQL files are NOT changed.
--
-- LAB BATCHES (Theory + Lab subjects only)
--   * The admin splits the students of a subject into Batch 1 and Batch 2 (by Reg No) and gives each batch a color.
--   * A lab program is posted for ONE batch.  A student sees only the lab programs of his / her own batch
--     (lab programs posted before v30 have no batch and stay visible to everybody).  Admin and CR see all.
--   * Lab Marks can be shown batch-wise (the website reads the batch of every student with batches_get).
--
-- What this file does
--   1. labs.batch            : new column (1 or 2, empty = old lab program for everybody)
--   2. subjects.batch_colors : the two batch colors, e.g. {"1":"#2563eb","2":"#f59e0b"}
--   3. lab_batch_members     : new table, which student is in which batch of a subject
--   4. batches_get / batches_save : NEW functions (read / save the batches)
--   5. subject_content       : same as before, but a student gets only his / her batch's lab programs
--   6. lab_add               : new last parameter  bt  (the batch, 1 or 2); the bell notification goes to that batch only
-- =====================================================================================

alter table public.labs     add column if not exists batch smallint;
alter table public.labs     drop constraint if exists labs_batch_check;
alter table public.labs     add  constraint labs_batch_check check (batch is null or batch in (1,2));
alter table public.subjects add column if not exists batch_colors jsonb;

create table if not exists public.lab_batch_members(
  subject_id uuid not null references public.subjects(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  batch smallint not null check (batch in (1,2)),
  primary key(subject_id, student_id));                       -- one student is in ONE batch of a subject
alter table public.lab_batch_members enable row level security;     -- the website can only use the functions below

-- read: admin / CR = every student of the subject that is in a batch;  student = only his / her own batch
create or replace function batches_get(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; begin r:=_access(t,sid); k:=_s(t);
  return json_build_object(
    'colors',coalesce((select batch_colors from subjects where id=sid),'{}'::jsonb),
    'rows',(select coalesce(json_agg(json_build_object('student_id',m.student_id,'regno',s.regno,'batch',m.batch) order by s.regno),'[]')
        from lab_batch_members m join students s on s.id=m.student_id
        join enrollments e on e.student_id=m.student_id and e.subject_id=sid
        where m.subject_id=sid and (r in ('admin','cr') or m.student_id=k.user_id))); end $$;

-- admin: save the batches.  rw = [{student_id, batch:1|2}]  (ALL students that are in a batch; the rest are in none)
--                           colors = {"1":"#rrggbb","2":"#rrggbb"}  (or null = keep the colors as they are)
create or replace function batches_save(t text, sid uuid, rw jsonb, colors jsonb) returns int language plpgsql security definer set search_path=public as $$
declare x jsonb; n int:=0; cd text; begin perform _admin(t);
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Batches are only for Theory + Lab subjects'; end if;
  if jsonb_typeof(rw)<>'array' then raise exception 'Wrong batch data'; end if;
  if colors is not null and jsonb_typeof(colors)<>'null' then
    if jsonb_typeof(colors)<>'object' or coalesce(colors->>'1','') !~ '^#[0-9A-Fa-f]{6}$' or coalesce(colors->>'2','') !~ '^#[0-9A-Fa-f]{6}$' then
      raise exception 'A batch color must look like #2563eb'; end if;
    update subjects set batch_colors=jsonb_build_object('1',colors->>'1','2',colors->>'2') where id=sid;
  end if;
  delete from lab_batch_members where subject_id=sid;
  for x in select * from jsonb_array_elements(rw) loop
    if coalesce(x->>'batch','') not in ('1','2') then raise exception 'The batch must be 1 or 2'; end if;
    if exists(select 1 from enrollments where subject_id=sid and student_id=(x->>'student_id')::uuid) then
      insert into lab_batch_members(subject_id,student_id,batch) values(sid,(x->>'student_id')::uuid,(x->>'batch')::smallint)
        on conflict (subject_id,student_id) do update set batch=excluded.batch; n:=n+1; end if;
  end loop;
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Lab batches saved in '||cd);
  return n; end $$;

-- subject_content: same as before; only 'labs' changed (a student sees his / her batch + the old lab programs without a batch)
create or replace function subject_content(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; mb smallint; begin r:=_access(t,sid); k:=_s(t);
  if r='student' then select batch into mb from lab_batch_members where subject_id=sid and student_id=k.user_id; end if;
  return json_build_object('role',r,
    'subject',(select json_build_object('id',id,'code',code,'name',name,'year',year,'full_name',full_name,'kind',kind) from subjects where id=sid),
    'materials',(select coalesce(json_agg(json_build_object('id',m.id,'category',m.category,'title',m.title,'link',m.link,'created_at',m.created_at)
        order by array_position(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks'],m.category), m.created_at),'[]') from materials m where m.subject_id=sid),
    'videos',(select coalesce(json_agg(v order by v.created_at desc),'[]') from videos v where v.subject_id=sid),
    'notices',(select coalesce(json_agg(n order by n.created_at desc),'[]') from notices n where n.subject_id=sid),
    'labs',(select coalesce(json_agg(l order by l.lab_date nulls last, l.lab_time nulls last, l.created_at),'[]') from labs l
        where l.subject_id=sid and (r<>'student' or l.batch is null or l.batch=mb)),
    'admin',(select json_build_object('name',coalesce(nullif(name,''),'Admin'),'photo',photo) from admins order by username limit 1),
    'crs',(select coalesce(json_agg(json_build_object('name',coalesce(nullif(c.name,''),c.username),'photo',c.photo) order by c.username),'[]') from crs c join cr_subjects x on x.cr_id=c.id where x.subject_id=sid)); end $$;

-- lab_add: new last parameter  bt = batch (1 or 2).  The program is posted for that batch only.
drop function if exists lab_add(text, uuid, text, text, text, text, text, text, text, text);
create or replace function lab_add(t text, sid uuid, ex text, ti text, task text, prog text, d text, slot text, loc text, lk text, bt int) returns void language plpgsql security definer set search_path=public as $$
declare cd text; n text; begin perform _admin(t);
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab programs are only for Theory + Lab subjects'; end if;
  if bt is null or bt not in (1,2) then raise exception 'Choose the batch (Batch 1 or Batch 2)'; end if;
  if not exists(select 1 from lab_batch_members m join enrollments e on e.student_id=m.student_id and e.subject_id=sid where m.subject_id=sid and m.batch=bt) then
    raise exception 'Batch % has no students yet. Create the batches first.', bt; end if;
  n:=nullif(trim(coalesce(ex,'')),'');
  if n is null then raise exception 'Choose the lab number'; end if;
  if length(n)>10 then raise exception 'Lab number is too long'; end if;
  if coalesce(trim(prog),'')='' and coalesce(trim(lk),'')='' then raise exception 'Add a Drive link or paste the code (at least one of the two)'; end if;
  if coalesce(trim(lk),'')<>'' and trim(lk) !~* '^https?://\S+$' then raise exception 'The link must start with https://'; end if;
  if length(coalesce(prog,''))>30000 then raise exception 'The code is too long (use a Drive link)'; end if;
  insert into labs(subject_id,exp_no,title,task,program,lab_date,lab_time,link,slot,location,batch)
    values(sid,n,coalesce(nullif(trim(ti),''),'Lab '||n),nullif(trim(task),''),nullif(trim(prog),''),nullif(trim(coalesce(d,'')),'')::date,null,nullif(trim(lk),''),nullif(trim(slot),''),nullif(trim(loc),''),bt);
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Lab program posted in '||cd||' for batch '||bt);
  insert into notifications(role,user_id,subject_id,kind,title,body,link)           -- bell: only the students of that batch + the CRs
    select 'student', m.student_id, sid, 'lab', cd||' · Lab '||n||' (Batch '||bt||')', nullif(trim(task),''), 'subject/'||cd||'/labs'
      from lab_batch_members m join enrollments e on e.student_id=m.student_id and e.subject_id=sid where m.subject_id=sid and m.batch=bt
    union all select 'cr', c.cr_id, sid, 'lab', cd||' · Lab '||n||' (Batch '||bt||')', nullif(trim(task),''), 'subject/'||cd||'/labs' from cr_subjects c where c.subject_id=sid; end $$;

grant execute on function batches_get(text,uuid), batches_save(text,uuid,jsonb,jsonb), subject_content(text,uuid),
  lab_add(text,uuid,text,text,text,text,text,text,text,text,int) to anon, authenticated;
notify pgrst, 'reload schema';

-- ===== v36: marks Publish + Timetable (same as 17_marks_publish_timetable.sql) =====
-- =====================================================================================
-- 17_marks_publish_timetable.sql   (v36)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
--
-- 1. MARKS PUBLISH:  every Theory Marks / Lab Marks sheet gets a  published  flag.
--      - Sheets that already exist stay VISIBLE (published = true), nothing changes for them.
--      - A NEW sheet starts as NOT published: the students (and the CR) see nothing until the admin presses "Publish".
--      - The admin always sees everything.  Publishing sends a bell notification to the students of the subject.
--    marks_get      : changed (returns  published ; hides columns + rows from students / CR while not published)
--    marks_publish  : new (admin) - publish or unpublish a sheet
-- 2. TIMETABLE:  one timetable for every  Year + Semester  (Monday to Saturday, 9 periods, merged cells, lab blocks).
--    timetables     : new table
--    timetable_get  : a student gets the timetable of his / her own year + semester;  admin / CR choose year + semester
--    timetable_save : new (admin)      timetable_del : new (admin)
-- =====================================================================================

alter table public.mark_sheets add column if not exists published boolean;
update public.mark_sheets set published=true where published is null;           -- old sheets stay visible
alter table public.mark_sheets alter column published set default false;        -- new sheets start hidden
alter table public.mark_sheets alter column published set not null;

create or replace function marks_get(t text, sid uuid, kd text) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; sh mark_sheets; show boolean; begin r:=_access(t,sid); k:=_s(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  select * into sh from mark_sheets where subject_id=sid and mark_sheets.kind=kd;
  show := (r='admin') or coalesce(sh.published,false);                            -- students and CR: only after Publish
  return json_build_object('published',coalesce(sh.published,false),
    'cols',case when show then coalesce(sh.cols,'[]'::jsonb) else '[]'::jsonb end,'row_colors',case when show then sh.row_colors else null end,
    'rows',case when not show then '[]'::json else (select coalesce(json_agg(json_build_object('student_id',s.id,'regno',s.regno,'name',s.name,'vals',coalesce(v.vals,'{}'::jsonb)) order by s.regno),'[]')
        from students s join enrollments e on e.student_id=s.id and e.subject_id=sid
        left join mark_values v on v.student_id=s.id and v.sheet_id=sh.id
        where r in ('admin','cr') or s.id=k.user_id) end); end $$;

create or replace function marks_publish(t text, sid uuid, kd text, pub boolean) returns void language plpgsql security definer set search_path=public as $$
declare was boolean; cd text; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  insert into mark_sheets(subject_id,kind) values(sid,kd) on conflict (subject_id,kind) do nothing;
  select published into was from mark_sheets where subject_id=sid and kind=kd;
  update mark_sheets set published=coalesce(pub,false), updated_at=now() where subject_id=sid and kind=kd;
  if coalesce(pub,false) and not was then
    select code into cd from subjects where id=sid;
    perform _notify_subject(sid,'marks',cd||' · '||case when kd='lab' then 'Lab Marks' else 'Theory Marks' end||' published','Your marks are now available.',
      'subject/'||cd||'/'||case when kd='lab' then 'labsheet' else 'marks' end);
  end if; end $$;

-- ---------- timetable ----------
create table if not exists public.timetables(
  year smallint not null check (year between 1 and 4),
  semester smallint not null check (semester between 1 and 8),
  data jsonb not null default '{}'::jsonb,                  -- { periods:[[start,end]...9], days:{ Monday:[{n:1,t:'DS',k:'t'}...] ... } }
  updated_at timestamptz default now(),
  primary key(year,semester));
alter table public.timetables enable row level security;    -- the website can only use the functions below

create or replace function timetable_get(t text, yr int default null, sm int default null) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; s students; x timetables; begin k:=_s(t);
  if k.role='student' then
    select * into s from students where id=k.user_id; yr:=s.year; sm:=s.semester;
    select * into x from timetables where year=yr and (sm is null or semester=sm) order by semester desc limit 1;
  else
    select * into x from timetables where year=yr and semester=sm;
  end if;
  return json_build_object('year',coalesce(x.year,yr),'semester',coalesce(x.semester,sm),'data',x.data,
    'list',case when k.role='student' then '[]'::json else (select coalesce(json_agg(json_build_object('year',year,'semester',semester) order by year,semester),'[]') from timetables) end); end $$;

create or replace function timetable_save(t text, yr int, sm int, d jsonb) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  if yr is null or yr not between 1 and 4 or sm is null or sm not between 1 and 8 then raise exception 'Choose the year (1-4) and the semester (1-8)'; end if;
  if jsonb_typeof(d)<>'object' or length(d::text)>40000 then raise exception 'Wrong timetable data'; end if;
  insert into timetables(year,semester,data) values(yr,sm,d) on conflict (year,semester) do update set data=excluded.data, updated_at=now(); end $$;

create or replace function timetable_del(t text, yr int, sm int) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from timetables where year=yr and semester=sm; end $$;

grant execute on function marks_get(text,uuid,text), marks_publish(text,uuid,text,boolean),
  timetable_get(text,int,int), timetable_save(text,int,int,jsonb), timetable_del(text,int,int) to anon, authenticated;
notify pgrst, 'reload schema';

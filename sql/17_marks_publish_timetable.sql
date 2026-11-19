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

-- =====================================================================================
-- 06_add_syllabus_lesson_plan.sql   (v20)
-- Adds two new subject tabs:  SYLLABUS  and  LESSON PLAN   (placed after Students)
--   Theory only  : Theory Syllabus, Theory Lesson Plan
--   Theory + Lab : Theory Syllabus, Lab Syllabus, Theory Lesson Plan, Lab Lesson Plan
-- Run this ONE file in Supabase > SQL Editor > Run.  Keeps all your data.  Safe to run again.
-- (New install?  00_ALL_IN_ONE_new_install.sql already contains this - you do not need this file.)
-- =====================================================================================

-- 1) allow the 4 new categories in the materials table
do $$ declare c text; begin
  for c in select conname from pg_constraint where conrelid='public.materials'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%category%' loop
    execute 'alter table public.materials drop constraint '||quote_ident(c);
  end loop;
end $$;
alter table public.materials add constraint materials_category_check check (category in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks'));

-- 2) functions (syllabus / lesson plan are not counted in the "Materials" numbers)

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

create or replace function subject_content(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; begin r:=_access(t,sid);
  return json_build_object('role',r,
    'subject',(select json_build_object('id',id,'code',code,'name',name,'year',year,'full_name',full_name,'kind',kind) from subjects where id=sid),
    'materials',(select coalesce(json_agg(json_build_object('id',m.id,'category',m.category,'title',m.title,'link',m.link,'created_at',m.created_at)
        order by array_position(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks'],m.category), m.created_at),'[]') from materials m where m.subject_id=sid),
    'videos',(select coalesce(json_agg(v order by v.created_at desc),'[]') from videos v where v.subject_id=sid),
    'notices',(select coalesce(json_agg(n order by n.created_at desc),'[]') from notices n where n.subject_id=sid),
    'labs',(select coalesce(json_agg(l order by l.lab_date nulls last, l.lab_time nulls last, l.created_at),'[]') from labs l where l.subject_id=sid)); end $$;

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

-- 3) permissions + refresh
grant usage on schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
notify pgrst, 'reload schema';

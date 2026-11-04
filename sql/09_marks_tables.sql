-- =====================================================================================
-- 09_marks_tables.sql   (v26)    Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
--
-- MARKS SHARE (theory marks) and LAB MARKS tables, one sheet per subject:
--   mark_sheets : the columns of the sheet (name, type 'marks' or 'formula', the formula text)
--   mark_values : one row per student, all his / her marks as JSON { columnId : number }
-- Rows = every student of the subject (they come from the Students tab automatically).
-- ADMIN  : create / rename / delete columns, type formulas, edit / clear every row, download Excel / PDF / Word.
-- STUDENT: sees ONLY his / her own row.       CR: sees the column names only (no marks).
-- Formulas are calculated by the website, e.g.  =SUM([AAT 1],[AAT 2])   =[Mid 1]+[Mid 2]   =AVG([AAT 1],[AAT 2])
-- =====================================================================================

create table if not exists public.mark_sheets(
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  kind text not null check (kind in ('theory','lab')),          -- theory = Marks Share, lab = Lab Marks
  cols jsonb not null default '[]'::jsonb,                      -- [{id,name,type:'marks'|'formula',f:'=SUM([A],[B])'}]
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

-- read: admin = every student row, student = own row only, CR = columns only
create or replace function marks_get(t text, sid uuid, kd text) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; sh mark_sheets; begin r:=_access(t,sid); k:=_s(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  select * into sh from mark_sheets where subject_id=sid and mark_sheets.kind=kd;
  return json_build_object('cols',coalesce(sh.cols,'[]'::jsonb),
    'rows',case when r='cr' then '[]'::json else (select coalesce(json_agg(json_build_object('student_id',s.id,'regno',s.regno,'name',s.name,'vals',coalesce(v.vals,'{}'::jsonb)) order by s.regno),'[]')
        from students s join enrollments e on e.student_id=s.id and e.subject_id=sid
        left join mark_values v on v.student_id=s.id and v.sheet_id=sh.id
        where r='admin' or s.id=k.user_id) end); end $$;

-- admin: save the columns (create / rename / delete / formulas)
create or replace function marks_cols_save(t text, sid uuid, kd text, cols jsonb) returns void language plpgsql security definer set search_path=public as $$
declare sh uuid; keep text[]; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  if jsonb_typeof(cols)<>'array' or jsonb_array_length(cols)>60 then raise exception 'Too many columns (maximum 60)'; end if;
  insert into mark_sheets(subject_id,kind,cols) values(sid,kd,cols)
    on conflict (subject_id,kind) do update set cols=excluded.cols, updated_at=now() returning id into sh;
  select array_agg(c->>'id') into keep from jsonb_array_elements(cols) c;       -- marks of deleted columns are removed
  update mark_values set vals=(select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(mark_values.vals) where key=any(coalesce(keep,'{}'))) where sheet_id=sh; end $$;

-- admin: save marks.  rw = [{student_id, vals:{colId:number}}]   (only students of this subject)
create or replace function marks_save(t text, sid uuid, kd text, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare sh uuid; x jsonb; n int:=0; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  insert into mark_sheets(subject_id,kind) values(sid,kd) on conflict (subject_id,kind) do nothing;
  select id into sh from mark_sheets where subject_id=sid and kind=kd;
  for x in select * from jsonb_array_elements(rw) loop
    if jsonb_typeof(x->'vals')<>'object' or length((x->'vals')::text)>6000 then raise exception 'Wrong marks data'; end if;
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

grant execute on function marks_get(text,uuid,text), marks_cols_save(text,uuid,text,jsonb), marks_save(text,uuid,text,jsonb),
  marks_row_clear(text,uuid,text,uuid), marks_sheet_del(text,uuid,text) to anon, authenticated;
notify pgrst, 'reload schema';

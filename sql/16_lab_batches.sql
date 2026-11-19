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

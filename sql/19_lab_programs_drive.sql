-- =====================================================================================
-- 19_lab_programs_drive.sql   (v40)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- Run it AFTER the files up to 18.   Old SQL files are NOT changed.
--
-- LAB PROGRAMS  =  Title + Drive link + Purpose, shared with EVERY student of the subject (no batches any more)
--   1. lab_share      : NEW function.  Admin posts a lab program (title, Drive link, purpose) for a Theory + Lab subject.
--   2. subject_content: same as before, but every student sees every lab program of the subject (newest first).
--   Nothing is deleted: old lab programs stay, the old batch tables / functions stay unused in the database.
-- =====================================================================================

create or replace function lab_share(t text, sid uuid, ti text, lk text, pu text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; n text; begin perform _admin(t);
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab programs are only for Theory + Lab subjects'; end if;
  n:=nullif(trim(coalesce(ti,'')),'');
  if n is null then raise exception 'Enter the title'; end if;
  if length(n)>120 then raise exception 'The title is too long'; end if;
  if coalesce(trim(lk),'')='' or trim(lk) !~* '^https?://[^[:space:]]+$' then raise exception 'Paste the Drive link (it must start with https://)'; end if;
  if length(coalesce(pu,''))>5000 then raise exception 'The purpose is too long (5000 letters at most)'; end if;
  insert into labs(subject_id,title,task,link) values(sid,n,nullif(trim(pu),''),trim(lk));
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Lab program posted in '||cd);
  insert into notifications(role,user_id,subject_id,kind,title,body,link)           -- bell: every student of the subject + the CRs
    select 'student', e.student_id, sid, 'lab', cd||' · '||n, nullif(trim(pu),''), 'subject/'||cd||'/labs' from enrollments e where e.subject_id=sid
    union all select 'cr', c.cr_id, sid, 'lab', cd||' · '||n, nullif(trim(pu),''), 'subject/'||cd||'/labs' from cr_subjects c where c.subject_id=sid; end $$;

-- subject_content: same as v30; only 'labs' changed (every student sees every lab program)
create or replace function subject_content(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; begin r:=_access(t,sid); k:=_s(t);
  return json_build_object('role',r,
    'subject',(select json_build_object('id',id,'code',code,'name',name,'year',year,'full_name',full_name,'kind',kind) from subjects where id=sid),
    'materials',(select coalesce(json_agg(json_build_object('id',m.id,'category',m.category,'title',m.title,'link',m.link,'created_at',m.created_at)
        order by array_position(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks'],m.category), m.created_at),'[]') from materials m where m.subject_id=sid),
    'videos',(select coalesce(json_agg(v order by v.created_at desc),'[]') from videos v where v.subject_id=sid),
    'notices',(select coalesce(json_agg(n order by n.created_at desc),'[]') from notices n where n.subject_id=sid),
    'labs',(select coalesce(json_agg(l order by l.created_at desc),'[]') from labs l
        where l.subject_id=sid),
    'admin',(select json_build_object('name',coalesce(nullif(name,''),'Admin'),'photo',photo) from admins order by username limit 1),
    'crs',(select coalesce(json_agg(json_build_object('name',coalesce(nullif(c.name,''),c.username),'photo',c.photo) order by c.username),'[]') from crs c join cr_subjects x on x.cr_id=c.id where x.subject_id=sid)); end $$;

grant execute on function lab_share(text,uuid,text,text,text), subject_content(text,uuid) to anon, authenticated;
notify pgrst, 'reload schema';

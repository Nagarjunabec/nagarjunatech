-- =====================================================================================
-- 07_add_semester_mobile_photos.sql   (v24)   FOR AN EXISTING DATABASE - keeps ALL data. Safe to run again.
--   1. students get 3 new columns:  semester (1 to 8), mobile, parent_mobile
--   2. students_add / student_edit / students_all / subject_students now handle them
--      (new students need semester 1-8, mobile and parent mobile; OLD students stay as they are
--       and the admin fills the new fields later with Edit)
--   3. profile photos: admin sees student + CR photos, the CR sees student photos, and
--      students + CRs see the admin's and the CR's photo (subject_content)
-- Run this ONE file in Supabase > SQL Editor > New query > Run.  New install? Not needed (00 / 01 / 02 already have it).
-- =====================================================================================
alter table students add column if not exists semester smallint;
alter table students add column if not exists mobile text;
alter table students add column if not exists parent_mobile text;
alter table students drop constraint if exists students_semester_check;
alter table students add constraint students_semester_check check (semester is null or semester between 1 and 8);

create or replace function _mobile(m text, lbl text) returns text language plpgsql immutable as $$
declare d text; begin d:=regexp_replace(coalesce(m,''),'[^0-9]','','g');
  if length(d)=12 and left(d,2)='91' then d:=substr(d,3); elsif length(d)=11 and left(d,1)='0' then d:=substr(d,2); end if;
  if d !~ '^[6-9][0-9]{9}$' then raise exception '% must be a 10-digit mobile number', lbl; end if;
  return d; end $$;

create or replace function subject_students(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; begin r:=_access(t,sid); if r='student' then raise exception 'Not allowed'; end if;
  return (select coalesce(json_agg(json_build_object('id',s.id,'regno',s.regno,'name',s.name,'email',s.email,'year',s.year,'semester',s.semester,'mobile',s.mobile,'parent_mobile',s.parent_mobile,
      'pw',case when r='admin' then s.pw end,'photo',s.photo) order by s.regno),'[]')
    from students s join enrollments e on e.student_id=s.id where e.subject_id=sid); end $$;

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

create or replace function students_all(t text) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(json_build_object('id',s.id,'regno',s.regno,'name',s.name,'email',s.email,'year',s.year,'semester',s.semester,'mobile',s.mobile,'parent_mobile',s.parent_mobile,'pw',s.pw,'photo',s.photo,
      'created_by',s.created_by,'created_at',s.created_at,
      'subjects',(select coalesce(json_agg(json_build_object('id',sb.id,'code',sb.code) order by sb.code),'[]')
                  from enrollments e join subjects sb on sb.id=e.subject_id where e.student_id=s.id)) order by s.regno),'[]')
    from students s); end $$;

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

grant usage on schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
revoke all on function _s(text), _admin(text), _access(text,uuid), _mysubs(sessions), _taken(text), _cleanup(),
  _throttle_check(text), _throttle_fail(text), _throttle_ok(text), _notify_subject(uuid,text,text,text,text), _mobile(text,text) from public, anon, authenticated;
notify pgrst, 'reload schema';

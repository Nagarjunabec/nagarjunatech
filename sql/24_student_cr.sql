-- =====================================================================================
-- 24_student_cr.sql   (v49)   Run ONCE in Supabase > SQL Editor > Run.  Keeps ALL data.  Safe to run again.
-- Run it AFTER file 23.  Old SQL files are NOT changed.  Nothing is deleted.
--
-- CR = a NORMAL STUDENT appointed by the admin (no separate CR accounts any more).
--   * The admin appoints / removes a CR inside the subject's Students tab ("Make CR" / "Remove CR").
--   * The CR logs in like every other student (Reg No + password) and sees only his / her own marks, like everybody.
--   * The ONE extra feature of a CR: Add students (to the subjects he / she is appointed CR of). Nothing else:
--     no student list, no passwords, no marks of others, no editing, no deleting.
--   * The old CR accounts (table crs) are left untouched in the database but are no longer used by the website.
-- =====================================================================================

alter table enrollments add column if not exists is_cr boolean not null default false;     -- true = this student is the CR of this subject

-- private helper: is this student the CR of this subject?
create or replace function _is_cr(uid uuid, sid uuid) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from enrollments where student_id=uid and subject_id=sid and is_cr) $$;

-- admin: appoint (v=true) or remove (v=false) the CR of a subject
create or replace function cr_set(t text, sid uuid, stu uuid, v boolean) returns void language plpgsql security definer set search_path=public as $$
declare nm text; cd text; begin perform _admin(t);
  update enrollments set is_cr=coalesce(v,false) where subject_id=sid and student_id=stu;
  if not found then raise exception 'This student is not in this subject'; end if;
  select name into nm from students where id=stu; select code into cd from subjects where id=sid;
  insert into activity(msg) values(nm||case when coalesce(v,false) then ' appointed as CR of ' else ' removed as CR of ' end||cd); end $$;

-- admin: the students who are CR of a subject (ids)
create or replace function cr_students(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  return (select coalesce(json_agg(student_id),'[]') from enrollments where subject_id=sid and is_cr); end $$;

-- a logged-in student: the subjects he / she is CR of (ids). Admin: empty list.
create or replace function my_cr_subjects(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  if k.role<>'student' then return '[]'::json; end if;
  return (select coalesce(json_agg(subject_id),'[]') from enrollments where student_id=k.user_id and is_cr); end $$;

-- add students: the admin, or a student who is CR of THIS subject (same function as file 23, only the permission line changed)
create or replace function students_add(t text, sid uuid, rw jsonb) returns json language plpgsql security definer set search_path=public,extensions as $$
declare r text; k sessions; sc text; x jsonb; rg text; nm text; em text; pwd text; ex students; nid uuid; sm int; mb text; pm text;
        added jsonb:='[]'; had jsonb:='[]'; bad jsonb:='[]';
begin r:=_access(t,sid); k:=_s(t);
  if r='student' and not _is_cr(k.user_id,sid) then raise exception 'Not allowed'; end if;     -- a normal student cannot; a student appointed CR of this subject can
  for x in select * from jsonb_array_elements(rw) loop
    rg:=upper(trim(coalesce(x->>'regno','')));
    sc:=upper(nullif(trim(coalesce(x->>'section','')),''));
    begin
      if rg !~ '^[A-Z0-9]{5,15}$' then raise exception 'Reg No must be 5-15 letters/digits'; end if;
      if sc is not null and coalesce((select section_list from subjects where id=sid),'')='' then sc:=null; end if;                       -- a subject without sections ignores the Section column
      if sc is not null and (sc !~ '^[A-J]$' or position(sc in coalesce((select section_list from subjects where id=sid),''))=0) then raise exception 'Section must be one of the sections of this subject'; end if;
      select * into ex from students where regno=rg;
      if ex.id is not null then            -- already has an account: only add to this subject
        insert into enrollments(subject_id,student_id,section) values(sid,ex.id,sc) on conflict (subject_id,student_id) do update set section=coalesce(excluded.section,enrollments.section);
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
        insert into enrollments(subject_id,student_id,section) values(sid,nid,sc);
        added:=added||jsonb_build_array(jsonb_build_object('regno',rg,'name',nm,'email',em));
      end if;
    exception when others then bad:=bad||jsonb_build_array(jsonb_build_object('regno',rg,'why',sqlerrm)); end;
  end loop;
  if jsonb_array_length(added)>0 then insert into activity(msg) values(jsonb_array_length(added)||' student(s) added to '||(select code from subjects where id=sid)||' by '||case when r='admin' then 'admin' else 'CR' end); end if;
  return json_build_object('added',added,'existing',had,'skipped',bad); end $$;

grant execute on function cr_set(text,uuid,uuid,boolean), cr_students(text,uuid), my_cr_subjects(text) to anon, authenticated;
revoke all on function _is_cr(uuid,uuid) from public, anon, authenticated;
notify pgrst, 'reload schema';

-- =====================================================================================
-- 23_section_checkboxes.sql   (v46)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- Run it AFTER file 20.  Old SQL files are NOT changed.
--
-- SECTIONS BY CHECKBOX: when a subject is created or edited, the admin ticks exactly the sections it has (any of A to J),
--   for example A, C and F  or  A, G and H.   Fewer than 2 ticks = no sections (the subject works as before).
--   Subjects made with file 20 (a number of sections) are converted: 3 sections -> A, B, C.
-- =====================================================================================

alter table subjects add column if not exists section_list text;                       -- the ticked letters, for example 'A,C,F'
update subjects set section_list=substr('ABCDEFGHIJ',1,sections) where sections>1 and section_list is null;
alter table subjects    drop constraint if exists subjects_sections_ok;
alter table subjects    add  constraint subjects_sections_ok check (sections between 1 and 10);
alter table enrollments drop constraint if exists enrollments_section_ok;
alter table enrollments add  constraint enrollments_section_ok check (section is null or section ~ '^[A-J]$');
alter table mark_sheets drop constraint if exists mark_sheets_kind_ok;
alter table mark_sheets add  constraint mark_sheets_kind_ok check (kind ~ '^(theory|lab)(-[A-J])?$');

drop function if exists subject_add(text,text,int,text,text,int);
drop function if exists subject_edit(text,uuid,text,int,text,text,int);

create or replace function marks_get(t text, sid uuid, kd text) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; sh mark_sheets; show boolean; begin r:=_access(t,sid); k:=_s(t);
  if kd !~ '^(theory|lab)(-[A-J])?$' then raise exception 'Wrong sheet'; end if;
  if _kbase(kd)='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  if r='student' and _ksec(kd) is not null and coalesce((select section from enrollments where subject_id=sid and student_id=k.user_id),'')<>_ksec(kd) then raise exception 'This is not your section'; end if;
  select * into sh from mark_sheets where subject_id=sid and mark_sheets.kind=kd;
  show := (r='admin') or coalesce(sh.published,false);                            -- students and CR: only after Publish
  return json_build_object('published',coalesce(sh.published,false),
    'cols',case when show then coalesce(sh.cols,'[]'::jsonb) else '[]'::jsonb end,'row_colors',case when show then sh.row_colors else null end,
    'rows',case when not show then '[]'::json else (select coalesce(json_agg(json_build_object('student_id',s.id,'regno',s.regno,'name',s.name,'vals',coalesce(v.vals,'{}'::jsonb)) order by s.regno),'[]')
        from students s join enrollments e on e.student_id=s.id and e.subject_id=sid and (_ksec(kd) is null or e.section=_ksec(kd))
        left join mark_values v on v.student_id=s.id and v.sheet_id=sh.id
        where r in ('admin','cr') or s.id=k.user_id) end); end $$;

create or replace function marks_cols_save(t text, sid uuid, kd text, cols jsonb) returns void language plpgsql security definer set search_path=public as $$
declare sh uuid; keep text[]; c jsonb; ids text[]:='{}'; nm text; has_aat boolean:=false; begin perform _admin(t);
  if kd !~ '^(theory|lab)(-[A-J])?$' then raise exception 'Wrong sheet'; end if;
  if _ksec(kd) is not null and position(_ksec(kd) in coalesce((select section_list from subjects where id=sid),''))=0 then raise exception 'This subject has no such section'; end if;
  if _kbase(kd)='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
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
      if _kbase(kd)='theory' and lower(nm)='aat 1' then has_aat:=true; end if;
    end if;
  end loop;
  if _kbase(kd)='theory' and not has_aat then raise exception 'The column "AAT 1" is mandatory in Theory Marks'; end if;
  insert into mark_sheets(subject_id,kind,cols) values(sid,kd,cols)
    on conflict (subject_id,kind) do update set cols=excluded.cols, updated_at=now() returning id into sh;
  select array_agg(x->>'id') into keep from jsonb_array_elements(cols) x;       -- marks of deleted columns are removed
  update mark_values set vals=(select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(mark_values.vals) where key=any(coalesce(keep,'{}'))) where sheet_id=sh; end $$;

create or replace function marks_save(t text, sid uuid, kd text, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare sh uuid; x jsonb; n int:=0; cl jsonb; e record; begin perform _admin(t);
  if kd !~ '^(theory|lab)(-[A-J])?$' then raise exception 'Wrong sheet'; end if;
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
    if exists(select 1 from enrollments where subject_id=sid and student_id=(x->>'student_id')::uuid and (_ksec(kd) is null or section=_ksec(kd))) then
      insert into mark_values(sheet_id,student_id,vals) values(sh,(x->>'student_id')::uuid,x->'vals')
        on conflict (sheet_id,student_id) do update set vals=excluded.vals, updated_at=now(); n:=n+1; end if;
  end loop; return n; end $$;

create or replace function marks_publish(t text, sid uuid, kd text, pub boolean) returns void language plpgsql security definer set search_path=public as $$
declare was boolean; cd text; begin perform _admin(t);
  if kd !~ '^(theory|lab)(-[A-J])?$' then raise exception 'Wrong sheet'; end if;
  if _kbase(kd)='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  insert into mark_sheets(subject_id,kind) values(sid,kd) on conflict (subject_id,kind) do nothing;
  select published into was from mark_sheets where subject_id=sid and kind=kd;
  update mark_sheets set published=coalesce(pub,false), updated_at=now() where subject_id=sid and kind=kd;
  if coalesce(pub,false) and not was then
    select code into cd from subjects where id=sid;
    if _ksec(kd) is null then
      perform _notify_subject(sid,'marks',cd||' · '||case when _kbase(kd)='lab' then 'Lab Marks' else 'Theory Marks' end||' published','Your marks are now available.',
        'subject/'||cd||'/'||case when _kbase(kd)='lab' then 'labsheet' else 'marks' end);
    else                                                                          -- a section: only the students of that section
      insert into notifications(role,user_id,subject_id,kind,title,body,link)
        select 'student', e.student_id, sid, 'marks', cd||' · '||case when _kbase(kd)='lab' then 'Lab Marks' else 'Theory Marks' end||' (Section '||_ksec(kd)||') published', 'Your marks are now available.',
          'subject/'||cd||'/'||case when _kbase(kd)='lab' then 'labsheet' else 'marks' end from enrollments e where e.subject_id=sid and e.section=_ksec(kd);
    end if;
  end if; end $$;

create or replace function marks_sections(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; begin r:=_access(t,sid); k:=_s(t);
  return json_build_object('count',(select sections from subjects where id=sid),'letters',(select section_list from subjects where id=sid),
    'mine',(select section from enrollments where subject_id=sid and student_id=k.user_id),
    'theory',(select coalesce(json_agg(_ksec(kind) order by kind),'[]') from mark_sheets where subject_id=sid and kind like 'theory-%'),
    'lab',(select coalesce(json_agg(_ksec(kind) order by kind),'[]') from mark_sheets where subject_id=sid and kind like 'lab-%'),
    'nosec',case when r='student' then null else (select count(*) from enrollments where subject_id=sid and section is null) end); end $$;

create or replace function student_section(t text, sid uuid, ids uuid[], sec text) returns void language plpgsql security definer set search_path=public as $$
declare r text; s text; begin r:=_access(t,sid); if r='student' then raise exception 'Not allowed'; end if;
  s:=upper(nullif(trim(coalesce(sec,'')),''));
  if s is not null and (s !~ '^[A-J]$' or position(s in coalesce((select section_list from subjects where id=sid),''))=0) then raise exception 'Section must be one of the sections of this subject'; end if;
  update enrollments set section=s where subject_id=sid and student_id=any(ids); end $$;

create or replace function students_add(t text, sid uuid, rw jsonb) returns json language plpgsql security definer set search_path=public,extensions as $$
declare r text; sc text; x jsonb; rg text; nm text; em text; pwd text; ex students; nid uuid; sm int; mb text; pm text;
        added jsonb:='[]'; had jsonb:='[]'; bad jsonb:='[]';
begin r:=_access(t,sid); if r='student' then raise exception 'Not allowed'; end if;
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
  if jsonb_array_length(added)>0 then insert into activity(msg) values(jsonb_array_length(added)||' student(s) added to '||(select code from subjects where id=sid)||' by '||r); end if;
  return json_build_object('added',added,'existing',had,'skipped',bad); end $$;

create or replace function subject_add(t text, n text, y int, f text, k text, sc int default 1, sl text default null) returns void language plpgsql security definer set search_path=public as $$
declare ls text; cnt int;
begin perform _admin(t); n:=upper(trim(coalesce(n,'')));
  if n !~ '^[A-Z0-9]{1,12}$' then raise exception 'Subject name: 1-12 letters/digits, no spaces (example: DS)'; end if;
  if coalesce(y,0) not between 2000 and 2100 then raise exception 'Enter a valid year (example: 2026)'; end if;
  if coalesce(k,'') not in ('theory','lab') then raise exception 'Choose: Theory only, or Theory + Lab'; end if;
  if sl is not null then
    select string_agg(x,',' order by x), count(*) into ls, cnt from (select distinct upper(trim(v)) x from unnest(string_to_array(sl,',')) v) q where x ~ '^[A-J]$';
    if coalesce(cnt,0)<2 then ls:=null; cnt:=1; end if;                                 -- fewer than 2 letters = no sections
  elsif coalesce(sc,1) between 2 and 10 then ls:=substr('ABCDEFGHIJ',1,sc); cnt:=sc;   -- old style: a number of sections
  else ls:=null; cnt:=1; end if;
  insert into subjects(code,name,year,full_name,kind,sections,section_list) values(n||'-'||y||'-'||(y+1), n, y, nullif(trim(f),''), k, cnt, ls);
  insert into activity(msg) values('Subject '||n||'-'||y||'-'||(y+1)||' created ('||case k when 'lab' then 'theory + lab' else 'theory only' end||')');
exception when unique_violation then raise exception 'This subject and year already exist'; end $$;

create or replace function subject_edit(t text, sid uuid, n text, y int, f text, k text, sc int default 1, sl text default null) returns void language plpgsql security definer set search_path=public as $$
declare ls text; cnt int;
begin perform _admin(t); n:=upper(trim(coalesce(n,'')));
  if n !~ '^[A-Z0-9]{1,12}$' then raise exception 'Subject name: 1-12 letters/digits, no spaces (example: DS)'; end if;
  if coalesce(y,0) not between 2000 and 2100 then raise exception 'Enter a valid year (example: 2026)'; end if;
  if coalesce(k,'') not in ('theory','lab') then raise exception 'Choose: Theory only, or Theory + Lab'; end if;
  if sl is not null then
    select string_agg(x,',' order by x), count(*) into ls, cnt from (select distinct upper(trim(v)) x from unnest(string_to_array(sl,',')) v) q where x ~ '^[A-J]$';
    if coalesce(cnt,0)<2 then ls:=null; cnt:=1; end if;                                 -- fewer than 2 letters = no sections
  elsif coalesce(sc,1) between 2 and 10 then ls:=substr('ABCDEFGHIJ',1,sc); cnt:=sc;   -- old style: a number of sections
  else ls:=null; cnt:=1; end if;
  update subjects set name=n, year=y, code=n||'-'||y||'-'||(y+1), full_name=nullif(trim(coalesce(f,'')),''), kind=k, sections=cnt, section_list=ls where id=sid;
  if not found then raise exception 'Subject not found'; end if;
  insert into activity(msg) values('Subject '||n||'-'||y||'-'||(y+1)||' edited');
exception when unique_violation then raise exception 'This subject and year already exist'; end $$;

create or replace function subjects_list(t text) returns json language plpgsql security definer set search_path=public as $$
declare k sessions; begin k:=_s(t);
  return (select coalesce(json_agg(x order by x.year desc, x.code),'[]') from (
    select s.id, s.code, s.name, s.year, s.full_name, s.kind, s.sections, s.section_list,
      (select count(*) from enrollments e where e.subject_id=s.id) as students,
      (select count(*) from materials m where m.subject_id=s.id and m.category not in ('Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan')) as materials,
      (select count(*) from notices n where n.subject_id=s.id) as notices,
      (select count(*) from labs l where l.subject_id=s.id) as labs,
      (select count(*) from videos v where v.subject_id=s.id) as videos
    from subjects s where s.id in (select * from _mysubs(k))) x); end $$;

create or replace function subject_content(t text, sid uuid) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; begin r:=_access(t,sid); k:=_s(t);
  return json_build_object('role',r,
    'subject',(select json_build_object('id',id,'code',code,'name',name,'year',year,'full_name',full_name,'kind',kind,'sections',sections,'section_list',section_list) from subjects where id=sid),
    'materials',(select coalesce(json_agg(json_build_object('id',m.id,'category',m.category,'title',m.title,'link',m.link,'created_at',m.created_at)
        order by array_position(array['Theory Syllabus','Lab Syllabus','Theory Lesson Plan','Lab Lesson Plan','Unit 1','Unit 2','Unit 3','Unit 4','Unit 5','Unit 6','AAT1','AAT2','Mid 1','Mid 2','Lab Marks'],m.category), m.created_at),'[]') from materials m where m.subject_id=sid),
    'videos',(select coalesce(json_agg(v order by v.created_at desc),'[]') from videos v where v.subject_id=sid),
    'notices',(select coalesce(json_agg(n order by n.created_at desc),'[]') from notices n where n.subject_id=sid),
    'labs',(select coalesce(json_agg(l order by l.created_at desc),'[]') from labs l
        where l.subject_id=sid),
    'admin',(select json_build_object('name',coalesce(nullif(name,''),'Admin'),'photo',photo) from admins order by username limit 1),
    'crs',(select coalesce(json_agg(json_build_object('name',coalesce(nullif(c.name,''),c.username),'photo',c.photo) order by c.username),'[]') from crs c join cr_subjects x on x.cr_id=c.id where x.subject_id=sid)); end $$;

grant execute on function subject_add(text,text,int,text,text,int,text), subject_edit(text,uuid,text,int,text,text,int,text), subjects_list(text), subject_content(text,uuid),
  marks_get(text,uuid,text), marks_cols_save(text,uuid,text,jsonb), marks_save(text,uuid,text,jsonb), marks_publish(text,uuid,text,boolean),
  marks_sections(text,uuid), student_section(text,uuid,uuid[],text), students_add(text,uuid,jsonb) to anon, authenticated;
notify pgrst, 'reload schema';

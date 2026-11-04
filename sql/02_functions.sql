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

create or replace function notice_del(t text, i uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t); delete from notices where id=i; end $$;

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

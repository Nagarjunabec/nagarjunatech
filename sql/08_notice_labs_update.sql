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

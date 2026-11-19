-- =====================================================================================
-- 21_lab_program_rule.sql   (v44)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- Lab Programs: the Title is required, the Drive link is optional, the Purpose is optional, but AT LEAST ONE of Drive link / Purpose must be given.
-- (File 20 already contains this rule: if you have not run file 20 yet, run 19 and 20 only. If you already ran 20, run this one.)
-- =====================================================================================

create or replace function lab_share(t text, sid uuid, ti text, lk text, pu text) returns void language plpgsql security definer set search_path=public as $$
declare cd text; n text; begin perform _admin(t);
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab programs are only for Theory + Lab subjects'; end if;
  n:=nullif(trim(coalesce(ti,'')),'');
  if n is null then raise exception 'Enter the title'; end if;
  if length(n)>120 then raise exception 'The title is too long'; end if;
  if coalesce(trim(lk),'')<>'' and trim(lk) !~* '^https?://[^[:space:]]+$' then raise exception 'The Drive link must start with https://'; end if;
  if length(coalesce(pu,''))>30000 then raise exception 'The purpose is too long'; end if;
  if coalesce(trim(lk),'')='' and trim(regexp_replace(coalesce(pu,''),'<[^>]*>|&nbsp;',' ','g'))='' then raise exception 'Give a Drive link or a purpose (at least one of them)'; end if;
  insert into labs(subject_id,title,task,link) values(sid,n,nullif(trim(coalesce(pu,'')),''),nullif(trim(coalesce(lk,'')),''));
  select code into cd from subjects where id=sid;
  insert into activity(msg) values('Lab program posted in '||cd);
  perform _notify_subject(sid,'lab',cd||' · '||n,null,'subject/'||cd||'/labs'); end $$;

grant execute on function lab_share(text,uuid,text,text,text) to anon, authenticated;
notify pgrst, 'reload schema';

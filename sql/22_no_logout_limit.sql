-- =====================================================================================
-- 22_no_logout_limit.sql   (v45)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- NO AUTOMATIC LOG-OUT for anybody (admin, CR, students): a login now lasts until the person presses "Log out".
--   (before: admin 8 hours, CR 2 days, student 3 days)
--   1. everybody who is logged in right now is extended too
--   2. unified_login: the same function as before, only the session length is changed
-- =====================================================================================

alter table sessions alter column expires_at set default now() + interval '100 years';
update sessions set expires_at = now() + interval '100 years' where expires_at < now() + interval '100 years';

create or replace function unified_login(u text, p text) returns json language plpgsql security definer set search_path=public,extensions as $$
declare a admins; c crs; s students; k text; kk text;
begin
  kk:='login:'||lower(trim(coalesce(u,''))); perform _throttle_check(kk); perform _cleanup();
  k:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');

  select * into a from admins where username=lower(trim(u));
  if a.id is not null and a.password_hash=crypt(p,a.password_hash) then
    perform _throttle_ok(kk); insert into sessions(token,role,user_id,expires_at) values(k,'admin',a.id,now()+interval '100 years');
    return json_build_object('role','admin','token',k,'name',coalesce(a.name,'Admin'),'sub','Admin','photo',a.photo); end if;

  select * into c from crs where username=upper(trim(u));
  if c.id is not null and (c.password_hash=crypt(p,c.password_hash) or c.password_hash=crypt(upper(btrim(p)),c.password_hash)) then
    perform _throttle_ok(kk); insert into sessions(token,role,user_id,expires_at) values(k,'cr',c.id,now()+interval '100 years');
    return json_build_object('role','cr','token',k,'name',coalesce(nullif(c.name,''),c.username),'sub','CR · '||c.username,'photo',c.photo); end if;

  select * into s from students where regno=upper(trim(u));
  if s.id is not null and (s.password_hash=crypt(p,s.password_hash) or s.password_hash=crypt(upper(btrim(p)),s.password_hash)) then
    perform _throttle_ok(kk); insert into sessions(token,role,user_id,expires_at) values(k,'student',s.id,now()+interval '100 years');
    return json_build_object('role','student','token',k,'name',s.name,'sub',s.regno||' · Year '||s.year,'photo',s.photo); end if;

  perform _throttle_fail(kk); return json_build_object('error','Invalid ID or password'); end $$;

grant execute on function unified_login(text,text) to anon, authenticated;
notify pgrst, 'reload schema';

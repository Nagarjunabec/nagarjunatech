-- 99_refresh_api_cache.sql  - run it when the website says
--   "Could not find the function public.unified_login ... in the schema cache"
-- (02_functions.sql and 03_admin_seed.sql already do this at their end; this file is only the extra one-liner)
grant usage on schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
notify pgrst, 'reload schema';
-- check: this must list the 4 names
select proname from pg_proc where proname in ('unified_login','forgot_password','password_change','profile_photo_set') order by 1;

-- =====================================================================================
-- 03_admin_seed.sql  (run LAST, after 01 and 02).  Safe to run again at any time.
--   Admin login   : nagarjunabec2009@gmail.com
--   Admin password: nagarjuna@2009
--   Admin name    : T Nagarjuna
-- The old admin (nextgencoders2024@gmail.com) is removed. Running this file again resets the
-- admin password to the value below. To change the login or password, edit the two values
-- here and run this file again. The password is stored only as a bcrypt hash.
-- =====================================================================================
delete from admins where username <> 'nagarjunabec2009@gmail.com';

insert into admins(username, name, password_hash)
values ('nagarjunabec2009@gmail.com', 'T Nagarjuna', extensions.crypt('nagarjuna@2009', extensions.gen_salt('bf', 8)))
on conflict (username) do update set password_hash = excluded.password_hash, name = excluded.name;

delete from sessions where role = 'admin';      -- everybody has to log in again

notify pgrst, 'reload schema';

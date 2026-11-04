-- =====================================================================================
-- 05_optional_passwords_to_regno.sql   (v14)  OPTIONAL - only for an existing database.
-- Sets the password of EVERY student back to his / her Reg No (also the ones students chose themselves) (capital letters; typing it in
-- small or mixed letters also works at login). Students added after v14 get this automatically.
-- Run it only if you want all old students (who have nexg@123-style passwords) on the new rule.
-- It does not touch the admin or the CR logins.
-- =====================================================================================
update students set pw = regno, password_hash = extensions.crypt(regno, extensions.gen_salt('bf', 8));
delete from sessions where role = 'student';

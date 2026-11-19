-- =====================================================================================
-- 04_update_existing_database.sql   (v14)   FOR AN EXISTING v12 DATABASE ONLY - run it FIRST.
-- Safe to run again. Keeps all your data. On a new install you do NOT need it (01 already has this).
--   1. adds the profile photo columns
--   2. adds the subject type (theory / theory + lab). Subjects that already have lab programs or a
--      "Lab Marks" link become "theory + lab", all others "theory" (the admin can change it in Edit)
--   3. subject codes become  DS-2026-2027  (name + start year + next year)
--   4. removes the whole Leave feature (leave requests are deleted)
--   5. students: marks the passwords chosen by students themselves later; nothing to change now
-- Order for an existing database:   04  ->  02  ->  03   (05 is optional)
-- =====================================================================================
alter table admins   add column if not exists photo text;
alter table students add column if not exists photo text;
alter table crs      add column if not exists photo text;

alter table subjects add column if not exists kind text not null default 'theory';
alter table subjects drop constraint if exists subjects_kind_check;
alter table subjects add constraint subjects_kind_check check (kind in ('theory','lab'));
update subjects s set kind = 'lab'
 where exists (select 1 from labs l where l.subject_id = s.id)
    or exists (select 1 from materials m where m.subject_id = s.id and m.category = 'Lab Marks');

update subjects set code = name || '-' || year || '-' || (year + 1) where code <> name || '-' || year || '-' || (year + 1);

drop function if exists subject_add(text, text, int, text);
drop function if exists subject_edit(text, uuid, text, int, text);
drop function if exists leave_apply(text, uuid, text, text, text);
drop function if exists leave_list(text, uuid);
drop function if exists leave_decide(text, uuid, text, text);
drop function if exists leave_cancel(text, uuid);
drop function if exists leave_edit(text, uuid, text, text, text, text, text);
drop function if exists leave_delete(text, uuid);
drop function if exists _notify_admins(uuid, text, text, text, text);
delete from notifications where kind = 'leave';
drop table if exists leaves cascade;

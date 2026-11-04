-- =====================================================================================
-- 13_marks_cr_view.sql   (v27)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- Run it AFTER 09 to 12.   Old SQL files are NOT changed.
--
-- A CR login can now VIEW the marks of ALL students (Theory Marks and Lab Marks) of the subjects assigned to that CR.
-- View only: marks_save, marks_cols_save, marks_row_clear and marks_sheet_del stay admin-only.
-- A student still sees only his / her own row.  Only marks_get changes.
-- =====================================================================================

create or replace function marks_get(t text, sid uuid, kd text) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; sh mark_sheets; begin r:=_access(t,sid); k:=_s(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  select * into sh from mark_sheets where subject_id=sid and mark_sheets.kind=kd;
  return json_build_object('cols',coalesce(sh.cols,'[]'::jsonb),
    'rows',(select coalesce(json_agg(json_build_object('student_id',s.id,'regno',s.regno,'name',s.name,'vals',coalesce(v.vals,'{}'::jsonb)) order by s.regno),'[]')
        from students s join enrollments e on e.student_id=s.id and e.subject_id=sid
        left join mark_values v on v.student_id=s.id and v.sheet_id=sh.id
        where r in ('admin','cr') or s.id=k.user_id)); end $$;

grant execute on function marks_get(text,uuid,text) to anon, authenticated;
notify pgrst, 'reload schema';

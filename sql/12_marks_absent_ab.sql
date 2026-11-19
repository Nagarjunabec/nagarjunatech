-- =====================================================================================
-- 12_marks_absent_ab.sql   (v27)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- Run it AFTER 09, 10 and 11.   Old SQL files are NOT changed.
--
-- Lets a mark be "AB" (absent) as well as a number.  Formulas ignore an AB cell (the website does this).
-- marks_save: a mark must be a number (not negative, not above the column maximum) OR the text "AB".
-- Without this file the database refuses AB (the check in 11 only accepts numbers).
-- =====================================================================================

create or replace function marks_save(t text, sid uuid, kd text, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare sh uuid; x jsonb; n int:=0; cl jsonb; e record; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
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
    if exists(select 1 from enrollments where subject_id=sid and student_id=(x->>'student_id')::uuid) then
      insert into mark_values(sheet_id,student_id,vals) values(sh,(x->>'student_id')::uuid,x->'vals')
        on conflict (sheet_id,student_id) do update set vals=excluded.vals, updated_at=now(); n:=n+1; end if;
  end loop; return n; end $$;

grant execute on function marks_save(text,uuid,text,jsonb) to anon, authenticated;
notify pgrst, 'reload schema';

-- =====================================================================================
-- 14_marks_row_colors.sql   (v28)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- Run it AFTER 09 to 13.   Old SQL files are NOT changed.
--
-- ROW COLOURS for Lab Marks.  The admin chooses (button "Row colors" on the Lab Marks page):
--   * ON / OFF
--   * which column decides the color (normally the Total column)
--   * the color ranges, for example   0 = red,  11 = blue,  16 = green
--       (a row gets the color of the highest "from" its mark has reached:
--        below 11 red, 11 to 15 blue, 16 and above green)
-- The colors are NOT fixed in the website: they are stored here, per Lab Marks sheet, and the admin can change them any time.
-- Until the admin saves something the website uses the defaults above (red / blue / green).
--
-- What this file does
--   1. mark_sheets gets one new column  row_colors  (jsonb, empty = defaults)
--   2. marks_get      : same as in 13 (admin / CR see every student, a student only his / her row) + returns row_colors
--   3. marks_rules_save : NEW, admin only, checks and saves the color rules (Lab Marks only)
-- =====================================================================================

alter table public.mark_sheets add column if not exists row_colors jsonb;      -- {"on":true,"col":"<column id>","rows":[{"from":0,"color":"#dc2626"},...]}

create or replace function marks_get(t text, sid uuid, kd text) returns json language plpgsql security definer set search_path=public as $$
declare r text; k sessions; sh mark_sheets; begin r:=_access(t,sid); k:=_s(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  select * into sh from mark_sheets where subject_id=sid and mark_sheets.kind=kd;
  return json_build_object('cols',coalesce(sh.cols,'[]'::jsonb),'row_colors',sh.row_colors,
    'rows',(select coalesce(json_agg(json_build_object('student_id',s.id,'regno',s.regno,'name',s.name,'vals',coalesce(v.vals,'{}'::jsonb)) order by s.regno),'[]')
        from students s join enrollments e on e.student_id=s.id and e.subject_id=sid
        left join mark_values v on v.student_id=s.id and v.sheet_id=sh.id
        where r in ('admin','cr') or s.id=k.user_id)); end $$;

-- admin: save the row color rules of a Lab Marks sheet.  rc = null  -> back to the default colors
create or replace function marks_rules_save(t text, sid uuid, kd text, rc jsonb) returns void language plpgsql security definer set search_path=public as $$
declare x jsonb; froms numeric[]:='{}'; f numeric; begin perform _admin(t);
  if kd<>'lab' then raise exception 'Row colors are only for Lab Marks'; end if;
  if (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  if rc is not null and jsonb_typeof(rc)<>'null' then
    if jsonb_typeof(rc)<>'object' or coalesce(jsonb_typeof(rc->'on'),'')<>'boolean' then raise exception 'Wrong color data'; end if;
    if coalesce(rc->>'col','') !~ '^[A-Za-z0-9]{1,20}$' then raise exception 'Choose the column that decides the color'; end if;
    if coalesce(jsonb_typeof(rc->'rows'),'')<>'array' then raise exception 'Give 1 to 10 color ranges'; end if;
    if jsonb_array_length(rc->'rows') not between 1 and 10 then raise exception 'Give 1 to 10 color ranges'; end if;
    for x in select * from jsonb_array_elements(rc->'rows') loop
      if jsonb_typeof(x)<>'object' then raise exception 'Wrong color data'; end if;
      if coalesce(jsonb_typeof(x->'from'),'')<>'number' then raise exception 'Every color range needs a "from" number'; end if;
      f:=(x->>'from')::numeric;
      if f<0 or f>1000 then raise exception 'A "from" mark must be between 0 and 1000'; end if;
      if f=any(froms) then raise exception 'Two color ranges start at the same mark (%)', f; end if;
      froms:=froms||f;
      if coalesce(x->>'color','') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'A color must look like #16a34a'; end if;
    end loop;
  else rc:=null; end if;
  insert into mark_sheets(subject_id,kind,row_colors) values(sid,kd,rc)
    on conflict (subject_id,kind) do update set row_colors=excluded.row_colors, updated_at=now(); end $$;

grant execute on function marks_get(text,uuid,text), marks_rules_save(text,uuid,text,jsonb) to anon, authenticated;
notify pgrst, 'reload schema';

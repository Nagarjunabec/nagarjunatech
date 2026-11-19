-- =====================================================================================
-- 11_marks_column_max.sql   (v27)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- Run it AFTER 09_marks_tables.sql and 10_marks_formula_rules.sql.   Old SQL files are NOT changed.
--
-- Adds database checks for the v27 marks features:
--   * a marks column may carry "max" (maximum marks): a number from 1 to 1000
--   * Theory Marks must always contain the inbuilt marks column "AAT 1" (mandatory)
--   * marks_save refuses a mark that is negative or above the column's maximum
-- Nothing in the tables changes: the maximum is stored inside mark_sheets.cols like the formulas are.
-- =====================================================================================

create or replace function marks_cols_save(t text, sid uuid, kd text, cols jsonb) returns void language plpgsql security definer set search_path=public as $$
declare sh uuid; keep text[]; c jsonb; ids text[]:='{}'; nm text; has_aat boolean:=false; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  if kd='lab' and (select kind from subjects where id=sid)<>'lab' then raise exception 'Lab marks are only for Theory + Lab subjects'; end if;
  if jsonb_typeof(cols)<>'array' or jsonb_array_length(cols)>60 then raise exception 'Too many columns (maximum 60)'; end if;
  for c in select * from jsonb_array_elements(cols) loop
    if jsonb_typeof(c)<>'object' then raise exception 'Wrong column data'; end if;
    if coalesce(c->>'id','') !~ '^[A-Za-z0-9]{1,20}$' or (c->>'id')=any(ids) then raise exception 'Wrong column id'; end if;
    ids:=ids||(c->>'id');
    nm:=btrim(coalesce(c->>'name',''));
    if length(nm) not between 1 and 40 or nm ~ '[\[\]]' then raise exception 'Column name: 1-40 characters, without [ or ]'; end if;
    if coalesce(c->>'type','') not in ('marks','formula') then raise exception 'Column type must be marks or formula'; end if;
    if c->>'type'='formula' then
      if coalesce(c->>'f','') !~ '^\s*=' then raise exception 'Formula of column "%" must start with =', nm; end if;
      if length(c->>'f')>300 then raise exception 'Formula of column "%" is too long (maximum 300 characters)', nm; end if;
      if (c->>'f') !~ '^[A-Za-z0-9_ \[\]()+\-*/^%,:.$<>=\"&]*$' then raise exception 'Formula of column "%" has a character that is not allowed', nm; end if;
    else
      if c ? 'max' and (jsonb_typeof(c->'max')<>'number' or (c->>'max')::numeric <= 0 or (c->>'max')::numeric > 1000) then
        raise exception 'Maximum marks of column "%" must be a number from 1 to 1000', nm; end if;
      if kd='theory' and lower(nm)='aat 1' then has_aat:=true; end if;
    end if;
  end loop;
  if kd='theory' and not has_aat then raise exception 'The column "AAT 1" is mandatory in Theory Marks'; end if;
  insert into mark_sheets(subject_id,kind,cols) values(sid,kd,cols)
    on conflict (subject_id,kind) do update set cols=excluded.cols, updated_at=now() returning id into sh;
  select array_agg(x->>'id') into keep from jsonb_array_elements(cols) x;       -- marks of deleted columns are removed
  update mark_values set vals=(select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(mark_values.vals) where key=any(coalesce(keep,'{}'))) where sheet_id=sh; end $$;

create or replace function marks_save(t text, sid uuid, kd text, rw jsonb) returns int language plpgsql security definer set search_path=public as $$
declare sh uuid; x jsonb; n int:=0; cl jsonb; e record; begin perform _admin(t);
  if kd not in ('theory','lab') then raise exception 'Wrong sheet'; end if;
  insert into mark_sheets(subject_id,kind) values(sid,kd) on conflict (subject_id,kind) do nothing;
  select id, cols into sh, cl from mark_sheets where subject_id=sid and kind=kd;
  for x in select * from jsonb_array_elements(rw) loop
    if jsonb_typeof(x->'vals')<>'object' or length((x->'vals')::text)>6000 then raise exception 'Wrong marks data'; end if;
    for e in select key, value from jsonb_each(x->'vals') loop                  -- every mark: a number, not negative, not above the column maximum
      if jsonb_typeof(e.value)<>'number' or (e.value#>>'{}')::numeric < 0 then raise exception 'Marks must be numbers, not negative'; end if;
      if exists(select 1 from jsonb_array_elements(coalesce(cl,'[]'::jsonb)) k where k->>'id'=e.key and k ? 'max' and (k->>'max')::numeric < (e.value#>>'{}')::numeric) then
        raise exception 'A mark is above the maximum marks of its column'; end if;
    end loop;
    if exists(select 1 from enrollments where subject_id=sid and student_id=(x->>'student_id')::uuid) then
      insert into mark_values(sheet_id,student_id,vals) values(sh,(x->>'student_id')::uuid,x->'vals')
        on conflict (sheet_id,student_id) do update set vals=excluded.vals, updated_at=now(); n:=n+1; end if;
  end loop; return n; end $$;

grant execute on function marks_cols_save(text,uuid,text,jsonb), marks_save(text,uuid,text,jsonb) to anon, authenticated;
notify pgrst, 'reload schema';

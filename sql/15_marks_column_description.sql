-- =====================================================================================
-- 15_marks_column_description.sql   (v29)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- Run it AFTER 09 to 14.   Old SQL files are NOT changed.
--
-- DESCRIPTION of every column in Lab Marks: an optional short text (up to 200 characters) written by the admin in the
-- column settings (the gear icon).  It is shown under the column name in the table, to the admin, the CR and the student.
-- Nothing in the tables changes: the description is stored inside mark_sheets.cols like the formula and the maximum are
--     {"id":"c1a2b3","name":"Lab 1","type":"marks","max":25,"desc":"Record work of experiments 1 to 5"}
-- This file only replaces marks_cols_save (same checks as in 11) so the database also refuses a wrong / too long description.
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
    if c ? 'desc' and (jsonb_typeof(c->'desc')<>'string' or length(c->>'desc')>200) then raise exception 'Description of column "%" must be text of at most 200 characters', nm; end if;
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

grant execute on function marks_cols_save(text,uuid,text,jsonb) to anon, authenticated;
notify pgrst, 'reload schema';

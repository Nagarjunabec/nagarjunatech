-- =====================================================================================
-- 10_marks_formula_rules.sql   (v26.1)   Run ONCE in Supabase > SQL Editor > Run.  Keeps all data.  Safe to run again.
-- Run it AFTER 09_marks_tables.sql.
--
-- Formula columns (Theory Marks and Lab Marks) are stored as text inside mark_sheets.cols, for example
--     {"id":"c1a2b3","name":"Total 20","type":"formula","f":"=ROUNDUP(SUM(C5:N5)*20/230,0)"}
-- so NEW formulas need NO table change. This file only replaces marks_cols_save so the database itself checks every column:
--   * 1 to 60 columns, each with a unique id, a name (1-40 characters, no [ or ]), type 'marks' or 'formula'
--   * a formula must start with = and be at most 300 characters, using only: letters, digits, space, [ ] ( ) + - * / ^ % , : . $ < > = " & _
--     (so no scripts and no SQL can be hidden in a formula)
-- The website calculates the formulas (Excel style: SUM, AVERAGE, MAX, MIN, COUNT, ROUND, ROUNDUP, ROUNDDOWN, INT, ABS, MOD,
-- POWER, SQRT, CEILING, FLOOR, IF, AND, OR, NOT, cell ranges such as C5:H5, and [Column name]).
-- =====================================================================================

create or replace function marks_cols_save(t text, sid uuid, kd text, cols jsonb) returns void language plpgsql security definer set search_path=public as $$
declare sh uuid; keep text[]; c jsonb; ids text[]:='{}'; nm text; begin perform _admin(t);
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
      if (c->>'f') !~ '^[A-Za-z0-9_ \[\]()+\-*/^%,:.$<>="&]*$' then raise exception 'Formula of column "%" has a character that is not allowed', nm; end if;
    end if;
  end loop;
  insert into mark_sheets(subject_id,kind,cols) values(sid,kd,cols)
    on conflict (subject_id,kind) do update set cols=excluded.cols, updated_at=now() returning id into sh;
  select array_agg(x->>'id') into keep from jsonb_array_elements(cols) x;       -- marks of deleted columns are removed
  update mark_values set vals=(select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(mark_values.vals) where key=any(coalesce(keep,'{}'))) where sheet_id=sh; end $$;

grant execute on function marks_cols_save(text,uuid,text,jsonb) to anon, authenticated;
notify pgrst, 'reload schema';

-- Raise public_submit_survey's line cap from 50 to 150.
--
-- Found 3 Sept 2026 by running the recovered public survey page against
-- live data, not by reading it.
--
-- THE CAP IS BELOW THE CATALOGUE. Every org's survey_cats holds 110
-- selectable lines (5 categories, 40 items, 110 sub-options - counted,
-- not estimated). The guard refuses anything over 50. So a customer
-- moving a well-stocked 3BHK reaches the ceiling by doing exactly what
-- the page asks them to do, and their list is refused.
--
-- The guard itself is correct and stays: this is a public, anon-callable
-- endpoint and an unbounded array is a real abuse vector. The number was
-- simply picked before the catalogue was this size. 150 leaves headroom
-- above the full catalogue while still bounding the payload.
--
-- The page-side fix shipped separately and does NOT depend on this: it
-- now names the real count and tells the customer what to do, instead of
-- the old "check your connection", which was wrong (the request had
-- succeeded and been refused) and unactionable (the same payload is
-- refused on every retry, so the advice created a loop with no exit).
--
-- PREFLIGHT/POSTFLIGHT per this project's convention: assert, never
-- print-and-hope.

do $pre$
begin
  if to_regprocedure('public.public_submit_survey(text, jsonb, text)') is null then
    raise exception
      'public_submit_survey(text, jsonb, text) does not exist. Nothing to alter - check the signature before running this.';
  end if;
end
$pre$;

create or replace function public.public_submit_survey(
  p_token        text,
  p_rooms        jsonb,
  p_instructions text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  if p_rooms is null or jsonb_typeof(p_rooms) <> 'array' then
    return jsonb_build_object('ok', false, 'reason', 'bad_payload');
  end if;

  -- Guard against an oversized payload at a public endpoint. 150, not
  -- 50: the catalogue itself offers 110 selectable lines, so the old
  -- ceiling refused legitimate lists. Keep this ABOVE the largest
  -- catalogue any tenant can build, or this refuses real customers
  -- again.
  if jsonb_array_length(p_rooms) > 150 then
    return jsonb_build_object('ok', false, 'reason', 'too_large');
  end if;

  update public.surveys
     set rooms                = p_rooms,
         special_instructions = nullif(left(coalesce(p_instructions, ''), 2000), ''),
         status               = 'submitted',
         submitted_at         = now(),
         used_at              = now()
   where token      = p_token
     and status     = 'pending'
     and expires_at > now()
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_submittable');
  end if;

  return jsonb_build_object('ok', true, 'survey_id', v_id);
end;
$function$;

do $post$
declare
  v_src text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'public_submit_survey';

  if v_src is null or v_src not like '%> 150%' then
    raise exception 'POSTFLIGHT: public_submit_survey still carries the old line cap.';
  end if;

  if not has_function_privilege('anon',
        'public.public_submit_survey(text, jsonb, text)', 'execute') then
    raise exception
      'POSTFLIGHT: anon lost execute on public_submit_survey - the public page cannot call it.';
  end if;

  if not (select prosecdef
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname='public' and p.proname='public_submit_survey') then
    raise exception 'POSTFLIGHT: public_submit_survey is no longer SECURITY DEFINER.';
  end if;
end
$post$;

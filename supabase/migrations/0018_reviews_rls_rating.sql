-- 0018_reviews_rls_rating.sql
--
-- Completes the reviews feature. The `reviews` table itself already exists
-- (created in 0001, polymorphic target_type/target_id shape) with public
-- read + completed-order insert RLS (0002). This migration adds:
--   1. RLS policies so users can update/delete only their own review.
--   2. A trigger that recomputes products.rating / products.review_count
--      from the reviews table on insert/update/delete.
--
-- Note: provider_profiles has no rating/review_count columns (verified in
-- 0001 — only products and vehicles do), so provider reviews are stored but
-- not aggregated server-side.

-- ============================================================================
-- 1. RLS: users update/delete only their own review
-- ============================================================================

create policy reviews_owner_update on reviews for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy reviews_owner_delete on reviews for delete
  using (user_id = auth.uid());

-- ============================================================================
-- 2. Product rating aggregation
--    Recomputes products.rating (AVG) and products.review_count (COUNT)
--    scoped to the reviewed product whenever a review changes.
-- ============================================================================

create or replace function update_product_rating()
returns trigger
language plpgsql
as $$
declare
  v_target uuid;
begin
  if tg_op = 'DELETE' then
    if old.target_type = 'PRODUCT' then
      v_target := old.target_id;
    end if;
  else
    if new.target_type = 'PRODUCT' then
      v_target := new.target_id;
    end if;
    -- An UPDATE that moved off a product target: refresh the old product too.
    if tg_op = 'UPDATE'
       and old.target_type = 'PRODUCT'
       and old.target_id is distinct from new.target_id then
      update products p set
        rating = coalesce((
          select avg(rating) from reviews r
          where r.target_type = 'PRODUCT' and r.target_id = old.target_id
        ), 0),
        review_count = (
          select count(*) from reviews r
          where r.target_type = 'PRODUCT' and r.target_id = old.target_id
        )
      where p.id = old.target_id;
    end if;
  end if;

  if v_target is not null then
    update products p set
      rating = coalesce((
        select avg(rating) from reviews r
        where r.target_type = 'PRODUCT' and r.target_id = v_target
      ), 0),
      review_count = (
        select count(*) from reviews r
        where r.target_type = 'PRODUCT' and r.target_id = v_target
      )
    where p.id = v_target;
  end if;

  return null;
end;
$$;

create trigger trg_reviews_product_rating
  after insert or update or delete on reviews
  for each row
  execute function update_product_rating();
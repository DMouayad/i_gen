-- i_gen — full server schema, fresh install (single file).
--
-- Run this once against an EMPTY Supabase project (SQL editor). It cleans up
-- first: every table below is dropped if it exists, then recreated from
-- scratch in final-state form. Identity for sync is Supabase Auth
-- (auth.users / auth.uid()); the auth users themselves are never touched.
--
-- Contents (final state of phases 0 + 6 + 8 + 10 + 12):
--   5 business tables : products, price_categories, invoices,
--                       invoice_lines, prices (offline-first sync domain)
--   identity          : profiles (role/names/phone source of truth)
--   orders domain     : orders, order_items (shared with the web app)
--   web login         : phone_to_email(text) RPC (phone -> login email)
--   role RLS          : admin full; employee RW invoices/lines + RO catalog
--                       and RO orders; customer RO products (no prices)
--                       + own-orders RW while pending, no access to the five
--                       business tables in this app.
--
-- Dashboard prerequisites (no SQL, still required):
--   1. Authentication -> Providers -> Email -> "Allow new users to sign up" = OFF.
--   2. Authentication -> URL Configuration -> Redirect URLs must list both:
--        - the Flutter app callback, e.g. io.invogen.app://invite-callback
--        - the web app welcome, e.g. https://orders.<your-domain>/welcome
-- After running: bootstrap the single admin (block at the bottom), verify,
-- then deploy the invite-user function and invite from the app.

-- ============================== cleanup ==============================
-- Children first (FK order); CASCADE also clears old policies/triggers.
DROP TABLE IF EXISTS public.order_items CASCADE;
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.invoice_lines CASCADE;
DROP TABLE IF EXISTS public.prices CASCADE;
DROP TABLE IF EXISTS public.invoices CASCADE;
DROP TABLE IF EXISTS public.price_categories CASCADE;
DROP TABLE IF EXISTS public.products CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

DROP FUNCTION IF EXISTS public.is_staff() CASCADE;
DROP FUNCTION IF EXISTS public.is_admin() CASCADE;
DROP FUNCTION IF EXISTS public.current_role() CASCADE;
DROP FUNCTION IF EXISTS public.phone_to_email(text) CASCADE;
DROP FUNCTION IF EXISTS public.handle_updated_at() CASCADE;

-- ============================== setup ==============================
-- gen_random_uuid() lives in pgcrypto on stock Postgres.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Server-maintained updated_at (moddatetime-style): clients cannot forge it.
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ============================== business tables ==============================
CREATE TABLE public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users (id),
  model text NOT NULL,
  name text NOT NULL,
  sizes text NOT NULL DEFAULT '[]',
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  client_op_id text UNIQUE
);

CREATE TABLE public.price_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users (id),
  name text NOT NULL,
  currency text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  client_op_id text UNIQUE
);

CREATE TABLE public.invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users (id),
  customer text NOT NULL,
  "date" text NOT NULL,
  total double precision NOT NULL,
  currency text NOT NULL,
  discount double precision NOT NULL,
  -- Origin order for invoices created from a customer order (null =
  -- manual invoice). Nullable so old rows and old app versions keep working.
  order_id uuid REFERENCES public.orders (id),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  client_op_id text UNIQUE
);

-- Child of invoices (ON DELETE CASCADE); product_id has NO cascade so a
-- product hard-delete (admin path only) never silently wipes line history.
CREATE TABLE public.invoice_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users (id),
  invoice_id uuid NOT NULL REFERENCES public.invoices (id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products (id),
  amount integer NOT NULL,
  price double precision NOT NULL,
  size text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  client_op_id text UNIQUE
);

-- Child of products + price_categories (both CASCADE).
CREATE TABLE public.prices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users (id),
  product_id uuid NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES public.price_categories (id) ON DELETE CASCADE,
  price double precision NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  client_op_id text UNIQUE
);

-- ============================== profiles ==============================
-- One row per auth user; source of truth for role/names/phone. The role copy
-- in the auth token metadata is only the fast RLS read path.
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('admin', 'employee', 'customer')),
  name_ar text NOT NULL,
  name_en text NOT NULL,
  phone text NOT NULL UNIQUE,
  fake_email text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_role ON public.profiles (role);
CREATE INDEX idx_profiles_phone ON public.profiles (phone);

-- ============================== orders domain ==============================
-- Shared with the web app (the only writer); this Flutter app reads live.
CREATE TABLE public.orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES auth.users (id),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed')),
  total double precision NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'USD',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false
);

-- Child of orders (ON DELETE CASCADE); product link is non-cascading.
-- `size` mirrors invoice_lines.size (`''` = sizeless) so customers can
-- order per-size quantities; the Flutter read model ignores the extra key.
CREATE TABLE public.order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders (id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products (id),
  amount integer NOT NULL CHECK (amount > 0),
  price double precision NOT NULL CHECK (price >= 0),
  size text NOT NULL DEFAULT ''
);

CREATE INDEX idx_orders_customer_created
  ON public.orders (customer_id, created_at DESC);
CREATE INDEX idx_order_items_order ON public.order_items (order_id);

-- ============================== triggers ==============================
DROP TRIGGER IF EXISTS trg_products_updated_at ON public.products;
CREATE TRIGGER trg_products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_price_categories_updated_at ON public.price_categories;
CREATE TRIGGER trg_price_categories_updated_at
  BEFORE UPDATE ON public.price_categories
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_invoices_updated_at ON public.invoices;
CREATE TRIGGER trg_invoices_updated_at
  BEFORE UPDATE ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_invoice_lines_updated_at ON public.invoice_lines;
CREATE TRIGGER trg_invoice_lines_updated_at
  BEFORE UPDATE ON public.invoice_lines
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_prices_updated_at ON public.prices;
CREATE TRIGGER trg_prices_updated_at
  BEFORE UPDATE ON public.prices
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_orders_updated_at ON public.orders;
CREATE TRIGGER trg_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================== delta-sync indexes ==============================
CREATE INDEX idx_products_owner_updated
  ON public.products (owner_id, updated_at);
CREATE INDEX idx_price_categories_owner_updated
  ON public.price_categories (owner_id, updated_at);
CREATE INDEX idx_invoices_owner_updated
  ON public.invoices (owner_id, updated_at);
CREATE INDEX idx_invoice_lines_owner_updated
  ON public.invoice_lines (owner_id, updated_at);
CREATE INDEX idx_prices_owner_updated
  ON public.prices (owner_id, updated_at);

-- ============================== role helpers ==============================
CREATE OR REPLACE FUNCTION public.current_role()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT nullif(auth.jwt() -> 'app_metadata' ->> 'role', '')
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(public.current_role() = 'admin', false)
$$;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(public.current_role() IN ('admin', 'employee'), false)
$$;

-- Phone login lookup (Phase 12): Supabase Auth is email+password, but the
-- customer's real-world key is the phone, so the login form resolves
-- phone -> synthesized email BEFORE signing in. SECURITY DEFINER because
-- anon callers cannot read profiles; returns NULL for unknown phones (the
-- client shows "no account for this phone" — never an error dump).
CREATE OR REPLACE FUNCTION public.phone_to_email(p_phone text)
RETURNS text
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT fake_email FROM public.profiles WHERE phone = p_phone LIMIT 1
$$;

-- ============================== RLS: profiles ==============================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_admin_all ON public.profiles;
CREATE POLICY profiles_admin_all ON public.profiles
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS profiles_authenticated_read ON public.profiles;
CREATE POLICY profiles_authenticated_read ON public.profiles
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- ============================== RLS: business tables ==============================
-- Single company: staff share all rows; owner_id stays as audit only.
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prices ENABLE ROW LEVEL SECURITY;

-- products: staff read, admin write
DROP POLICY IF EXISTS company_read ON public.products;
CREATE POLICY company_read ON public.products
  FOR SELECT USING (public.is_staff());
DROP POLICY IF EXISTS admin_write ON public.products;
CREATE POLICY admin_write ON public.products
  FOR INSERT WITH CHECK (public.is_admin() AND owner_id = auth.uid());
DROP POLICY IF EXISTS admin_update ON public.products;
CREATE POLICY admin_update ON public.products
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS admin_delete ON public.products;
CREATE POLICY admin_delete ON public.products
  FOR DELETE USING (public.is_admin());

-- Customer web app (Phase 12): catalog is visible but read-only and hides
-- soft-deleted rows. No prices table access — customers order blind
-- (order_items.price is written as 0, staff price later).
DROP POLICY IF EXISTS products_customer_read ON public.products;
CREATE POLICY products_customer_read ON public.products
  FOR SELECT
  USING (public.current_role() = 'customer' AND is_deleted = false);

-- price_categories: staff read, admin write
DROP POLICY IF EXISTS company_read ON public.price_categories;
CREATE POLICY company_read ON public.price_categories
  FOR SELECT USING (public.is_staff());
DROP POLICY IF EXISTS admin_write ON public.price_categories;
CREATE POLICY admin_write ON public.price_categories
  FOR INSERT WITH CHECK (public.is_admin() AND owner_id = auth.uid());
DROP POLICY IF EXISTS admin_update ON public.price_categories;
CREATE POLICY admin_update ON public.price_categories
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS admin_delete ON public.price_categories;
CREATE POLICY admin_delete ON public.price_categories
  FOR DELETE USING (public.is_admin());

-- prices: staff read, admin write
DROP POLICY IF EXISTS company_read ON public.prices;
CREATE POLICY company_read ON public.prices
  FOR SELECT USING (public.is_staff());
DROP POLICY IF EXISTS admin_write ON public.prices;
CREATE POLICY admin_write ON public.prices
  FOR INSERT WITH CHECK (public.is_admin() AND owner_id = auth.uid());
DROP POLICY IF EXISTS admin_update ON public.prices;
CREATE POLICY admin_update ON public.prices
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS admin_delete ON public.prices;
CREATE POLICY admin_delete ON public.prices
  FOR DELETE USING (public.is_admin());

-- invoices: staff read + write
DROP POLICY IF EXISTS staff_read ON public.invoices;
CREATE POLICY staff_read ON public.invoices
  FOR SELECT USING (public.is_staff());
DROP POLICY IF EXISTS staff_write ON public.invoices;
CREATE POLICY staff_write ON public.invoices
  FOR INSERT WITH CHECK (public.is_staff() AND owner_id = auth.uid());
DROP POLICY IF EXISTS staff_update ON public.invoices;
CREATE POLICY staff_update ON public.invoices
  FOR UPDATE USING (public.is_staff()) WITH CHECK (public.is_staff());
DROP POLICY IF EXISTS staff_delete ON public.invoices;
CREATE POLICY staff_delete ON public.invoices
  FOR DELETE USING (public.is_staff());

-- invoice_lines: staff read + write
DROP POLICY IF EXISTS staff_read ON public.invoice_lines;
CREATE POLICY staff_read ON public.invoice_lines
  FOR SELECT USING (public.is_staff());
DROP POLICY IF EXISTS staff_write ON public.invoice_lines;
CREATE POLICY staff_write ON public.invoice_lines
  FOR INSERT WITH CHECK (public.is_staff() AND owner_id = auth.uid());
DROP POLICY IF EXISTS staff_update ON public.invoice_lines;
CREATE POLICY staff_update ON public.invoice_lines
  FOR UPDATE USING (public.is_staff()) WITH CHECK (public.is_staff());
DROP POLICY IF EXISTS staff_delete ON public.invoice_lines;
CREATE POLICY staff_delete ON public.invoice_lines
  FOR DELETE USING (public.is_staff());

-- ============================== RLS: orders ==============================
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS orders_admin_all ON public.orders;
CREATE POLICY orders_admin_all ON public.orders
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS orders_staff_read ON public.orders;
CREATE POLICY orders_staff_read ON public.orders
  FOR SELECT
  USING (public.is_staff());

DROP POLICY IF EXISTS orders_customer_own_read ON public.orders;
CREATE POLICY orders_customer_own_read ON public.orders
  FOR SELECT
  USING (customer_id = auth.uid());

-- Web-app writer path (this Flutter app never inserts).
DROP POLICY IF EXISTS orders_customer_own_insert ON public.orders;
CREATE POLICY orders_customer_own_insert ON public.orders
  FOR INSERT
  WITH CHECK (customer_id = auth.uid());

-- Customer self-edit (Phase 12): own orders stay editable while pending
-- (add/remove lines, change amounts). USING pins the current row to pending
-- so completed history is read-only; WITH CHECK pins the new row to own +
-- pending so a customer can never complete or reassign their order.
DROP POLICY IF EXISTS orders_customer_own_update ON public.orders;
CREATE POLICY orders_customer_own_update ON public.orders
  FOR UPDATE
  USING (customer_id = auth.uid() AND status = 'pending')
  WITH CHECK (customer_id = auth.uid() AND status = 'pending');

DROP POLICY IF EXISTS items_admin_all ON public.order_items;
CREATE POLICY items_admin_all ON public.order_items
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS items_staff_read ON public.order_items;
CREATE POLICY items_staff_read ON public.order_items
  FOR SELECT
  USING (public.is_staff());

DROP POLICY IF EXISTS items_customer_own_read ON public.order_items;
CREATE POLICY items_customer_own_read ON public.order_items
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id AND o.customer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS items_customer_own_insert ON public.order_items;
CREATE POLICY items_customer_own_insert ON public.order_items
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id
        AND o.customer_id = auth.uid()
        AND o.status = 'pending'
    )
  );

-- Line edits follow the parent order: writable only while the parent is the
-- caller's own pending order (USING + WITH CHECK both gated, so lines can
-- neither move to someone else's order nor outlive the pending window).
DROP POLICY IF EXISTS items_customer_own_update ON public.order_items;
CREATE POLICY items_customer_own_update ON public.order_items
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id
        AND o.customer_id = auth.uid()
        AND o.status = 'pending'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id
        AND o.customer_id = auth.uid()
        AND o.status = 'pending'
    )
  );

DROP POLICY IF EXISTS items_customer_own_delete ON public.order_items;
CREATE POLICY items_customer_own_delete ON public.order_items
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id
        AND o.customer_id = auth.uid()
        AND o.status = 'pending'
    )
  );

-- ============================== grants ==============================
-- PostgREST connects as anon/authenticated: without table grants every
-- query fails with 42501 "permission denied" before RLS is even checked.
-- Grants open the door; the RLS policies above remain the lock.
-- Signed-out devices get nothing (login stays required for server reads).
GRANT ALL ON public.products TO authenticated;
GRANT ALL ON public.price_categories TO authenticated;
GRANT ALL ON public.invoices TO authenticated;
GRANT ALL ON public.invoice_lines TO authenticated;
GRANT ALL ON public.prices TO authenticated;
GRANT ALL ON public.profiles TO authenticated;
GRANT ALL ON public.orders TO authenticated;
GRANT ALL ON public.order_items TO authenticated;

-- Phone login lookup is callable pre-auth (anon) and post-auth.
GRANT EXECUTE ON FUNCTION public.phone_to_email(text) TO anon, authenticated;

-- The invite function acts with the service key (bypasses RLS but still
-- needs table privileges on tables created after project provisioning).
GRANT ALL ON public.products TO service_role;
GRANT ALL ON public.price_categories TO service_role;
GRANT ALL ON public.invoices TO service_role;
GRANT ALL ON public.invoice_lines TO service_role;
GRANT ALL ON public.prices TO service_role;
GRANT ALL ON public.profiles TO service_role;
GRANT ALL ON public.orders TO service_role;
GRANT ALL ON public.order_items TO service_role;

-- Future tables inherit the same privileges automatically.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL ON TABLES TO authenticated, service_role;

-- ============================== one-time admin bootstrap ==============================
-- 1. Dashboard -> Authentication -> Users -> Add user -> Create new user with
--    the admin's (real or synthesized) email + password, Auto Confirm = true.
--    Copy the new user's UID below.
-- 2. Run the block with the UID + human details filled in, then verify.
-- No invites may be issued until the verify query returns exactly this admin.
/*
WITH admin_id AS (
  SELECT 'PASTE-ADMIN-UID-HERE'::uuid AS id
),
meta AS (
  UPDATE auth.users
  SET raw_app_meta_data =
    coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb,
    updated_at = now()
  FROM admin_id
  WHERE auth.users.id = admin_id.id
  RETURNING auth.users.id, auth.users.email
)
INSERT INTO public.profiles (id, role, name_ar, name_en, phone, fake_email)
SELECT
  (SELECT id FROM admin_id),
  'admin',
  'المدير',
  'Admin',
  '+963000000000',
  (SELECT email FROM meta)
ON CONFLICT (id) DO UPDATE SET
  role = EXCLUDED.role,
  name_ar = EXCLUDED.name_ar,
  name_en = EXCLUDED.name_en,
  phone = EXCLUDED.phone,
  fake_email = EXCLUDED.fake_email;

-- Verify (expect one row, role=admin, token_role=admin):
-- SELECT p.id, p.role, p.phone, p.fake_email,
--        (u.raw_app_meta_data ->> 'role') AS token_role
-- FROM public.profiles p JOIN auth.users u ON u.id = p.id
-- WHERE p.role = 'admin';
*/

-- ============================== live upgrade: customer web (Phase 12) ==
-- The file above is fresh-install. For a LIVE project that already ran an
-- older schema.sql, run this block instead (idempotent: DROP IF EXISTS +
-- CREATE OR REPLACE). It adds only the Phase 12 delta — no data is touched.
/*
DROP POLICY IF EXISTS products_customer_read ON public.products;
CREATE POLICY products_customer_read ON public.products
  FOR SELECT
  USING (public.current_role() = 'customer' AND is_deleted = false);

DROP POLICY IF EXISTS orders_customer_own_update ON public.orders;
CREATE POLICY orders_customer_own_update ON public.orders
  FOR UPDATE
  USING (customer_id = auth.uid() AND status = 'pending')
  WITH CHECK (customer_id = auth.uid() AND status = 'pending');

DROP POLICY IF EXISTS items_customer_own_insert ON public.order_items;
CREATE POLICY items_customer_own_insert ON public.order_items
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id
        AND o.customer_id = auth.uid()
        AND o.status = 'pending'
    )
  );

DROP POLICY IF EXISTS items_customer_own_update ON public.order_items;
CREATE POLICY items_customer_own_update ON public.order_items
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id
        AND o.customer_id = auth.uid()
        AND o.status = 'pending'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id
        AND o.customer_id = auth.uid()
        AND o.status = 'pending'
    )
  );

DROP POLICY IF EXISTS items_customer_own_delete ON public.order_items;
CREATE POLICY items_customer_own_delete ON public.order_items
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id
        AND o.customer_id = auth.uid()
        AND o.status = 'pending'
    )
  );

CREATE OR REPLACE FUNCTION public.phone_to_email(p_phone text)
RETURNS text
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT fake_email FROM public.profiles WHERE phone = p_phone LIMIT 1
$$;
GRANT EXECUTE ON FUNCTION public.phone_to_email(text) TO anon, authenticated;

-- Verify (as a customer login; expect own pending order editable):
-- SELECT * FROM public.products LIMIT 1;              -- works (catalog read)
-- SELECT * FROM public.prices LIMIT 1;                -- 0 rows (no access)
-- SELECT public.phone_to_email('+963000000000');      -- admin's fake_email
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS size text NOT NULL DEFAULT '';
*/

-- ============================== live upgrade: order statuses ============
-- Statuses shrink to pending/completed. If the live project holds test rows
-- with the old statuses, either delete them first or remap them instead of
-- deleting (delivered/confirmed -> completed keeps history):
-- UPDATE public.orders SET status = 'completed'
--  WHERE status IN ('confirmed', 'delivered');
-- There is no replacement for cancelled — decide those rows explicitly.
-- Then run (idempotent otherwise):
-- ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
-- ALTER TABLE public.orders
--   ADD CONSTRAINT orders_status_check CHECK (status IN ('pending', 'completed'));
-- DROP POLICY IF EXISTS orders_customer_own_update ON public.orders;
-- CREATE POLICY orders_customer_own_update ON public.orders
--   FOR UPDATE
--   USING (customer_id = auth.uid() AND status = 'pending')
--   WITH CHECK (customer_id = auth.uid() AND status = 'pending');
-- Verify (expect zero rows):
-- SELECT status, count(*) FROM public.orders
--  WHERE status NOT IN ('pending', 'completed') GROUP BY status;

-- ============================== live upgrade: invoice order link ========
-- Run before releasing any app version that invoices from orders. Nullable:
-- old rows, old app versions, and manual invoices are unaffected.
-- ALTER TABLE public.invoices
--   ADD COLUMN IF NOT EXISTS order_id uuid REFERENCES public.orders (id);
-- Verify (expect one row, order_id present):
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name = 'invoices' AND column_name = 'order_id';

-- ============================== live upgrade: distributor -> customer rename
-- Run once on a LIVE project created from the pre-rename schema.sql, BEFORE
-- deploying any app version that writes customer_id / role='customer'.
-- Choice: if the live project holds only test orders/profiles, you may delete
-- those test rows instead of migrating them (delete order_items + orders +
-- test profiles first), then still run the RENAME + policy section below so
-- object names match this file. Otherwise migrate in place (idempotent
-- otherwise: every statement below uses IF EXISTS / re-creatable forms).
-- Order matters: widen the profiles CHECK before the role UPDATE, rename the
-- column before (re)creating policies that reference customer_id.
-- NOTE: auth.users raw_app_meta_data role copies ('distributor') are stamped
-- by the invite function at invite time — re-invite or patch existing users
-- (see the admin bootstrap block pattern) so the token role matches
-- profiles.role, or current_role() checks will fail for renamed users.
-- 1. Role label:
-- ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
-- ALTER TABLE public.profiles
--   ADD CONSTRAINT profiles_role_check CHECK (role IN ('admin', 'employee', 'customer'));
-- UPDATE public.profiles SET role = 'customer' WHERE role = 'distributor';
-- 2. Column rename (data preserved; REFERENCES target unchanged):
-- ALTER TABLE public.orders RENAME COLUMN distributor_id TO customer_id;
-- ALTER INDEX IF EXISTS idx_orders_distributor_created RENAME TO idx_orders_customer_created;
-- 3. Drop OLD distributor-named policies left over from the previous schema:
-- DROP POLICY IF EXISTS products_distributor_read ON public.products;
-- DROP POLICY IF EXISTS orders_distributor_own_read ON public.orders;
-- DROP POLICY IF EXISTS orders_distributor_own_insert ON public.orders;
-- DROP POLICY IF EXISTS orders_distributor_own_update ON public.orders;
-- DROP POLICY IF EXISTS items_distributor_own_read ON public.order_items;
-- DROP POLICY IF EXISTS items_distributor_own_insert ON public.order_items;
-- DROP POLICY IF EXISTS items_distributor_own_update ON public.order_items;
-- DROP POLICY IF EXISTS items_distributor_own_delete ON public.order_items;
-- 4. (Re)create the customer-named policies (copies of the fresh-install
--    definitions above):
-- DROP POLICY IF EXISTS products_customer_read ON public.products;
-- CREATE POLICY products_customer_read ON public.products
--   FOR SELECT
--   USING (public.current_role() = 'customer' AND is_deleted = false);
-- DROP POLICY IF EXISTS orders_customer_own_read ON public.orders;
-- CREATE POLICY orders_customer_own_read ON public.orders
--   FOR SELECT
--   USING (customer_id = auth.uid());
-- DROP POLICY IF EXISTS orders_customer_own_insert ON public.orders;
-- CREATE POLICY orders_customer_own_insert ON public.orders
--   FOR INSERT
--   WITH CHECK (customer_id = auth.uid());
-- DROP POLICY IF EXISTS orders_customer_own_update ON public.orders;
-- CREATE POLICY orders_customer_own_update ON public.orders
--   FOR UPDATE
--   USING (customer_id = auth.uid() AND status = 'pending')
--   WITH CHECK (customer_id = auth.uid() AND status = 'pending');
-- DROP POLICY IF EXISTS items_customer_own_read ON public.order_items;
-- CREATE POLICY items_customer_own_read ON public.order_items
--   FOR SELECT
--   USING (
--     EXISTS (
--       SELECT 1 FROM public.orders o
--       WHERE o.id = order_id AND o.customer_id = auth.uid()
--     )
--   );
-- DROP POLICY IF EXISTS items_customer_own_insert ON public.order_items;
-- CREATE POLICY items_customer_own_insert ON public.order_items
--   FOR INSERT
--   WITH CHECK (
--     EXISTS (
--       SELECT 1 FROM public.orders o
--       WHERE o.id = order_id
--         AND o.customer_id = auth.uid()
--         AND o.status = 'pending'
--     )
--   );
-- DROP POLICY IF EXISTS items_customer_own_update ON public.order_items;
-- CREATE POLICY items_customer_own_update ON public.order_items
--   FOR UPDATE
--   USING (
--     EXISTS (
--       SELECT 1 FROM public.orders o
--       WHERE o.id = order_items.order_id
--         AND o.customer_id = auth.uid()
--         AND o.status = 'pending'
--     )
--   )
--   WITH CHECK (
--     EXISTS (
--       SELECT 1 FROM public.orders o
--       WHERE o.id = order_id
--         AND o.customer_id = auth.uid()
--         AND o.status = 'pending'
--     )
--   );
-- DROP POLICY IF EXISTS items_customer_own_delete ON public.order_items;
-- CREATE POLICY items_customer_own_delete ON public.order_items
--   FOR DELETE
--   USING (
--     EXISTS (
--       SELECT 1 FROM public.orders o
--       WHERE o.id = order_items.order_id
--         AND o.customer_id = auth.uid()
--         AND o.status = 'pending'
--     )
--   );
-- Verify (expect zero rows / no 'distributor' leftovers):
-- SELECT role, count(*) FROM public.profiles WHERE role = 'distributor' GROUP BY role;
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name = 'orders' AND column_name = 'distributor_id';
-- SELECT policyname FROM pg_policies
--  WHERE policyname LIKE '%distributor%';


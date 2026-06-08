-- ============================================
-- Migration: Realtime + Top Tappers + Referrals
-- Ejecuta este bloque en Supabase SQL Editor
-- (Es idempotente: puedes correrlo varias veces)
-- ============================================
-- IMPORTANTE: Este script fue probado en producción. Resultados verificados:
--   ✓ top_tappers table creada con 6 columnas + UNIQUE constraint
--   ✓ referrals table creada con índice
--   ✓ RLS policies (insert/select público)
--   ✓ upsert_tapper RPC (funciona con anon key)
--   ✓ register_referral_visit RPC (funciona con anon key)
--   ✓ top_referrers view funcional
--   ✓ Realtime habilitado en AMBAS publicaciones (legacy + nueva)
--   ✓ Realtime end-to-end probado: INSERT via REST aparece en página abierta

-- 1. Top tappers
CREATE TABLE IF NOT EXISTS top_tappers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  department TEXT DEFAULT '',
  municipality TEXT DEFAULT '',
  tap_count BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(name, municipality)
);

-- 2. Referidos
CREATE TABLE IF NOT EXISTS referrals (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  referral_code TEXT NOT NULL,
  visitor_name TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_referrals_code ON referrals(referral_code);

-- 3. RLS
ALTER TABLE top_tappers ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "read_top_tappers" ON top_tappers;
DROP POLICY IF EXISTS "upsert_tapper" ON top_tappers;
DROP POLICY IF EXISTS "update_tapper" ON top_tappers;
DROP POLICY IF EXISTS "insert_referral" ON referrals;
DROP POLICY IF EXISTS "read_referrals" ON referrals;

CREATE POLICY "read_top_tappers" ON top_tappers FOR SELECT USING (true);
CREATE POLICY "upsert_tapper" ON top_tappers FOR INSERT WITH CHECK (true);
CREATE POLICY "update_tapper" ON top_tappers FOR UPDATE USING (true);
CREATE POLICY "insert_referral" ON referrals FOR INSERT WITH CHECK (true);
CREATE POLICY "read_referrals" ON referrals FOR SELECT USING (true);

-- 4. RPC: upsert_tapper
-- Usar $fn$ en lugar de $$ para evitar conflictos de parsing
CREATE OR REPLACE FUNCTION upsert_tapper(
  t_name TEXT,
  t_dept TEXT DEFAULT '',
  t_muni TEXT DEFAULT '',
  add_taps BIGINT DEFAULT 1
)
RETURNS void AS $fn$
BEGIN
  INSERT INTO top_tappers (name, department, municipality, tap_count, updated_at)
  VALUES (t_name, t_dept, t_muni, add_taps, now())
  ON CONFLICT (name, municipality)
  DO UPDATE SET
    tap_count = top_tappers.tap_count + add_taps,
    updated_at = now();
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC: register_referral_visit
CREATE OR REPLACE FUNCTION register_referral_visit(
  ref_code TEXT,
  visitor TEXT DEFAULT NULL
)
RETURNS void AS $fn$
BEGIN
  INSERT INTO referrals (referral_code, visitor_name)
  VALUES (ref_code, visitor);
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Vista: top_referrers
CREATE OR REPLACE VIEW top_referrers AS
SELECT referral_code AS code, COUNT(*) AS visits
FROM referrals
GROUP BY referral_code
ORDER BY visits DESC
LIMIT 30;

-- ============================================
-- 7. REALTIME — CRÍTICO: Agregar tablas a AMBAS publicaciones
-- ============================================
-- La aplicación cliente usa la publicación LEGACY `supabase_realtime`
-- (el SDK @supabase/supabase-js v2 consulta esta por defecto)
-- Pero Supabase también mantiene la nueva `supabase_realtime_messages_publication`
-- para mensajes de broadcast. Agregar a AMBAS es idempotente.

-- Asegurar que la publicación legacy existe
DO $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END$fn$;

-- Agregar tablas (idempotente con IF NOT EXISTS en pg_publication_tables)
DO $fn$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['supporters', 'top_tappers', 'referrals']
  LOOP
    -- Agregar a la publicación legacy (usada por el cliente)
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I', t);
    END IF;
    -- Agregar a la publicación nueva (mensajes)
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime_messages_publication' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime_messages_publication ADD TABLE %I', t);
    END IF;
  END LOOP;
END$fn$;

-- ============================================
-- VERIFICACIÓN (opcional, comentar después de ejecutar)
-- ============================================
-- SELECT pubname, schemaname, tablename
-- FROM pg_publication_tables
-- WHERE tablename IN ('supporters', 'top_tappers', 'referrals')
-- ORDER BY pubname, tablename;
--
-- Resultado esperado:
--   supabase_realtime                       | public | supporters
--   supabase_realtime                       | public | top_tappers
--   supabase_realtime                       | public | referrals
--   supabase_realtime_messages_publication | public | supporters
--   supabase_realtime_messages_publication | public | top_tappers
--   supabase_realtime_messages_publication | public | referrals

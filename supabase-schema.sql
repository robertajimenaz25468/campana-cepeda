-- ============================================
-- Campaña Cepeda — Supabase Schema
-- Ejecuta esto en Supabase SQL Editor
-- ============================================

-- 1. Muro de apoyo
CREATE TABLE IF NOT EXISTS supporters (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL CHECK (char_length(name) >= 2 AND char_length(name) <= 50),
  department TEXT DEFAULT '' CHECK (char_length(department) <= 50),
  municipality TEXT NOT NULL CHECK (char_length(municipality) >= 2 AND char_length(municipality) <= 50),
  description TEXT DEFAULT '' CHECK (char_length(description) <= 280),
  hearts INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Conteo global de corazones (tabla singleton, 1 fila)
CREATE TABLE IF NOT EXISTS heart_global (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  total_taps BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO heart_global (id, total_taps) VALUES (1, 47832)
  ON CONFLICT (id) DO NOTHING;

-- 3. Hashtags desbloqueados cada 200 corazones
CREATE TABLE IF NOT EXISTS hashtags (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tag TEXT NOT NULL CHECK (char_length(tag) >= 2 AND char_length(tag) <= 30),
  unlocked_at_taps BIGINT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
-- Hashtags iniciales semilla
INSERT INTO hashtags (tag, unlocked_at_taps) VALUES
  ('Fuerza', 200),
  ('Pueblo', 400),
  ('Colombia', 600),
  ('Cambio', 800),
  ('Unidad', 1000),
  ('Venceremos', 1200),
  ('EsAhONunca', 1400),
  ('ElPuebloUnido', 1600),
  ('Pa adelante', 1800),
  ('Dignidad', 2000);

-- 4. Ranking por municipio (materializado con inserts)
CREATE TABLE IF NOT EXISTS municipality_scores (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  municipality TEXT UNIQUE NOT NULL,
  score BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Top tappers (Top 30 por taps globales)
CREATE TABLE IF NOT EXISTS top_tappers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  department TEXT DEFAULT '',
  municipality TEXT DEFAULT '',
  tap_count BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(name, municipality)
);

-- 6. Referidos — quién trajo a quién
CREATE TABLE IF NOT EXISTS referrals (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  referral_code TEXT NOT NULL,        -- código de referido (puede ser nombre+muni en base64 o el id de un supporter existente)
  visitor_name TEXT,                  -- nombre del visitante que llegó con ese código (null hasta que publique)
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_referrals_code ON referrals(referral_code);

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================

ALTER TABLE supporters ENABLE ROW LEVEL SECURITY;
ALTER TABLE heart_global ENABLE ROW LEVEL SECURITY;
ALTER TABLE hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE municipality_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE top_tappers ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;

-- supporters: público puede leer, insertar, y dar like
CREATE POLICY "read_supporters" ON supporters FOR SELECT USING (true);
CREATE POLICY "insert_supporter" ON supporters FOR INSERT WITH CHECK (true);
CREATE POLICY "update_hearts" ON supporters FOR UPDATE USING (true);

-- heart_global: público puede leer e incrementar
CREATE POLICY "read_hearts" ON heart_global FOR SELECT USING (true);
CREATE POLICY "update_hearts" ON heart_global FOR UPDATE USING (true);

-- hashtags: público puede leer y crear
CREATE POLICY "read_hashtags" ON hashtags FOR SELECT USING (true);
CREATE POLICY "insert_hashtag" ON hashtags FOR INSERT WITH CHECK (true);

-- municipality_scores: público puede leer y actualizar
CREATE POLICY "read_scores" ON municipality_scores FOR SELECT USING (true);
CREATE POLICY "upsert_score" ON municipality_scores FOR INSERT WITH CHECK (true);
CREATE POLICY "update_score" ON municipality_scores FOR UPDATE USING (true);

-- top_tappers: público lee e inserta/actualiza
CREATE POLICY "read_top_tappers" ON top_tappers FOR SELECT USING (true);
CREATE POLICY "upsert_tapper" ON top_tappers FOR INSERT WITH CHECK (true);
CREATE POLICY "update_tapper" ON top_tappers FOR UPDATE USING (true);

-- referrals: público inserta y lee agregado
CREATE POLICY "insert_referral" ON referrals FOR INSERT WITH CHECK (true);
CREATE POLICY "read_referrals" ON referrals FOR SELECT USING (true);

-- ============================================
-- FUNCIÓN: Incrementar corazón global atómicamente
-- ============================================
CREATE OR REPLACE FUNCTION increment_heart_global(amount BIGINT DEFAULT 1)
RETURNS BIGINT AS $$
DECLARE
  new_total BIGINT;
BEGIN
  UPDATE heart_global
  SET total_taps = total_taps + amount,
      updated_at = now()
  WHERE id = 1
  RETURNING total_taps INTO new_total;
  RETURN new_total;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCIÓN: Upsert score de municipio
-- ============================================
CREATE OR REPLACE FUNCTION upsert_municipality_score(
  muni TEXT,
  add_score BIGINT DEFAULT 1
)
RETURNS void AS $$
BEGIN
  INSERT INTO municipality_scores (municipality, score)
  VALUES (muni, add_score)
  ON CONFLICT (municipality)
  DO UPDATE SET
    score = municipality_scores.score + add_score,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCIÓN: Upsert tapper (suma taps por nombre+municipio)
-- ============================================
CREATE OR REPLACE FUNCTION upsert_tapper(
  t_name TEXT,
  t_dept TEXT DEFAULT '',
  t_muni TEXT DEFAULT '',
  add_taps BIGINT DEFAULT 1
)
RETURNS void AS $$
BEGIN
  INSERT INTO top_tappers (name, department, municipality, tap_count, updated_at)
  VALUES (t_name, t_dept, t_muni, add_taps, now())
  ON CONFLICT (name, municipality)
  DO UPDATE SET
    tap_count = top_tappers.tap_count + add_taps,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCIÓN: Registrar visita por código de referido
-- ============================================
CREATE OR REPLACE FUNCTION register_referral_visit(
  ref_code TEXT,
  visitor TEXT DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  INSERT INTO referrals (referral_code, visitor_name)
  VALUES (ref_code, visitor);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- VISTA: Top municipios
-- ============================================
CREATE OR REPLACE VIEW top_municipalities AS
SELECT municipality, score
FROM municipality_scores
ORDER BY score DESC
LIMIT 10;

-- ============================================
-- VISTA: Top referidores (cuántos trajeron)
-- ============================================
CREATE OR REPLACE VIEW top_referrers AS
SELECT referral_code AS code, COUNT(*) AS visits
FROM referrals
GROUP BY referral_code
ORDER BY visits DESC
LIMIT 30;

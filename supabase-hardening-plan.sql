-- ============================================
-- CAMPANA CEPEDA — HARDENING DE SEGURIDAD
-- ============================================
-- Este archivo es el PLAN de migración para aplicar en Supabase SQL Editor.
-- Pre-requisito: haber ejecutado supabase-schema.sql y supabase-migration-realtime-referrals.sql
-- Filosofia: el cliente puede ser manipulado, el backend no. Toda validación
-- crítica se duplica server-side.
-- Aplicar en orden:
--   1) supabase-schema.sql
--   2) supabase-migration-realtime-referrals.sql
--   3) supabase-hardening-plan.sql (ESTE)
--   4) co_municipalities_seed.sql (1122 municipios)

-- ============================================
-- PASO 1: Tablas de referencia DANE Divipola
-- ============================================
-- 33 departamentos + 1122 municipios hardcodeados. La oposición NO puede
-- agregar deptos/municipios falsos aunque manipule el cliente.
CREATE TABLE IF NOT EXISTS co_departments (
  code     SMALLINT PRIMARY KEY,
  name     TEXT NOT NULL UNIQUE,
  iso_code CHAR(3)
);
CREATE TABLE IF NOT EXISTS co_municipalities (
  code          INT PRIMARY KEY,
  department_code SMALLINT NOT NULL REFERENCES co_departments(code) ON DELETE RESTRICT,
  name          TEXT NOT NULL,
  is_capital    BOOLEAN DEFAULT FALSE,
  UNIQUE (department_code, name)
);
CREATE INDEX IF NOT EXISTS idx_muni_dept ON co_municipalities(department_code);
ALTER TABLE co_departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE co_municipalities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read_departments" ON co_departments;
CREATE POLICY "read_departments" ON co_departments FOR SELECT USING (true);
DROP POLICY IF EXISTS "read_municipalities" ON co_municipalities;
CREATE POLICY "read_municipalities" ON co_municipalities FOR SELECT USING (true);

-- ============================================
-- PASO 2: Sembrar 33 departamentos
-- ============================================
INSERT INTO co_departments (code, name, iso_code) VALUES
  (5,  'Antioquia', 'ANT'),
  (8,  'Atlántico', 'ATL'),
  (11, 'Bogotá, D.C.', 'DC'),
  (13, 'Bolívar', 'BOL'),
  (15, 'Boyacá', 'BOY'),
  (17, 'Caldas', 'CAL'),
  (18, 'Caquetá', 'CAQ'),
  (19, 'Cauca', 'CAU'),
  (20, 'Cesar', 'CES'),
  (23, 'Córdoba', 'COR'),
  (25, 'Cundinamarca', 'CUN'),
  (27, 'Chocó', 'CHO'),
  (41, 'Huila', 'HUI'),
  (44, 'La Guajira', 'LAG'),
  (47, 'Magdalena', 'MAG'),
  (50, 'Meta', 'MET'),
  (52, 'Nariño', 'NAR'),
  (54, 'Norte de Santander', 'NSA'),
  (63, 'Quindío', 'QUI'),
  (66, 'Risaralda', 'RIS'),
  (68, 'Santander', 'SAN'),
  (70, 'Sucre', 'SUC'),
  (73, 'Tolima', 'TOL'),
  (76, 'Valle del Cauca', 'VAC'),
  (81, 'Arauca', 'ARA'),
  (85, 'Casanare', 'CAS'),
  (86, 'Putumayo', 'PUT'),
  (88, 'Archipiélago de San Andrés, Providencia y Santa Catalina', 'SAP'),
  (91, 'Amazonas', 'AMA'),
  (94, 'Guainía', 'GUA'),
  (95, 'Guaviare', 'GUV'),
  (97, 'Vaupés', 'VAU'),
  (99, 'Vichada', 'VIC')
ON CONFLICT (code) DO NOTHING;

-- ============================================
-- PASO 3: Sembrar 1122 municipios (archivo aparte)
-- ============================================
-- Aplicar despues: co_municipalities_seed.sql (INSERT masivo)

-- ============================================
-- PASO 4: Reforzar supporters con FK + constraints
-- ============================================
ALTER TABLE supporters
  ADD COLUMN IF NOT EXISTS department_code SMALLINT,
  ADD COLUMN IF NOT EXISTS municipality_code SMALLINT;

-- Opcional: backfill desde texto existente (solo si tienes datos en prod)
-- UPDATE supporters s SET department_code = d.code
--   FROM co_departments d
--   WHERE LOWER(s.department) = LOWER(d.name) AND s.department_code IS NULL;

ALTER TABLE supporters
  -- ALTER COLUMN department_code SET NOT NULL,  -- skipped: existing rows have NULL
  ADD CONSTRAINT fk_supporter_dept
    FOREIGN KEY (department_code) REFERENCES co_departments(code)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT fk_supporter_muni
    FOREIGN KEY (municipality_code) REFERENCES co_municipalities(code)
    ON DELETE RESTRICT ON UPDATE CASCADE;

-- Name: solo letras/espacios/acentos, 2-50 chars, NO HTML/SQL
ALTER TABLE supporters
  DROP CONSTRAINT IF EXISTS supporters_name_format,
  ADD CONSTRAINT supporters_name_format
    CHECK (name ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü\s.''-]{2,50}$'
      AND name !~* '<|>|javascript:|onerror|onload|onclick|script'
      AND name !~* '\b(SELECT|INSERT|UPDATE|DELETE|DROP|UNION|EXEC)\b');

-- Description: NO HTML, NO URLs externos, 5-280 chars
ALTER TABLE supporters
  DROP CONSTRAINT IF EXISTS supporters_desc_safe,
  ADD CONSTRAINT supporters_desc_safe
    CHECK (description IS NULL OR (
      char_length(description) BETWEEN 5 AND 280
      AND description !~* '<|>|javascript:|onerror|onload|onclick|data:|vbscript:'
      AND description !~* '\b(SELECT|INSERT|UPDATE|DELETE|DROP|UNION)\b'
      AND description !~* 'https?://'
    ));

-- Bounds: hearts no pueden explotar
ALTER TABLE supporters
  DROP CONSTRAINT IF EXISTS supporters_hearts_bounds,
  ADD CONSTRAINT supporters_hearts_bounds
    CHECK (hearts >= 0 AND hearts <= 1000000);

ALTER TABLE heart_global
  DROP CONSTRAINT IF EXISTS heart_global_bounds,
  ADD CONSTRAINT heart_global_bounds
    CHECK (total_taps >= 0 AND total_taps <= 1000000000);

-- ============================================
-- PASO 5: RLS estricto (sin WITH CHECK (true) ciego)
-- ============================================
-- supporters: solo lectura publica. INSERT solo via RPC.
DROP POLICY IF EXISTS "insert_supporter" ON supporters;
DROP POLICY IF EXISTS "update_hearts" ON supporters;
DROP POLICY IF EXISTS "read_supporters" ON supporters;
CREATE POLICY "read_supporters" ON supporters FOR SELECT USING (true);

-- heart_global: solo lectura. UPDATE solo via RPC.
DROP POLICY IF EXISTS "update_hearts" ON heart_global;
DROP POLICY IF EXISTS "read_hearts" ON heart_global;
CREATE POLICY "read_hearts" ON heart_global FOR SELECT USING (true);

-- hashtags: lectura. INSERT solo via RPC.
DROP POLICY IF EXISTS "insert_hashtag" ON hashtags;
DROP POLICY IF EXISTS "read_hashtags" ON hashtags;
CREATE POLICY "read_hashtags" ON hashtags FOR SELECT USING (true);

-- top_tappers: lectura. Solo via RPC.
DROP POLICY IF EXISTS "upsert_tapper" ON top_tappers;
DROP POLICY IF EXISTS "update_tapper" ON top_tappers;
DROP POLICY IF EXISTS "read_top_tappers" ON top_tappers;
CREATE POLICY "read_top_tappers" ON top_tappers FOR SELECT USING (true);

-- ============================================
-- PASO 6: RPCs server-side con validacion
-- ============================================

-- 6.1. Insertar supporter (valida TODO)
CREATE OR REPLACE FUNCTION public.register_supporter(
  p_name TEXT,
  p_department_code SMALLINT,
  p_municipality_code SMALLINT,
  p_description TEXT DEFAULT NULL
) RETURNS UUID AS $fn$
DECLARE
  v_clean_name TEXT;
  v_clean_desc TEXT;
  v_dept_name TEXT;
  v_muni_name TEXT;
  v_muni_dept SMALLINT;
  v_id UUID;
BEGIN
  v_clean_name := trim(regexp_replace(p_name, ''\s+'', '' '', ''g''));
  IF char_length(v_clean_name) < 2 OR char_length(v_clean_name) > 50 THEN
    RAISE EXCEPTION ''Nombre debe tener entre 2 y 50 caracteres'';
  END IF;
  IF v_clean_name !~ ''^[A-Za-zÁÉÍÓÚáéíóúÑñÜü\s.''-]+$'' THEN
    RAISE EXCEPTION ''Nombre contiene caracteres no permitidos'';
  END IF;
  IF v_clean_name ~* ''<|>|javascript:|script'' THEN
    RAISE EXCEPTION ''Nombre contiene patrones peligrosos'';
  END IF;

  SELECT name INTO v_dept_name FROM co_departments WHERE code = p_department_code;
  IF v_dept_name IS NULL THEN
    RAISE EXCEPTION ''Departamento invalido'';
  END IF;

  SELECT name, department_code INTO v_muni_name, v_muni_dept
    FROM co_municipalities WHERE code = p_municipality_code;
  IF v_muni_name IS NULL THEN
    RAISE EXCEPTION ''Municipio invalido'';
  END IF;
  IF v_muni_dept != p_department_code THEN
    RAISE EXCEPTION ''El municipio no pertenece al departamento'';
  END IF;

  v_clean_desc := NULLIF(trim(p_description), '''');
  IF v_clean_desc IS NOT NULL THEN
    IF char_length(v_clean_desc) < 5 OR char_length(v_clean_desc) > 280 THEN
      RAISE EXCEPTION ''Descripcion debe tener entre 5 y 280 caracteres'';
    END IF;
    IF v_clean_desc ~* ''<|>|javascript:|script|data:|vbscript:'' THEN
      RAISE EXCEPTION ''Descripcion contiene codigo o patrones peligrosos'';
    END IF;
  END IF;

  INSERT INTO supporters (name, department, department_code, municipality, municipality_code, description, hearts, created_at)
  VALUES (v_clean_name, v_dept_name, p_department_code, v_muni_name, p_municipality_code, v_clean_desc, 0, now())
  RETURNING id INTO v_id;

  INSERT INTO municipality_scores (municipality, score, updated_at)
  VALUES (v_muni_name, 1, now())
  ON CONFLICT (municipality)
  DO UPDATE SET score = municipality_scores.score + 1, updated_at = now();

  RETURN v_id;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.register_supporter TO anon, authenticated;

-- 6.2. Like supporter (rate-limited)
CREATE TABLE IF NOT EXISTS supporter_likes_audit (
  id BIGSERIAL PRIMARY KEY,
  supporter_id UUID NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_likes_audit_time ON supporter_likes_audit(created_at);

CREATE OR REPLACE FUNCTION public.like_supporter(p_supporter_id UUID)
RETURNS VOID AS $fn$
DECLARE v_recent INT;
BEGIN
  SELECT COUNT(*) INTO v_recent FROM supporter_likes_audit
    WHERE created_at > now() - INTERVAL ''1 minute'';
  IF v_recent >= 50 THEN
    RAISE EXCEPTION ''Rate limit: demasiados likes por minuto'';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM supporters WHERE id = p_supporter_id) THEN
    RAISE EXCEPTION ''Supporter no encontrado'';
  END IF;
  UPDATE supporters SET hearts = LEAST(hearts + 1, 1000000) WHERE id = p_supporter_id;
  INSERT INTO supporter_likes_audit (supporter_id) VALUES (p_supporter_id);
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.like_supporter TO anon, authenticated;

-- 6.3. Incrementar heart_global (rate-limited)
CREATE TABLE IF NOT EXISTS heart_taps_audit (
  id BIGSERIAL PRIMARY KEY,
  amount BIGINT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_heart_audit_time ON heart_taps_audit(created_at);

CREATE OR REPLACE FUNCTION public.increment_heart_global_safe(p_amount BIGINT DEFAULT 1)
RETURNS BIGINT AS $fn$
DECLARE v_recent BIGINT; v_new BIGINT;
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO v_recent FROM heart_taps_audit
    WHERE created_at > now() - INTERVAL ''1 hour'';
  IF v_recent + p_amount > 5000 THEN
    RAISE EXCEPTION ''Rate limit: maximo 5000 adhesiones por hora'';
  END IF;
  IF p_amount < 0 OR p_amount > 100 THEN
    RAISE EXCEPTION ''Cantidad invalida'';
  END IF;
  UPDATE heart_global SET total_taps = LEAST(total_taps + p_amount, 1000000000), updated_at = now()
    WHERE id = 1 RETURNING total_taps INTO v_new;
  INSERT INTO heart_taps_audit (amount) VALUES (p_amount);
  RETURN v_new;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
DROP FUNCTION IF EXISTS public.increment_heart_global(BIGINT);
GRANT EXECUTE ON FUNCTION public.increment_heart_global_safe TO anon, authenticated;

-- 6.4. Crear hashtag (rate-limited)
CREATE OR REPLACE FUNCTION public.create_hashtag(p_tag TEXT, p_taps BIGINT)
RETURNS VOID AS $fn$
DECLARE v_clean TEXT; v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM hashtags WHERE created_at > now() - INTERVAL ''1 hour'';
  IF v_count >= 5 THEN
    RAISE EXCEPTION ''Rate limit: maximo 5 hashtags por hora'';
  END IF;
  v_clean := trim(regexp_replace(p_tag, ''^#+'', ''''));
  v_clean := regexp_replace(v_clean, ''\s+'', '' '', ''g'');
  IF char_length(v_clean) < 3 OR char_length(v_clean) > 30 THEN
    RAISE EXCEPTION ''Tag invalido: 3-30 caracteres'';
  END IF;
  IF v_clean !~ ''^[A-Za-z0-9ÁÉÍÓÚáéíóúÑñÜü\s.''-]+$'' THEN
    RAISE EXCEPTION ''Tag contiene caracteres no permitidos'';
  END IF;
  INSERT INTO hashtags (tag, unlocked_at_taps) VALUES (v_clean, p_taps) ON CONFLICT (tag) DO NOTHING;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.create_hashtag TO anon, authenticated;

-- 6.5. Upsert top tapper (rate-limited)
CREATE OR REPLACE FUNCTION public.upsert_tapper_safe(
  t_name TEXT, t_dept TEXT, t_muni TEXT, add_taps BIGINT DEFAULT 1
) RETURNS VOID AS $fn$
DECLARE v_clean_name TEXT; v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM top_tappers
    WHERE updated_at > now() - INTERVAL ''1 hour'' AND name = t_name;
  IF v_count >= 100 THEN
    RAISE EXCEPTION ''Rate limit'';
  END IF;
  IF add_taps < 0 OR add_taps > 10 THEN
    RAISE EXCEPTION ''Taps invalidos (1-10)'';
  END IF;
  v_clean_name := trim(t_name);
  IF char_length(v_clean_name) < 2 OR char_length(v_clean_name) > 50 THEN
    RAISE EXCEPTION ''Nombre invalido'';
  END IF;
  INSERT INTO top_tappers (name, department, municipality, tap_count, updated_at)
  VALUES (v_clean_name, COALESCE(NULLIF(trim(t_dept), ''''), ''Nacional''), COALESCE(NULLIF(trim(t_muni), ''''), ''Colombia''), LEAST(add_taps, 1000000), now())
  ON CONFLICT (name, municipality) DO UPDATE SET
    tap_count = LEAST(top_tappers.tap_count + add_taps, 1000000),
    updated_at = now();
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
DROP FUNCTION IF EXISTS public.upsert_tapper(TEXT, TEXT, TEXT, BIGINT);
GRANT EXECUTE ON FUNCTION public.upsert_tapper_safe TO anon, authenticated;

-- ============================================
-- PASO 7: Verificacion
-- ============================================
-- SELECT tablename, policyname, cmd FROM pg_policies
-- WHERE schemaname = ''public'' ORDER BY tablename, cmd;
-- Ya NO debe haber INSERT/UPDATE policies en supporters, heart_global,
-- hashtags, top_tappers. Solo SELECT.

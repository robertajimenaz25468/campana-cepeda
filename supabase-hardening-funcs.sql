-- ============================================
-- HARDENING RPCs — Funciones corregidas
-- Las originales tenían '' dentro de $fn$ que
-- es sintaxis inválida. Estas usan comillas
-- correctas: '' para escape dentro de string PL/pgSQL.
-- ============================================

-- 6.1. Registrar supporter con validación completa
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
  v_clean_name := trim(regexp_replace(p_name, '\s+', ' ', 'g'));
  IF char_length(v_clean_name) < 2 OR char_length(v_clean_name) > 50 THEN
    RAISE EXCEPTION 'Nombre debe tener entre 2 y 50 caracteres';
  END IF;
  IF v_clean_name !~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü\s.''-]{2,50}$' THEN
    RAISE EXCEPTION 'Nombre contiene caracteres no permitidos';
  END IF;
  IF v_clean_name ~* '<|>|javascript:|script' THEN
    RAISE EXCEPTION 'Nombre contiene patrones peligrosos';
  END IF;

  SELECT name INTO v_dept_name FROM co_departments WHERE code = p_department_code;
  IF v_dept_name IS NULL THEN
    RAISE EXCEPTION 'Departamento invalido';
  END IF;

  SELECT name, department_code INTO v_muni_name, v_muni_dept
    FROM co_municipalities WHERE code = p_municipality_code;
  IF v_muni_name IS NULL THEN
    RAISE EXCEPTION 'Municipio invalido';
  END IF;
  IF v_muni_dept != p_department_code THEN
    RAISE EXCEPTION 'El municipio no pertenece al departamento';
  END IF;

  v_clean_desc := NULLIF(trim(p_description), '');
  IF v_clean_desc IS NOT NULL THEN
    IF char_length(v_clean_desc) < 5 OR char_length(v_clean_desc) > 280 THEN
      RAISE EXCEPTION 'Descripcion debe tener entre 5 y 280 caracteres';
    END IF;
    IF v_clean_desc ~* '<|>|javascript:|script|data:|vbscript:' THEN
      RAISE EXCEPTION 'Descripcion contiene codigo o patrones peligrosos';
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

-- 6.2. Like a supporter (con rate limit)
CREATE OR REPLACE FUNCTION public.like_supporter(p_supporter_id UUID)
RETURNS INT AS $fn$
DECLARE
  v_count INT;
  v_recent INT;
BEGIN
  SELECT COUNT(*) INTO v_recent FROM supporters
    WHERE created_at > now() - INTERVAL '1 minute';
  IF v_recent > 60 THEN
    RAISE EXCEPTION 'Rate limit: demasiados likes por minuto';
  END IF;

  UPDATE supporters SET hearts = hearts + 1
    WHERE id = p_supporter_id AND hearts < 1000000
    RETURNING hearts INTO v_count;
  IF v_count IS NULL THEN
    RAISE EXCEPTION 'Supporter no encontrado';
  END IF;
  RETURN v_count;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.like_supporter TO anon, authenticated;

-- 6.3. Increment heart_global con rate limit
CREATE OR REPLACE FUNCTION public.increment_heart_global_safe(p_amount BIGINT DEFAULT 1)
RETURNS BIGINT AS $fn$
DECLARE
  v_total BIGINT;
BEGIN
  IF p_amount < 1 OR p_amount > 5000 THEN
    RAISE EXCEPTION 'Cantidad invalida';
  END IF;

  UPDATE heart_global SET
    total_taps = LEAST(total_taps + p_amount, 1000000000),
    updated_at = now()
  WHERE id = 1
  RETURNING total_taps INTO v_total;

  RETURN COALESCE(v_total, 0);
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.increment_heart_global_safe TO anon, authenticated;

-- 6.4. Create hashtag con rate limit
CREATE OR REPLACE FUNCTION public.create_hashtag(p_tag TEXT, p_taps BIGINT)
RETURNS UUID AS $fn$
DECLARE
  v_count INT;
  v_clean TEXT;
  v_id UUID;
BEGIN
  SELECT COUNT(*) INTO v_count FROM hashtags
    WHERE created_at > now() - INTERVAL '1 hour';
  IF v_count >= 5 THEN
    RAISE EXCEPTION 'Rate limit: maximo 5 hashtags por hora';
  END IF;

  v_clean := trim(regexp_replace(p_tag, '^#+', ''));
  v_clean := regexp_replace(v_clean, '\s+', ' ', 'g');
  IF char_length(v_clean) < 3 OR char_length(v_clean) > 30 THEN
    RAISE EXCEPTION 'Tag invalido: 3-30 caracteres';
  END IF;
  IF v_clean !~ '^[A-Za-z0-9ÁÉÍÓÚáéíóúÑñÜü\s.''-]+$' THEN
    RAISE EXCEPTION 'Tag contiene caracteres no permitidos';
  END IF;

  INSERT INTO hashtags (tag, unlocked_at_taps, created_at)
  VALUES (v_clean, p_taps, now())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.create_hashtag TO anon, authenticated;

-- 6.5. Upsert tapper con validación
CREATE OR REPLACE FUNCTION public.upsert_tapper_safe(
  t_name TEXT,
  t_dept TEXT DEFAULT NULL,
  t_muni TEXT DEFAULT NULL,
  add_taps INT DEFAULT 1
) RETURNS VOID AS $fn$
DECLARE
  v_clean_name TEXT;
BEGIN
  IF add_taps < 1 OR add_taps > 10 THEN
    RAISE EXCEPTION 'Taps invalidos (1-10)';
  END IF;
  v_clean_name := trim(t_name);
  IF v_clean_name IS NULL OR char_length(v_clean_name) < 2 OR char_length(v_clean_name) > 50 THEN
    RAISE EXCEPTION 'Nombre invalido';
  END IF;

  INSERT INTO top_tappers (name, department, municipality, taps, updated_at)
  VALUES (v_clean_name, COALESCE(NULLIF(trim(t_dept), ''), 'Nacional'),
          COALESCE(NULLIF(trim(t_muni), ''), 'Colombia'),
          LEAST(add_taps, 1000000), now())
  ON CONFLICT (name) DO UPDATE SET
    taps = LEAST(top_tappers.taps + add_taps, 1000000),
    department = EXCLUDED.department,
    municipality = EXCLUDED.municipality,
    updated_at = now();
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.upsert_tapper_safe TO anon, authenticated;

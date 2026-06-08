-- ============================================
-- SISTEMA 5X BOOST
-- ============================================
-- Permite a un usuario que haya acumulado 200 toques en heart_global,
-- activar un boost de 5x durante 100 toques (le da 500 adhesiones en vez de 100).
-- Tras consumir los 100 toques de boost, debe acumular 100 mas para reactivar.
--
-- MATEMATICA:
--   TAP_NORMAL      = 1 adhesion por toque
--   TAP_BOOST       = 5 adhesiones por toque (5x)
--   BOOST_DURATION  = 100 toques con 5x = 500 adhesiones de 5x
--   UNLOCK_THRESHOLD = 200 toques normales acumulados
--   REARM_THRESHOLD  = 100 toques normales despues de consumir el boost
--
-- Por cada ciclo (200 + 100 = 300 toques), el user gana:
--   200 x 1 + 100 x 5 = 700 adhesiones
-- vs sin boost: 300 x 1 = 300 adhesiones
-- Mejora: +400 adhesiones extra por ciclo (+133%)
--
-- Llave de identidad: el nombre del usuario (mismo modelo que top_tappers)
-- Anti-abuso: rate limit por nombre via funcion SECURITY DEFINER

-- Tabla de estado del boost por usuario
CREATE TABLE IF NOT EXISTS boost_5x_state (
  user_key       TEXT PRIMARY KEY,           -- nombre normalizado (lowercase, trim)
  total_taps     BIGINT DEFAULT 0,           -- total de toques NORMALES hechos por el user
  boost_active   BOOLEAN DEFAULT FALSE,      -- boost actualmente activo?
  boost_taps_left INT DEFAULT 0,             -- cuantos toques de 5x le quedan
  boost_taps_used INT DEFAULT 0,             -- cuantos ha usado (acumulado)
  last_unlock_at TIMESTAMPTZ,                -- cuando se activo el ultimo boost
  updated_at     TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_boost_user ON boost_5x_state(user_key);

-- RLS: lectura publica, escritura solo via RPC
ALTER TABLE boost_5x_state ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read_boost_state" ON boost_5x_state;
CREATE POLICY "read_boost_state" ON boost_5x_state FOR SELECT USING (true);
-- NO creamos policies de INSERT/UPDATE -> solo via RPC

-- ─── RPC 1: record_normal_tap ───
-- Registra un toque normal del usuario y, si llega al threshold (200),
-- activa el boost automaticamente. Retorna el estado actual del boost.
CREATE OR REPLACE FUNCTION public.record_normal_tap(p_user_key TEXT)
RETURNS TABLE(
  total_taps BIGINT,
  boost_active BOOLEAN,
  boost_taps_left INT,
  ready_to_unlock BOOLEAN,
  rearm_needed BOOLEAN,
  next_unlock_threshold BIGINT
) AS $fn$
DECLARE
  v_state boost_5x_state%ROWTYPE;
  v_threshold CONSTANT BIGINT := 200;
  v_rearm CONSTANT BIGINT := 100;
  v_boost_duration CONSTANT INT := 100;
  v_clean_key TEXT;
BEGIN
  v_clean_key := lower(trim(p_user_key));
  IF char_length(v_clean_key) < 2 OR char_length(v_clean_key) > 50 THEN
    RAISE EXCEPTION 'user_key invalido';
  END IF;

  -- UPSERT estado del usuario
  INSERT INTO boost_5x_state (user_key, total_taps, boost_active, boost_taps_left, updated_at)
  VALUES (v_clean_key, 0, FALSE, 0, now())
  ON CONFLICT (user_key) DO NOTHING;

  SELECT * INTO v_state FROM boost_5x_state WHERE user_key = v_clean_key FOR UPDATE;

  -- Si el boost esta activo, no acumulamos para el siguiente unlock
  IF v_state.boost_active THEN
    RETURN QUERY SELECT
      v_state.total_taps,
      v_state.boost_active,
      v_state.boost_taps_left,
      FALSE,           -- ready_to_unlock
      FALSE,           -- rearm_needed
      v_state.total_taps + v_threshold;  -- next unlock cuando termine el boost
    RETURN;
  END IF;

  -- Sumar el toque normal
  v_state.total_taps := v_state.total_taps + 1;

  -- Verificar si ya cumplio el threshold de 200 y puede desbloquear
  IF v_state.total_taps >= v_threshold THEN
    -- Activar boost: 100 toques con 5x
    v_state.boost_active := TRUE;
    v_state.boost_taps_left := v_boost_duration;
    v_state.last_unlock_at := now();

    UPDATE boost_5x_state SET
      total_taps = v_state.total_taps,
      boost_active = TRUE,
      boost_taps_left = v_boost_duration,
      last_unlock_at = now(),
      updated_at = now()
    WHERE user_key = v_clean_key;

    RETURN QUERY SELECT
      v_state.total_taps,
      TRUE,
      v_boost_duration,
      FALSE,           -- listo_to_unlock (ya esta activo, no necesita hacer nada)
      FALSE,           -- rearm_needed
      v_state.total_taps;
    RETURN;
  END IF;

  -- No hay boost aun, pero el user esta acumulando
  UPDATE boost_5x_state SET
    total_taps = v_state.total_taps,
    updated_at = now()
  WHERE user_key = v_clean_key;

  -- ready_to_unlock: true cuando el user esta a 10 o menos del threshold
  RETURN QUERY SELECT
    v_state.total_taps,
    FALSE,
    0,
    (v_threshold - v_state.total_taps) <= 10,  -- ready_to_unlock: cerca del umbral
    FALSE,
    v_threshold;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.record_normal_tap TO anon, authenticated;

-- ─── RPC 2: consume_5x_tap ───
-- Consume 1 toque de 5x del usuario (solo si boost esta activo).
-- Suma 5 adhesiones a heart_global. Retorna adhesiones sumadas y taps restantes.
-- Si el boost se agota, lo desactiva y resetea el counter (comienza nuevo ciclo).
CREATE OR REPLACE FUNCTION public.consume_5x_tap(p_user_key TEXT)
RETURNS TABLE(
  success BOOLEAN,
  adhesiones_added INT,
  boost_taps_left INT,
  boost_active BOOLEAN,
  message TEXT
) AS $fn$
DECLARE
  v_state boost_5x_state%ROWTYPE;
  v_rearm CONSTANT BIGINT := 100;
  v_clean_key TEXT;
BEGIN
  v_clean_key := lower(trim(p_user_key));
  IF char_length(v_clean_key) < 2 OR char_length(v_clean_key) > 50 THEN
    RETURN QUERY SELECT FALSE, 0, 0, FALSE, 'user_key invalido';
    RETURN;
  END IF;

  SELECT * INTO v_state FROM boost_5x_state WHERE user_key = v_clean_key FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 0, 0, FALSE, 'Sin estado, registra un toque normal primero';
    RETURN;
  END IF;

  IF NOT v_state.boost_active THEN
    RETURN QUERY SELECT FALSE, 0, 0, FALSE, 'Boost 5x no esta activo. Necesitas 200 toques.';
    RETURN;
  END IF;

  IF v_state.boost_taps_left <= 0 THEN
    -- Esto no deberia pasar, pero por si acaso
    UPDATE boost_5x_state SET boost_active = FALSE, boost_taps_left = 0 WHERE user_key = v_clean_key;
    RETURN QUERY SELECT FALSE, 0, 0, FALSE, 'Boost agotado. Espera a recargar.';
    RETURN;
  END IF;

  -- Consumir 1 tap de boost y sumar 5 adhesiones al global
  v_state.boost_taps_left := v_state.boost_taps_left - 1;
  v_state.boost_taps_used := v_state.boost_taps_used + 1;

  -- Sumar 5 al global (atómico)
  UPDATE heart_global
    SET total_taps = LEAST(total_taps + 5, 1000000000),
        updated_at = now()
    WHERE id = 1;

  -- Si se agotaron los 5x taps, desactivar el boost
  IF v_state.boost_taps_left = 0 THEN
    v_state.boost_active := FALSE;
    -- reset: el user debe acumular v_rearm mas toques para reactivar
    -- NO reseteamos total_taps porque queremos que el siguiente unlock
    -- requiera 100 toques mas, no 200 desde 0
    UPDATE boost_5x_state SET
      boost_active = FALSE,
      boost_taps_left = 0,
      boost_taps_used = v_state.boost_taps_used,
      updated_at = now()
    WHERE user_key = v_clean_key;

    RETURN QUERY SELECT
      TRUE,
      5,
      0,
      FALSE,
      'Boost 5x agotado (100 toques usados). Acumula ' || v_rearm || ' toques mas para reactivar.';
    RETURN;
  END IF;

  -- Actualizar estado
  UPDATE boost_5x_state SET
    boost_taps_left = v_state.boost_taps_left,
    boost_taps_used = v_state.boost_taps_used,
    updated_at = now()
  WHERE user_key = v_clean_key;

  RETURN QUERY SELECT
    TRUE,
    5,
    v_state.boost_taps_left,
    TRUE,
    'Boost 5x activo. Te quedan ' || v_state.boost_taps_left || ' toques con 5x.';
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.consume_5x_tap TO anon, authenticated;

-- ─── RPC 3: get_boost_status ───
-- Devuelve el estado actual del boost del usuario (solo lectura).
CREATE OR REPLACE FUNCTION public.get_boost_status(p_user_key TEXT)
RETURNS TABLE(
  total_taps BIGINT,
  boost_active BOOLEAN,
  boost_taps_left INT,
  boost_taps_used INT,
  rearm_needed BOOLEAN,
  taps_until_unlock BIGINT
) AS $fn$
DECLARE
  v_state boost_5x_state%ROWTYPE;
  v_threshold CONSTANT BIGINT := 200;
  v_rearm CONSTANT BIGINT := 100;
  v_clean_key TEXT;
BEGIN
  v_clean_key := lower(trim(p_user_key));
  IF char_length(v_clean_key) < 2 OR char_length(v_clean_key) > 50 THEN
    RAISE EXCEPTION 'user_key invalido';
  END IF;

  SELECT * INTO v_state FROM boost_5x_state WHERE user_key = v_clean_key;
  IF NOT FOUND THEN
    -- Estado nuevo (aun no ha hecho ningun toque)
    RETURN QUERY SELECT 0::BIGINT, FALSE, 0, 0, FALSE, v_threshold;
    RETURN;
  END IF;

  -- Si el boost esta activo: el contador esta corriendo, no se necesita rearm
  -- Si NO esta activo y total_taps >= 200 (cumplio threshold pero lo agoto):
  --   necesita v_rearm toques mas (estado conocido como "rearm_needed")
  -- Si NO esta activo y total_taps < 200: esta acumulando, faltan (threshold - total_taps)
  IF v_state.boost_active THEN
    RETURN QUERY SELECT
      v_state.total_taps,
      TRUE,
      v_state.boost_taps_left,
      v_state.boost_taps_used,
      FALSE,
      0::BIGINT;
  ELSIF v_state.total_taps >= v_threshold THEN
    -- Ya uso un boost antes, esta en cooldown
    RETURN QUERY SELECT
      v_state.total_taps,
      FALSE,
      0,
      v_state.boost_taps_used,
      TRUE,
      v_rearm - ((v_state.total_taps - v_threshold) % v_rearm);
  ELSE
    -- Aun no llega al primer unlock
    RETURN QUERY SELECT
      v_state.total_taps,
      FALSE,
      0,
      v_state.boost_taps_used,
      FALSE,
      v_threshold - v_state.total_taps;
  END IF;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
GRANT EXECUTE ON FUNCTION public.get_boost_status TO anon, authenticated;

-- ─── Verificacion ───
-- SELECT proname FROM pg_proc WHERE proname IN
--   ('record_normal_tap', 'consume_5x_tap', 'get_boost_status');
-- Esperado: 3 funciones listadas

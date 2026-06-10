-- RESET COMPLETO: borra todos los datos de campaña
-- Ejecutar en Supabase SQL Editor (https://ntetozxmzpupwpjpfjrr.supabase.co)

TRUNCATE TABLE municipality_scores RESTART IDENTITY CASCADE;
TRUNCATE TABLE supporters RESTART IDENTITY CASCADE;
TRUNCATE TABLE top_tappers RESTART IDENTITY CASCADE;
TRUNCATE TABLE hashtags RESTART IDENTITY CASCADE;
TRUNCATE TABLE referrals RESTART IDENTITY CASCADE;

-- Reiniciar contador global de corazones a 0
UPDATE heart_global SET total_taps = 0 WHERE id = 1;

-- Verificar
SELECT 'municipality_scores' as tabla, count(*) FROM municipality_scores
UNION ALL
SELECT 'supporters', count(*) FROM supporters
UNION ALL
SELECT 'top_tappers', count(*) FROM top_tappers
UNION ALL
SELECT 'hashtags', count(*) FROM hashtags
UNION ALL
SELECT 'referrals', count(*) FROM referrals
UNION ALL
SELECT 'heart_global', total_taps FROM heart_global WHERE id = 1;

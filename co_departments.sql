-- ============================================
-- DANE Divipola: Tablas + 33 departamentos
-- ============================================
CREATE TABLE IF NOT EXISTS co_departments (
  code     SMALLINT PRIMARY KEY,
  name     TEXT NOT NULL UNIQUE,
  iso_code CHAR(3)
);
CREATE TABLE IF NOT EXISTS co_municipalities (
  code          SMALLINT PRIMARY KEY,
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

-- 33 departamentos de Colombia (DIVIPOLA DANE)
INSERT INTO co_departments (code, name, iso_code) VALUES
  (5,  'Antioquia', 'ANT'),
  (8,  'Atlantico', 'ATL'),
  (11, 'Bogota, D.C.', 'DC'),
  (13, 'Bolivar', 'BOL'),
  (15, 'Boyaca', 'BOY'),
  (17, 'Caldas', 'CAL'),
  (18, 'Caqueta', 'CAQ'),
  (19, 'Cauca', 'CAU'),
  (20, 'Cesar', 'CES'),
  (23, 'Cordoba', 'COR'),
  (25, 'Cundinamarca', 'CUN'),
  (27, 'Choco', 'CHO'),
  (41, 'Huila', 'HUI'),
  (44, 'La Guajira', 'LAG'),
  (47, 'Magdalena', 'MAG'),
  (50, 'Meta', 'MET'),
  (52, 'Narino', 'NAR'),
  (54, 'Norte de Santander', 'NSA'),
  (63, 'Quindio', 'QUI'),
  (66, 'Risaralda', 'RIS'),
  (68, 'Santander', 'SAN'),
  (70, 'Sucre', 'SUC'),
  (73, 'Tolima', 'TOL'),
  (76, 'Valle del Cauca', 'VAC'),
  (81, 'Arauca', 'ARA'),
  (85, 'Casanare', 'CAS'),
  (86, 'Putumayo', 'PUT'),
  (88, 'San Andres y Providencia', 'SAP'),
  (91, 'Amazonas', 'AMA'),
  (94, 'Guainia', 'GUA'),
  (95, 'Guaviare', 'GUV'),
  (97, 'Vaupes', 'VAU'),
  (99, 'Vichada', 'VID')
ON CONFLICT (code) DO NOTHING;

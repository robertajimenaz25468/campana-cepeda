# Movimiento Ciudadano por el Dialogo Nacional 2026

Espacio de participacion ciudadana independiente. Nacido de la sociedad civil.
No afiliado, financiado ni coordinado por ninguna campana politica oficial,
partido o movimiento.

Ejercicio del derecho fundamental a la participacion politica
(Art. 40, Constitucion Politica de Colombia).

Costo operativo: $0 COP. Mantenido con herramientas gratuitas y trabajo voluntario.

## Stack

- **Frontend**: HTML + Tailwind CSS (CDN) + FontAwesome, sin build step
- **Backend**: Supabase (Postgres + Realtime Broadcast)
- **Animaciones**: CSS + Web Animations API (sin frameworks)
- **Persistencia**: localStorage con esquema versionado

## Características principales

### Volcán de Proclamas
Sistema de animación donde los tags de los usuarios erupcionan desde una boca dorada en la parte superior, ascienden, se balancean, y estallan en chispas tricolor antes de desvanecerse.

- 4 carriles flotantes con deteccion de colisiones (sin solapamientos)
- Erupciones en lotes de 3 con stagger de 90ms
- Duracion 7-9s por tag con fase de hold para legibilidad
- Sincronizacion en tiempo real via Supabase Broadcast (canal proclamas-volcano)
- Fondo oscuro premium con estela de luz patriota + 14 estrellas titilantes

### Persistencia local robusta
- Schema versionado (cp_v) para migraciones futuras
- Manejo de QuotaExceededError con purga automatica del muro
- Cache en memoria como fallback (modo incognito / sandbox)
- Chip visual "Reconocido como [Nombre]" en el panel del sello

### Paneles con tabs sticky
- 3 tabs: Muro de Compromiso / Lideres de la Causa / Top 30 Sellos
- Sticky positioning con fondo 100% opaco y z-index 30
- Solo cambia el color del tab activo (oro vs gris)

### Seguridad
- Validacion OWASP-aligned (homoglifos, Zalgo, inyeccion, scripts mixtos)
- Honeypot anti-bot
- DOMPurify para cualquier HTML de usuario

## Estructura

`
campana-cepeda/
├── index.html                          # Aplicacion completa (single-file)
├── gaitan.b64.js                       # Audio base64 de la Voz de Gaitan
├── supabase-schema.sql                 # Schema inicial (5 tablas + RLS)
├── supabase-migration-realtime-referrals.sql  # Realtime + top tappers + referrals
└── .gitignore
`

## Setup

1. Aplicar schema a Supabase (SQL Editor, en orden):
   - supabase-schema.sql
   - supabase-migration-realtime-referrals.sql

2. Configurar credenciales en index.html linea ~1035:
   `js
   DB=sc.createClient('https://TU_PROYECTO.supabase.co','TU_ANON_KEY');
   `

3. Servir localmente:
   `ash
   npx http-server -p 8765
   # Abre: http://localhost:8765/index.html
   `

## Licencia

Privado - uso interno de la campana.

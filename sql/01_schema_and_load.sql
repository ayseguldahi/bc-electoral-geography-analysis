-- ============================================================
-- BC Electoral Geography Analysis
-- 01: Schema & Data Load (PostgreSQL + PostGIS)
-- Data: Elections BC open data via BC Geographic Data Warehouse
--   * Electoral district boundaries: current (2023 redistribution,
--     93 districts) and previous (2015 redistribution, 87 districts)
--   * Voting places 2020 (points, with official district assignment)
--   * Provincial voting results by voting place (CSV)
-- Licence: Elections BC Open Data Licence
-- ============================================================

CREATE EXTENSION IF NOT EXISTS postgis;

-- ------------------------------------------------------------
-- Spatial layers are loaded with ogr2ogr (GDAL). Run from shell:
--
-- ogr2ogr -f PostgreSQL PG:"dbname=bc_electoral" \
--   data/EBC_PROV_ELECTORAL_DIST_SVW.geojson \
--   -nln electoral_districts_2024 -nlt PROMOTE_TO_MULTI -t_srs EPSG:3005
--
-- ogr2ogr -f PostgreSQL PG:"dbname=bc_electoral" \
--   data/EBC_ELECTORAL_DISTS_BS10_SVW.geojson \
--   -nln electoral_districts_2017 -nlt PROMOTE_TO_MULTI -t_srs EPSG:3005
--
-- ogr2ogr -f PostgreSQL PG:"dbname=bc_electoral" \
--   data/EBC_VOTING_PLACES_SP.geojson \
--   -nln voting_places -t_srs EPSG:3005
--
-- Notes:
--   * EPSG:3005 (BC Albers) is an equal-area projection: correct
--     choice for area calculations in the redistribution analysis.
--   * PROMOTE_TO_MULTI avoids mixed POLYGON/MULTIPOLYGON errors.
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Election results (tabular)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS voting_results_raw;

CREATE TABLE voting_results_raw (
    id                    VARCHAR(20),
    event_name            VARCHAR(60),
    event_year            SMALLINT,
    ed_abbreviation       VARCHAR(5),
    ed_name               VARCHAR(50),
    va_code               VARCHAR(10),
    edva_code             VARCHAR(10),
    voting_location       VARCHAR(120),
    address_standard_id   VARCHAR(20),
    voting_opportunity    VARCHAR(40),   -- Advance / General / Mail etc.
    candidate             VARCHAR(80),
    elected               CHAR(1),
    affiliation           VARCHAR(60),
    votes_considered      INTEGER,
    vote_category         VARCHAR(20),   -- Valid / Rejected
    combined_indicator    CHAR(1),
    results_reported_under VARCHAR(20)
);

-- \copy voting_results_raw FROM 'provincial_voting_results_by_voting_place.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- ------------------------------------------------------------
-- Spatial indexes (created automatically by ogr2ogr, but ensure)
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_ed2024_geom ON electoral_districts_2024 USING GIST (wkb_geometry);
CREATE INDEX IF NOT EXISTS idx_ed2017_geom ON electoral_districts_2017 USING GIST (wkb_geometry);
CREATE INDEX IF NOT EXISTS idx_vp_geom     ON voting_places           USING GIST (wkb_geometry);
CREATE INDEX idx_results_event ON voting_results_raw (event_year, ed_name);

-- ------------------------------------------------------------
-- Sanity checks
-- ------------------------------------------------------------
-- Expect 93 / 87 / 4354 rows respectively:
-- SELECT (SELECT COUNT(*) FROM electoral_districts_2024) AS districts_2024,
--        (SELECT COUNT(*) FROM electoral_districts_2017) AS districts_2017,
--        (SELECT COUNT(*) FROM voting_places)            AS voting_places;

-- Expect 2024 Provincial General Election with ~9.5K rows and 4 by-elections:
-- SELECT event_year, event_name, COUNT(*) FROM voting_results_raw GROUP BY 1, 2 ORDER BY 1;

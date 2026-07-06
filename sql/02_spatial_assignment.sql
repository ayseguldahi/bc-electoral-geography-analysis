-- ============================================================
-- BC Electoral Geography Analysis
-- 02: Spatial Assignment & Validation
-- Business question: can point locations be reliably assigned to
-- electoral districts with a spatial join — and where does pure
-- point-in-polygon assignment disagree with official assignments?
-- (This mirrors the core VDG function of assigning voters to
--  districts based on residential address location.)
-- ============================================================

-- ------------------------------------------------------------
-- Q1. Assign every voting place to a district by location
--     (point-in-polygon against BOTH boundary sets)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS voting_place_assignment;

CREATE TABLE voting_place_assignment AS
SELECT
    vp.voting_place_id,
    vp.street_address,
    vp.locality,
    vp.ed_name                    AS official_ed_2017,   -- official assignment (2015 redistribution names)
    e17.ed_name                   AS spatial_ed_2017,    -- our point-in-polygon result, old boundaries
    e24.ed_name                   AS spatial_ed_2024,    -- our point-in-polygon result, new boundaries
    vp.wkb_geometry
FROM voting_places vp
LEFT JOIN electoral_districts_2017 e17
       ON ST_Contains(e17.wkb_geometry, vp.wkb_geometry)
LEFT JOIN electoral_districts_2024 e24
       ON ST_Contains(e24.wkb_geometry, vp.wkb_geometry);

-- ------------------------------------------------------------
-- Q2. Validation: how often does the spatial assignment match
--     the official assignment?
--     Finding: ~84.5% — and the mismatches are NOT errors.
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                                          AS total_places,
    SUM(CASE WHEN spatial_ed_2017 IS NOT NULL THEN 1 ELSE 0 END)      AS assigned,
    SUM(CASE WHEN UPPER(TRIM(spatial_ed_2017)) = UPPER(TRIM(official_ed_2017))
             THEN 1 ELSE 0 END)                                       AS match_official,
    ROUND(100.0 * SUM(CASE WHEN UPPER(TRIM(spatial_ed_2017)) = UPPER(TRIM(official_ed_2017))
                           THEN 1 ELSE 0 END) / COUNT(*), 1)          AS pct_match
FROM voting_place_assignment;

-- ------------------------------------------------------------
-- Q3. The interesting 15%: voting places that PHYSICALLY sit in
--     a different district than the one they serve.
--     Real-world reason: a facility just across the boundary
--     (school, hall) can serve the neighbouring district. This is
--     why Elections BC warns that spatial data must not be used
--     to determine a voter's district — assignment must come from
--     authoritative address reference data.
-- ------------------------------------------------------------
SELECT
    official_ed_2017               AS serves_district,
    spatial_ed_2017                AS located_in_district,
    COUNT(*)                       AS facilities,
    -- how far inside the "wrong" district are they? (metres)
    ROUND(AVG(ST_Distance(
        wkb_geometry,
        (SELECT ST_Boundary(e.wkb_geometry)
         FROM electoral_districts_2017 e
         WHERE UPPER(TRIM(e.ed_name)) = UPPER(TRIM(official_ed_2017)))
    ))::numeric, 0)                AS avg_distance_to_own_district_m
FROM voting_place_assignment
WHERE spatial_ed_2017 IS NOT NULL
  AND UPPER(TRIM(spatial_ed_2017)) <> UPPER(TRIM(official_ed_2017))
GROUP BY official_ed_2017, spatial_ed_2017
ORDER BY facilities DESC
LIMIT 15;

-- ------------------------------------------------------------
-- Q4. Redistribution impact on service locations: how many
--     voting places fall in a 2024 district whose name differs
--     from their 2017 district? (continuity of service planning)
-- ------------------------------------------------------------
SELECT
    CASE WHEN UPPER(TRIM(spatial_ed_2017)) = UPPER(TRIM(spatial_ed_2024))
         THEN 'Same district name'
         ELSE 'District changed in redistribution' END AS status,
    COUNT(*)                                           AS voting_places,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM voting_place_assignment
WHERE spatial_ed_2017 IS NOT NULL AND spatial_ed_2024 IS NOT NULL
GROUP BY 1;

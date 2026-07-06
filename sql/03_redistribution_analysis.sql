-- ============================================================
-- BC Electoral Geography Analysis
-- 03: Redistribution Analysis — 87 districts (2015) -> 93 (2023)
-- Business question: how much of the electoral map actually
-- changed, which districts were split or merged, and where should
-- voter-communication effort concentrate?
-- All area math in EPSG:3005 (BC Albers, equal-area).
-- ============================================================

-- ------------------------------------------------------------
-- Q1. Overlap matrix: every (old district x new district) pair
--     with the share of the old district's area it represents
-- ------------------------------------------------------------
DROP TABLE IF EXISTS redistribution_overlap;

CREATE TABLE redistribution_overlap AS
WITH pairs AS (
    SELECT
        o.ed_name                                        AS old_ed,
        n.ed_name                                        AS new_ed,
        ST_Area(ST_Intersection(o.wkb_geometry, n.wkb_geometry)) AS overlap_area_m2,
        ST_Area(o.wkb_geometry)                          AS old_area_m2
    FROM electoral_districts_2017 o
    JOIN electoral_districts_2024 n
      ON ST_Intersects(o.wkb_geometry, n.wkb_geometry)
)
SELECT
    old_ed,
    new_ed,
    overlap_area_m2,
    ROUND((100.0 * overlap_area_m2 / old_area_m2)::numeric, 2) AS pct_of_old_district
FROM pairs
WHERE 100.0 * overlap_area_m2 / old_area_m2 >= 1.0;  -- ignore sliver overlaps < 1%

-- ------------------------------------------------------------
-- Q2. The fate of the 87 old districts
--     Finding: only 30 stayed intact; 36 split in two; 21 split
--     into three or more pieces.
-- ------------------------------------------------------------
WITH splits AS (
    SELECT old_ed, COUNT(*) AS n_pieces
    FROM redistribution_overlap
    GROUP BY old_ed
)
SELECT
    CASE WHEN n_pieces = 1 THEN '1 - intact (single successor)'
         WHEN n_pieces = 2 THEN '2 - split in two'
         ELSE '3+ - heavily fragmented' END AS outcome,
    COUNT(*)                                AS old_districts
FROM splits
GROUP BY 1
ORDER BY 1;

-- Most fragmented old districts (candidates for the most voter confusion)
SELECT old_ed, COUNT(*) AS successor_districts,
       STRING_AGG(new_ed || ' (' || pct_of_old_district || '%)', ', '
                  ORDER BY pct_of_old_district DESC) AS where_it_went
FROM redistribution_overlap
GROUP BY old_ed
ORDER BY successor_districts DESC, old_ed
LIMIT 10;

-- ------------------------------------------------------------
-- Q3. The origin of the 93 new districts
--     Finding: 55 of 93 new districts merge territory from
--     multiple old districts — most of the new map is recombined,
--     not just renamed.
-- ------------------------------------------------------------
WITH origins AS (
    SELECT new_ed, COUNT(*) AS n_sources
    FROM redistribution_overlap
    GROUP BY new_ed
)
SELECT
    CASE WHEN n_sources = 1 THEN 'Formed from a single old district'
         ELSE 'Merged from multiple old districts' END AS origin,
    COUNT(*)                                           AS new_districts
FROM origins
GROUP BY 1;

-- ------------------------------------------------------------
-- Q4. Where is voter-communication risk highest? Rank new
--     districts by how "mixed" their origins are (an entropy-like
--     measure: 1 - max share inherited from any single old district)
-- ------------------------------------------------------------
WITH new_shares AS (
    SELECT
        new_ed,
        overlap_area_m2 / SUM(overlap_area_m2) OVER (PARTITION BY new_ed) AS share
    FROM redistribution_overlap
)
SELECT
    new_ed,
    COUNT(*)                                      AS source_districts,
    ROUND((100 * (1 - MAX(share)))::numeric, 1)   AS mixed_origin_score  -- 0 = pure, higher = more recombined
FROM new_shares
GROUP BY new_ed
ORDER BY mixed_origin_score DESC
LIMIT 10;

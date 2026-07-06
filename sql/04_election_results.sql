-- ============================================================
-- BC Electoral Geography Analysis
-- 04: 2024 Provincial General Election Results
-- Business questions: where were the closest races, how do votes
-- split across voting opportunities, and what would service
-- planning prioritize for the next event?
-- ============================================================

-- ------------------------------------------------------------
-- Q1. Candidate totals and winners by district (window functions)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS results_2024_by_candidate;

CREATE TABLE results_2024_by_candidate AS
SELECT
    ed_name,
    candidate,
    affiliation,
    SUM(votes_considered)                            AS votes,
    RANK() OVER (PARTITION BY ed_name
                 ORDER BY SUM(votes_considered) DESC) AS place_in_district
FROM voting_results_raw
WHERE event_name = '2024 Provincial General Election'
  AND vote_category = 'Valid'
  AND candidate IS NOT NULL
GROUP BY ed_name, candidate, affiliation;

-- ------------------------------------------------------------
-- Q2. Closest races: margin between 1st and 2nd
--     Finding: Surrey-Guildford was decided by 22 votes (0.12%).
-- ------------------------------------------------------------
WITH ranked AS (
    SELECT ed_name, affiliation, votes, place_in_district,
           SUM(votes) OVER (PARTITION BY ed_name)        AS district_total,
           LEAD(votes) OVER (PARTITION BY ed_name
                             ORDER BY place_in_district) AS runner_up_votes
    FROM results_2024_by_candidate
)
SELECT
    ed_name,
    affiliation                                       AS winning_party,
    votes                                             AS winner_votes,
    votes - runner_up_votes                           AS margin,
    ROUND(100.0 * (votes - runner_up_votes) / district_total, 2) AS margin_pct
FROM ranked
WHERE place_in_district = 1
ORDER BY margin
LIMIT 10;

-- ------------------------------------------------------------
-- Q3. Province-wide seats and vote share by party
-- ------------------------------------------------------------
SELECT
    affiliation,
    SUM(CASE WHEN place_in_district = 1 THEN 1 ELSE 0 END) AS seats,
    SUM(votes)                                             AS total_votes,
    ROUND(100.0 * SUM(votes) / SUM(SUM(votes)) OVER (), 1) AS vote_share_pct
FROM results_2024_by_candidate
GROUP BY affiliation
HAVING SUM(votes) > 10000
ORDER BY seats DESC, total_votes DESC;

-- ------------------------------------------------------------
-- Q4. Voting opportunity mix by district: where is advance /
--     mail voting heaviest? (input for service capacity planning)
-- ------------------------------------------------------------
SELECT
    ed_name,
    SUM(votes_considered)                                        AS valid_votes,
    ROUND(100.0 * SUM(CASE WHEN voting_opportunity ILIKE '%advance%'
                           THEN votes_considered ELSE 0 END)
               / SUM(votes_considered), 1)                       AS pct_advance,
    ROUND(100.0 * SUM(CASE WHEN voting_opportunity ILIKE '%mail%'
                           THEN votes_considered ELSE 0 END)
               / SUM(votes_considered), 1)                       AS pct_mail
FROM voting_results_raw
WHERE event_name = '2024 Provincial General Election'
  AND vote_category = 'Valid'
GROUP BY ed_name
ORDER BY pct_advance DESC
LIMIT 15;

-- ------------------------------------------------------------
-- Q5. Join results to geography: closest races on the new map
--     (feeds the margin choropleth in images/)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_district_margins AS
WITH ranked AS (
    SELECT ed_name, affiliation, votes,
           place_in_district,
           SUM(votes) OVER (PARTITION BY ed_name)        AS district_total,
           LEAD(votes) OVER (PARTITION BY ed_name
                             ORDER BY place_in_district) AS runner_up_votes
    FROM results_2024_by_candidate
)
SELECT
    e.ed_name,
    r.affiliation                                            AS winning_party,
    ROUND(100.0 * (r.votes - r.runner_up_votes) / r.district_total, 2) AS margin_pct,
    e.wkb_geometry
FROM electoral_districts_2024 e
JOIN ranked r
  ON UPPER(TRIM(r.ed_name)) = UPPER(TRIM(e.ed_name))
WHERE r.place_in_district = 1;

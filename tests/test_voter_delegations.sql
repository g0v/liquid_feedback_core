-- run with test.sh

-- NOTE: This file requires that sequence generators have not been used.
-- (All new rows need to start with id '1'.)

BEGIN;

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

INSERT INTO "member"
("activated", "last_activity", "active", "login", "name") VALUES
('now', 'now', TRUE, 'user1',  'User #1'), -- id  1
('now', 'now', TRUE, 'user2',  'User #2'), -- id  2
('now', 'now', TRUE, 'user3',  'User #3'), -- id  3
('now', 'now', TRUE, 'user4',  'User #4'); -- id  4

-- set password to "login"
UPDATE "member" SET "password" = '$1$PcI6b1Bg$2SHjAZH2nMLFp0fxHis.Q0';

INSERT INTO "policy" (
    "index",
    "name",
    "admission_time",
    "discussion_time",
    "verification_time",
    "voting_time",
    "issue_quorum_num", "issue_quorum_den",
    "initiative_quorum_num", "initiative_quorum_den",
    "direct_majority_num", "direct_majority_den", "direct_majority_strict",
    "no_reverse_beat_path", "no_multistage_majority"
  ) VALUES (
    1,
    'Default policy',
    '1 hour', '1 hour', '1 hour', '1 hour',
    25, 100,
    20, 100,
    1, 2, TRUE,
    TRUE, FALSE
  );

CREATE FUNCTION "time_warp"() RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      UPDATE "issue" SET
        "snapshot"     = "snapshot"     - '1 hour 1 minute'::INTERVAL,
        "created"      = "created"      - '1 hour 1 minute'::INTERVAL,
        "accepted"     = "accepted"     - '1 hour 1 minute'::INTERVAL,
        "half_frozen"  = "half_frozen"  - '1 hour 1 minute'::INTERVAL,
        "fully_frozen" = "fully_frozen" - '1 hour 1 minute'::INTERVAL
      WHERE "closed" ISNULL;
      PERFORM "check_everything"();
      RETURN;
    END;
  $$;

INSERT INTO "unit" ("name") VALUES
('Main');

INSERT INTO "privilege" ("unit_id", "member_id", "voting_right")
  SELECT 1 AS "unit_id", "id" AS "member_id", TRUE AS "voting_right"
  FROM "member";

INSERT INTO "area" ("unit_id", "name") VALUES
(1, 'Area #1');

INSERT INTO "allowed_policy" ("area_id", "policy_id", "default_policy") VALUES
(1, 1, TRUE);

INSERT INTO "membership" ("area_id", "member_id") VALUES
(1, 2),
(1, 3);
-- user1 is only interested via delegation to user3;

INSERT INTO "delegation" ("truster_id", "trustee_id", "scope", "unit_id", "area_id", "issue_id") VALUES
( 1, 2, 'unit',    1, NULL, NULL), -- user1: unit delegation -> user2
( 1, 3, 'area', NULL,    1, NULL); -- user1: area delegation -> user3

INSERT INTO "issue" ("area_id", "policy_id") VALUES
(1, 1);

INSERT INTO "initiative" ("issue_id", "name") VALUES
(1, 'Initiative #1');

INSERT INTO "draft" ("initiative_id", "author_id", "name", "content") VALUES
(1, 4, 'Name', 'Lorem ipsum...'); -- user4

INSERT INTO "initiator" ("initiative_id", "member_id") VALUES
(1, 4); -- user4

INSERT INTO "supporter" ("member_id", "initiative_id", "draft_id") VALUES
( 2,  1,  1), -- user2
( 3,  1,  1); -- user3
-- user1 supports only via delegation to user3;

SELECT "time_warp"();
SELECT "time_warp"();
SELECT "time_warp"();

INSERT INTO "direct_voter" ("member_id", "issue_id") VALUES
( 2, 1),
( 3, 1);

INSERT INTO "vote" ("member_id", "issue_id", "initiative_id", "grade") VALUES
( 2, 1, 1,  1), -- user2 votes pro
( 3, 1, 1, -1); -- user3 votes contra

SELECT "time_warp"();

-- check result

SELECT * FROM delegating_voter;
SELECT * FROM delegating_population_snapshot;
SELECT * FROM delegating_interest_snapshot;

/* expected output:

 issue_id | member_id | scope | delegate_member_id
 ----------+-----------+-------+--------------------
         1 |         1 | area  |                  3

  issue_id |      event       | member_id | scope | delegate_member_id
 ----------+------------------+-----------+-------+--------------------
         1 | end_of_admission |         1 | area  |                  3
         1 | half_freeze      |         1 | area  |                  3
         1 | full_freeze      |         1 | area  |                  3

  issue_id |      event       | member_id | scope | delegate_member_id
 ----------+------------------+-----------+-------+--------------------
         1 | end_of_admission |         1 | area  |                  3
         1 | half_freeze      |         1 | area  |                  3
         1 | full_freeze      |         1 | area  |                  3

*/

END;

-- run with test.sh

-- NOTE: This file requires that sequence generators have not been used.
-- (All new rows need to start with id '1'.)

BEGIN;

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

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

CREATE FUNCTION "create_issues"() RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE AS $$
  DECLARE
    i "policy"."id"%TYPE;
    member_name "member"."name"%TYPE;
  BEGIN

    -- test policies that help with testing specific frontend parts
    INSERT INTO "policy" (
        "index",
        "name",
        "admission_time",
        "discussion_time",
        "verification_time",
        "voting_time",
        "issue_quorum_num", "issue_quorum_den",
        "initiative_quorum_num", "initiative_quorum_den"
      ) VALUES (
        1,
        'Test New',
        '1 day',
        '1 hour',
        '1 hour',
        '1 hour',
        100, 100,
        100, 100
      ), (
        2,
        'Test Accepted',
        '1 hour',
        '1 day',
        '1 hour',
        '1 hour',
        0, 100,
        0, 100
      ), (
        3,
        'Test Not Accepted (Issue Quorum failed)',
        '1 hour',
        '1 day',
        '1 hour',
        '1 hour',
        100, 100,
        100, 100
      ), (
        4,
        'Test Frozen',
        '1 hour',
        '1 hour',
        '1 day',
        '1 hour',
        0, 100,
        0, 100
      ), (
        5,
        'Test Voting',
        '1 hour',
        '1 hour',
        '1 hour',
        '1 day',
        0, 100,
        0, 100
      ), (
        6,
        'Test Not Admitted (Initiative Quorum failed)',
        '1 hour',
        '1 hour',
        '1 hour',
        '1 day',
        0, 100,
        100, 100
      ), (
        7,
        'Test Closed', -- with votes
        '1 hour',
        '1 hour',
        '1 hour',
        '1 hour',
        0, 100,
        0, 100
      );

    INSERT INTO "unit" ("name") VALUES
    ('Main'),
    ('Other');

    INSERT INTO "area" ("unit_id", "name") VALUES
    (1, 'Area #1');

    INSERT INTO "allowed_policy" ("area_id", "policy_id", "default_policy") VALUES
    (1, 1, TRUE);

    /* users:

    == A delegates not
    0    - noone participates
    1    - A(1) participates
    == A delegates to B
    2->3 - noone participates
    4->5 - A(4) participates
    6->7 - B(7) participates

    additional not participating delegates in prefence list: 8, X, 9

    1x  supporter (+interest) + membership
    2x  interest + membership
    3x  membership
    4x  supporter (+interest)
    5x  interest

    */

    -- create users
    FOR i IN 1..59 LOOP
      member_name := 'User #' || i;

      IF i = 8 THEN
        member_name := member_name || ' no voting right';
      END IF;
      IF i = 9 THEN
        member_name := member_name || ' voting right only in Other';
      END IF;
      IF i >= 10 THEN

        -- participates
        IF i % 10 = 1 OR i % 10 = 4 OR i % 10 = 7 THEN
          member_name := member_name || ' participates';
        END IF;
        -- delegates
        IF i % 10 = 2 OR i % 10 = 4 OR i % 10 = 6 THEN
          member_name := member_name || ' delegates';
        END IF;
        -- trustee
        IF i % 10 = 3 OR i % 10 = 5 OR i % 10 = 7 OR i % 10 = 8 OR i % 10 = 9 THEN
          member_name := member_name || ' trustee';
        END IF;

        -- supporter
        IF i <= 19 OR (i >= 40 AND i <= 49) THEN
          member_name := member_name || ' supporter';
        END IF;
        -- interest
        IF (i >= 20 AND i <= 29) OR (i >= 50 AND i <= 59) THEN
          member_name := member_name || ' interested';
        END IF;
        -- area member
        IF i <= 30 THEN
          member_name := member_name || ' area';
        END IF;

      END IF;
      INSERT INTO "member"
      ("activated", "last_activity", "active", "login", "name") VALUES
      ('now', 'now', TRUE, 'user' || i, member_name );
    END LOOP;

    -- set password to "login"
    UPDATE "member" SET "password" = '$1$PcI6b1Bg$2SHjAZH2nMLFp0fxHis.Q0';

    -- voting right for all members
    INSERT INTO "privilege" ("unit_id", "member_id", "voting_right")
      SELECT 1 AS "unit_id", "id" AS "member_id", TRUE AS "voting_right"
      FROM "member"
      WHERE "id" != 9
      AND "id" != 8; -- user 8 has no voting rights at all
    -- user 9 can be used to have a look as a member without voting rights in the main unit
    INSERT INTO "privilege" ("unit_id", "member_id", "voting_right") VALUES
    (2, 9, TRUE);

    FOR i IN 10..50 BY 10 LOOP
      INSERT INTO "delegation" ("truster_id", "trustee_id", "scope", "unit_id", "area_id", "issue_id", "preference") VALUES
      ( 2+i, 8+i, 'unit', 1, NULL, NULL, 1),
      ( 2+i, 3+i, 'unit', 1, NULL, NULL, 2),
      ( 2+i, 9+i, 'unit', 1, NULL, NULL, 3),
      ( 4+i, 8+i, 'unit', 1, NULL, NULL, 1),
      ( 4+i, 5+i, 'unit', 1, NULL, NULL, 2),
      ( 4+i, 9+i, 'unit', 1, NULL, NULL, 3),
      ( 6+i, 8+i, 'unit', 1, NULL, NULL, 1),
      ( 6+i, 7+i, 'unit', 1, NULL, NULL, 2),
      ( 6+i, 9+i, 'unit', 1, NULL, NULL, 3),
      ( 2+i, 8+i, 'area', NULL, 1, NULL, 1),
      ( 2+i, 3+i, 'area', NULL, 1, NULL, 2),
      ( 2+i, 9+i, 'area', NULL, 1, NULL, 3),
      ( 4+i, 8+i, 'area', NULL, 1, NULL, 1),
      ( 4+i, 5+i, 'area', NULL, 1, NULL, 2),
      ( 4+i, 9+i, 'area', NULL, 1, NULL, 3),
      ( 6+i, 8+i, 'area', NULL, 1, NULL, 1),
      ( 6+i, 7+i, 'area', NULL, 1, NULL, 2),
      ( 6+i, 9+i, 'area', NULL, 1, NULL, 3);
    END LOOP;

    FOR i IN 10..39 LOOP
      INSERT INTO "membership" ("area_id", "member_id") VALUES (1, i);
    END LOOP;

    FOR i IN
      SELECT "id" FROM "policy" ORDER BY "id"
    LOOP

      INSERT INTO "issue" ("area_id", "policy_id") VALUES
      (1, i);

      INSERT INTO "initiative" ("issue_id", "name") VALUES
      (i, 'Initiative #' || i );

      INSERT INTO "draft" ("initiative_id", "author_id", "name", "content") VALUES
      (i, 4, 'Name', 'Lorem ipsum...'); -- user4

      INSERT INTO "initiator" ("initiative_id", "member_id") VALUES
      (i, 4); -- user4

      INSERT INTO "supporter" ("member_id", "initiative_id", "draft_id") VALUES
      (11, i, i),
      (14, i, i),
      (17, i, i),
      (41, i, i),
      (44, i, i),
      (47, i, i);

      INSERT INTO "interest" ("member_id", "issue_id") VALUES
      (21, i),
      (24, i),
      (27, i),
      (51, i),
      (54, i),
      (57, i);

    END LOOP;

    RETURN;
  END;
$$;

SELECT create_issues();

SELECT "time_warp"();
SELECT "time_warp"();
SELECT "time_warp"();

-- vote

-- override protection triggers:
INSERT INTO "temporary_transaction_data" ("key", "value")
  VALUES ('override_protection_triggers', TRUE::TEXT);

INSERT INTO "direct_voter" ("member_id", "issue_id") VALUES
(11, 7),
(14, 7),
(17, 7),
(41, 7),
(44, 7),
(47, 7);
INSERT INTO "vote" ("member_id", "issue_id", "initiative_id", "grade") VALUES
(11, 7, 7,  1), -- pro
(14, 7, 7, -1), -- contra
(17, 7, 7,  1), -- pro
(41, 7, 7,  1), -- pro
(44, 7, 7, -1), -- contra
(47, 7, 7,  1); -- pro

-- finish overriding protection triggers (avoids garbage):
DELETE FROM "temporary_transaction_data"
  WHERE "key" = 'override_protection_triggers';

SELECT "time_warp"();

END;

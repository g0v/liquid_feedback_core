-- run with test.sh

-- Afterwards you have to call lf_update_and_notification.sh to actually send the mails.

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


CREATE FUNCTION "create_users"() RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE AS $$
  DECLARE
    i INT;
    j INT;
    event VARCHAR;
    interest "notify_interest"%TYPE;
    events VARCHAR[] := ARRAY[
      'initiative_created_in_new_issue',                 -- 1x
      'admission__initiative_created_in_existing_issue', -- 2x
      'admission__new_draft_created',                    -- ...
      'admission__suggestion_created',
      'admission__initiative_revoked',
      'canceled_revoked_before_accepted',
      'canceled_issue_not_accepted',
      'discussion',
      'discussion__initiative_created_in_existing_issue',
      'discussion__new_draft_created',
      'discussion__suggestion_created',
      'discussion__initiative_revoked',
      'canceled_after_revocation_during_discussion',
      'verification',
      'verification__initiative_created_in_existing_issue',
      'verification__initiative_revoked',
      'canceled_after_revocation_during_verification',
      'canceled_no_initiative_admitted',
      'voting',
      'finished_with_winner',
      'finished_without_winner'
    ];
    interests VARCHAR[] := ARRAY[
      'all',         -- 0
      'my_units',    -- 1
      'my_areas',    -- 2
      'interested',  -- 3
      'potentially', -- 4
      'supported',   -- 5
      'initiated',   -- 6
      'voted'        -- 7
    ];
  BEGIN

    i := 1;
    FOREACH event IN ARRAY events LOOP

      j := 0;
      FOREACH interest IN ARRAY interests LOOP

        INSERT INTO "member"
        ("id", "activated", "last_activity", "active", "login", "name", "notify_email", "notify_level") VALUES (
          i * 10 + j,
          'now', 'now', TRUE,
          'user'   || i * 10 + j,
          'User #' || i * 10 + j || ' ' || interest || ' ' || event,
          'user'   || i * 10 + j || '.' || interest || '.' || event || '@example.com',
          'expert'
        );

        -- activate notifications
        IF j = 3 THEN
        EXECUTE 'INSERT INTO notify ("member_id", "interest", "' || event || '") VALUES ($1, $2, TRUE)'
          USING i * 10 + j, interest;
        END IF;

        j := j + 1;
      END LOOP;

      i := i + 1;
    END LOOP;

    -- create the user 9 for actions
    INSERT INTO "member"
    ("id", "activated", "last_activity", "active", "login", "name", "notify_email", "notify_level") VALUES
    (9, 'now', 'now', TRUE, 'user9', 'User #9 action', 'user9.action@example.com', 'expert');

    RETURN;
  END;
$$;

SELECT create_users();

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
    'Successful',
    '1 hour', '1 hour', '1 hour', '1 hour',
    1, 100,
    1, 100,
    1, 2, TRUE,
    TRUE, FALSE
  ), (
    2,
    'Not successful in voting',
    '1 hour', '1 hour', '1 hour', '1 hour',
    1, 100,
    1, 100,
    1, 2, TRUE,
    TRUE, FALSE
  ), (
    3,
    'Not Admitted (Initiative Quorum failed)',
    '1 hour', '1 hour', '1 hour', '1 hour',
    1, 100,
    100, 100,
    1, 2, TRUE,
    TRUE, FALSE
  ), (
    4,
    'Not Accepted (Issue Quorum failed)',
    '1 hour', '1 hour', '1 hour', '1 hour',
    100, 100,
    100, 100,
    1, 2, TRUE,
    TRUE, FALSE
  );


CREATE FUNCTION "main"() RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE AS $$
  DECLARE
    i INT;
  BEGIN

    -- create environment
    INSERT INTO "unit" ("name") VALUES
    ('Main');
    INSERT INTO "area" ("unit_id", "name") VALUES
    (1, 'Area #1');
    INSERT INTO "allowed_policy" ("area_id", "policy_id", "default_policy") VALUES
    (1, 1, TRUE);
    -- set participation of the users
    INSERT INTO "privilege" ("unit_id", "member_id", "voting_right")
      SELECT 1 AS "unit_id", "id" AS "member_id", TRUE AS "voting_right"
      FROM "member" WHERE "id" % 10 != 0;
    INSERT INTO "membership" ("area_id", "member_id")
      SELECT 1 AS "area_id", "id" AS "member_id"
      FROM "member" WHERE "id" % 10 = 2;

    FOR i IN 1..4 LOOP
      -- successful issue
      INSERT INTO "issue" ("area_id", "policy_id") VALUES
      (1, i);
      INSERT INTO "initiative" ("issue_id", "name") VALUES
      (i, 'Initiative #' || i);
      INSERT INTO "draft" ("initiative_id", "author_id", "name", "content") VALUES
      (i, 9, 'Name', 'Lorem ipsum...');
      INSERT INTO "initiator" ("initiative_id", "member_id") VALUES
      (i, 9);
      INSERT INTO "suggestion" ("initiative_id", "author_id", "name", "content") VALUES
      (i, 9, 'Suggestion #' || i, 'Lorem ipsum...');
      INSERT INTO "opinion" ("member_id", "suggestion_id", "degree", "fulfilled") VALUES
      (9, i, 1, FALSE);
      -- set participation of the users
      INSERT INTO "initiator" ("initiative_id", "member_id")
        SELECT i AS "initiative_id", "id" AS "member_id"
        FROM "member" WHERE "id" % 10 = 6;
      INSERT INTO "interest" ("issue_id", "member_id")
        SELECT i AS "issue_id", "id" AS "member_id"
        FROM "member" WHERE "id" % 10 = 3;
      INSERT INTO "supporter" ("initiative_id", "member_id", "draft_id")
        SELECT i AS "initiative_id", "id" AS "member_id", i AS "draft_id"
        FROM "member" WHERE "id" % 10 = 4 OR "id" % 10 = 5;
      INSERT INTO "opinion" ("member_id", "suggestion_id", "degree", "fulfilled")
        SELECT "id" AS "member_id", i AS "suggestion_id", 2 AS "degree", FALSE AS "fulfilled"
        FROM "member" WHERE "id" % 10 = 4;
    END LOOP;

    -- admission__initiative_created_in_existing_issue
    INSERT INTO "initiative" ("issue_id", "name") VALUES
    (1, 'Initiative #5');
    INSERT INTO "draft" ("initiative_id", "author_id", "name", "content") VALUES
    (5, 9, 'Name', 'Lorem ipsum...');
    INSERT INTO "initiator" ("initiative_id", "member_id") VALUES
    (5, 9);

    -- admission__new_draft_created
    INSERT INTO "draft" ("initiative_id", "author_id", "name", "content") VALUES
    (1, 9, 'Name 2', 'Lorem ipsum 2 ...');

    -- admission__suggestion_created

    -- admission__initiative_revoked
    UPDATE "initiative" SET "revoked" = now(), "revoked_by_member_id" = 9 WHERE "id" = 5;

    -- canceled_revoked_before_accepted

    -- canceled_issue_not_accepted
    -- -> initiative #4


    PERFORM "time_warp"(); -- discussion

    -- discussion
    -- discussion__initiative_created_in_existing_issue
    INSERT INTO "initiative" ("issue_id", "name") VALUES
    (1, 'Initiative #6');
    INSERT INTO "draft" ("initiative_id", "author_id", "name", "content") VALUES
    (6, 9, 'Name', 'Lorem ipsum...');
    INSERT INTO "initiator" ("initiative_id", "member_id") VALUES
    (6, 9);

    -- discussion__new_draft_created
    INSERT INTO "draft" ("initiative_id", "author_id", "name", "content") VALUES
    (1, 9, 'Name 3', 'Lorem ipsum 3 ...');

    -- discussion__suggestion_created
    INSERT INTO "suggestion" ("initiative_id", "author_id", "name", "content") VALUES
    (1, 9, 'Suggestion #5', 'Lorem ipsum...');
    INSERT INTO "opinion" ("member_id", "suggestion_id", "degree", "fulfilled") VALUES
    (9, 5, 1, FALSE);

    -- discussion__initiative_revoked
    UPDATE "initiative" SET "revoked" = now(), "revoked_by_member_id" = 9 WHERE "id" = 6;

    -- canceled_after_revocation_during_discussion


    PERFORM "time_warp"(); -- frozen

    -- verification
    -- verification__initiative_created_in_existing_issue
    INSERT INTO "initiative" ("issue_id", "name") VALUES
    (1, 'Initiative #7');
    INSERT INTO "draft" ("initiative_id", "author_id", "name", "content") VALUES
    (7, 9, 'Name', 'Lorem ipsum...');
    INSERT INTO "initiator" ("initiative_id", "member_id") VALUES
    (7, 9);

    -- verification__initiative_revoked
    UPDATE "initiative" SET "revoked" = now(), "revoked_by_member_id" = 9 WHERE "id" = 7;

    -- canceled_after_revocation_during_verification

    -- canceled_no_initiative_admitted
    -- -> initiative #3


    PERFORM "time_warp"(); -- voting

    -- voting

    -- finished_with_winner
    -- -> initiative #1
    INSERT INTO "direct_voter" ("member_id", "issue_id")
      SELECT "id" AS "member_id", 1 AS "issue_id"
      FROM "member" WHERE "id" % 10 = 7;
    INSERT INTO "vote" ("member_id", "issue_id", "initiative_id", "grade")
      SELECT "id" AS "member_id", 1 AS "issue_id", 1 AS "initiative_id", 1 AS "grade"
      FROM "member" WHERE "id" % 10 = 7;

    -- finished_without_winner
    -- -> initiative #2
    INSERT INTO "direct_voter" ("member_id", "issue_id")
      SELECT "id" AS "member_id", 2 AS "issue_id"
      FROM "member" WHERE "id" % 10 = 7;
    INSERT INTO "vote" ("member_id", "issue_id", "initiative_id", "grade")
      SELECT "id" AS "member_id", 2 AS "issue_id", 2 AS "initiative_id", -1 AS "grade"
      FROM "member" WHERE "id" % 10 = 7;

    PERFORM "time_warp"(); -- closed


    RETURN;
  END;
$$;

SELECT main();


END;

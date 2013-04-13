-- Recalculate the vote counts on all closed issues to show direct and deleted votes separately
-- This script is optional. Pirate Feedback v1.1.0 also handles old data, just without the distinction between direct and delegated votes.


BEGIN;


CREATE FUNCTION "count_votes"("issue_id_p" "issue"."id"%TYPE)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE AS $$
  BEGIN
    -- set voter count:
    UPDATE "issue" SET
      "voter_count"        = "subquery"."voter_count",
      "direct_voter_count" = "subquery"."direct_voter_count"
      FROM (
        SELECT
          coalesce(sum("weight"), 0) AS "voter_count",
          count(1)                   AS "direct_voter_count"
        FROM "direct_voter"
        WHERE "issue_id" = "issue_id_p"
      ) AS "subquery"
      WHERE "id" = "issue_id_p";
    -- materialize battle_view:
    -- NOTE: "closed" column of issue must be set at this point
    DELETE FROM "battle" WHERE "issue_id" = "issue_id_p";
    INSERT INTO "battle" (
      "issue_id",
      "winning_initiative_id", "losing_initiative_id",
      "count", "direct_count"
    ) SELECT
      "issue_id",
      "winning_initiative_id", "losing_initiative_id",
      "count", "direct_count"
      FROM "battle_view" WHERE "issue_id" = "issue_id_p";
    -- copy "positive_votes" and "negative_votes" from "battle" table:
    UPDATE "initiative" SET
      "positive_votes" = "battle_win"."count",
      "negative_votes" = "battle_lose"."count",
      "positive_direct_votes" = "battle_win"."direct_count",
      "negative_direct_votes" = "battle_lose"."direct_count"
      FROM "battle" AS "battle_win", "battle" AS "battle_lose"
      WHERE
        "battle_win"."issue_id" = "issue_id_p" AND
        "battle_win"."winning_initiative_id" = "initiative"."id" AND
        "battle_win"."losing_initiative_id" ISNULL AND
        "battle_lose"."issue_id" = "issue_id_p" AND
        "battle_lose"."losing_initiative_id" = "initiative"."id" AND
        "battle_lose"."winning_initiative_id" ISNULL;
  END;
$$;

SELECT "count_votes"("id") FROM "issue" WHERE "closed" IS NOT NULL;

DROP FUNCTION "count_votes"("issue_id_p" "issue"."id"%TYPE);


COMMIT;

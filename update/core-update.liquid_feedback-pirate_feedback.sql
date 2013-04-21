-- Convert a database from Liquid Feedback Core v2.2.3 to Pirate Feedback v1.2.0

-- See INSTALL for instructions!
-- After running this script the database schema must be recreated.


BEGIN;


-- convert delegation chains to preference lists

ALTER TABLE "delegation"
  ADD "preference" INT2 NOT NULL DEFAULT 0,
  DROP CONSTRAINT "delegation_unit_id_key",
  DROP CONSTRAINT "delegation_area_id_key",
  DROP CONSTRAINT "delegation_issue_id_key",
  ADD UNIQUE ("unit_id",  "truster_id", "preference"),
  ADD UNIQUE ("area_id",  "truster_id", "preference"),
  ADD UNIQUE ("issue_id", "truster_id", "preference"),
  ADD UNIQUE ("unit_id",  "truster_id", "trustee_id"),
  ADD UNIQUE ("area_id",  "truster_id", "trustee_id"),
  ADD UNIQUE ("issue_id", "truster_id", "trustee_id");

CREATE FUNCTION "autoincrement_delegation_preference_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      SELECT COALESCE(MAX(preference), 0) + 1
        INTO NEW.preference
        FROM "delegation"
        WHERE truster_id = NEW.truster_id
          AND (NEW.unit_id ISNULL OR unit_id = NEW.unit_id)
          AND (NEW.area_id ISNULL OR area_id = NEW.area_id)
          AND (NEW.issue_id ISNULL OR issue_id = NEW.issue_id);
      RETURN NEW;
    END;
  $$;
CREATE TRIGGER "autoincrement_delegation_preference" BEFORE INSERT ON "delegation"
  FOR EACH ROW EXECUTE PROCEDURE "autoincrement_delegation_preference_trigger"();

CREATE FUNCTION "delegation_chains_to_preference_lists"()
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "delegation_row"  "delegation"%ROWTYPE;
      "member_id_v"     INT4;
    BEGIN
      FOR "delegation_row" IN
        SELECT * FROM "delegation"
      LOOP
        FOR "member_id_v" IN
          -- index 0 is the member itsself, index 1 is the existing delegation record
          SELECT "member_id" FROM "delegation_chain"(
            "delegation_row"."truster_id",
            "delegation_row"."unit_id", "delegation_row"."area_id", "delegation_row"."issue_id"
          ) WHERE "index" > 1 AND NOT "loop" = 'repetition'
        LOOP
          INSERT INTO "delegation" (
            "truster_id",
            "trustee_id",
            "scope",
            "unit_id",
            "area_id",
            "issue_id"
          ) VALUES (
            "delegation_row"."truster_id",
            "member_id_v",
            "delegation_row"."scope",
            "delegation_row"."unit_id",
            "delegation_row"."area_id",
            "delegation_row"."issue_id"
          );
        END LOOP;
      END LOOP;
    END;
  $$;

SELECT "delegation_chains_to_preference_lists"();


-- convert snapshots

DROP TRIGGER "forbid_changes_on_closed_issue" ON "delegating_voter";

ALTER TABLE "delegating_population_snapshot"
  ADD "delegate_member_id" INT4 REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE "delegating_interest_snapshot"
  ADD "delegate_member_id" INT4 REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE "delegating_voter"
  ADD "delegate_member_id" INT4 REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

UPDATE "delegating_population_snapshot"
  SET "delegate_member_id" = "delegate_member_ids"[ array_upper("delegate_member_ids", 1) ];
UPDATE "delegating_interest_snapshot"
  SET "delegate_member_id" = "delegate_member_ids"[ array_upper("delegate_member_ids", 1) ];
UPDATE "delegating_voter"
  SET "delegate_member_id" = "delegate_member_ids"[ array_upper("delegate_member_ids", 1) ];

ALTER TABLE "delegating_population_snapshot"
  DROP "delegate_member_ids",
  DROP "weight";
ALTER TABLE "delegating_interest_snapshot"
  DROP "delegate_member_ids",
  DROP "weight";
ALTER TABLE "delegating_voter"
  DROP "delegate_member_ids",
  DROP "weight";


-- copy initiative names to drafts

ALTER TABLE "draft" ADD COLUMN "name" TEXT;
UPDATE "draft" SET "name" = "initiative"."name" FROM "initiative" WHERE "draft"."initiative_id" = "initiative"."id";


COMMIT;

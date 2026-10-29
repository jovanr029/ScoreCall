# Fixture sync

Keeps the current Premier League season in Salesforce up to date from football-data.org: teams, gameweeks, fixtures, results and the league table. Source and decisions: [decisions/002-fixture-source.md](decisions/002-fixture-source.md).

## How it runs

```
FixtureSyncJob          Schedulable, every 30 minutes (two cron jobs: :00 and :30)
  └─ FixtureSyncQueueable   Queueable + callouts; writes a Sync Log
       └─ FixtureSyncService
            ├─ FootballDataClient   2 callouts: /matches, /standings (Named Credential FootballData)
            ├─ GameweekAssigner     fixture → gameweek by kickoff date
            └─ writes, all or nothing:
                 lock passed gameweeks → season → teams → gameweeks → fixtures → table → lock again
FixtureTrigger (after update)
  └─ PredictionStatusService   void / re-open predictions when a fixture is postponed or changes gameweek
```

- **Callouts before DML:** Salesforce doesn't allow a callout after DML in one transaction. A Schedulable can't call out at all, and a class can't be both Schedulable and Queueable, hence the three classes.
- **Only changes are written.** A run with nothing new does no DML (about 450 ms of CPU, 8 queries).
- **All or nothing:** any error rolls back the whole run.
- **Gameweeks** are assigned by kickoff date (the API's matchday stays the original one for rescheduled matches).
- **Locking:** gameweeks whose deadline has passed are locked _before_ fixture changes are applied, so a last-minute postponement can't re-open them (`Gameweek__c.Locked__c`, see [game-rules.md](game-rules.md)).
- **Season table prediction deadline:** filled only when empty and the season hasn't started. For 2026/27 the PO sets it by hand (launch date).

## Sync Logs

The **Sync Logs** tab (admin only) shows one record per run that **failed** or **changed something**: status, start/finish time, a summary ("Fixtures changed: 3, gameweeks locked: 1, …") and, for failures, the error and stack trace. A failed run wrote nothing.

Logs older than 14 days are deleted automatically, because the Developer Edition orgs have only 5 MB of data storage (#23).

## Setting it up in an org

Once per org, after the code is deployed (as the admin user, who must have `ScoreCall_Admin`):

1. Enter the API key in the Named Credential (see [ci.md](ci.md)) and check it:
   ```bash
   sf apex run --file scripts/apex/check-football-data.apex --target-org scorecall-uat
   ```
2. Run the sync once (loads the whole season), then check the Sync Logs tab:
   ```bash
   sf apex run --file scripts/apex/run-fixture-sync.apex --target-org scorecall-uat
   ```
3. Schedule it every 30 minutes:
   ```bash
   sf apex run --file scripts/apex/schedule-fixture-sync.apex --target-org scorecall-uat
   ```

To stop it (e.g. after the last match of the season): `FixtureSyncJob.unschedule();` in anonymous Apex, or delete the two "ScoreCall fixture sync" jobs in **Setup → Scheduled Jobs**.

## Deploying while the sync is scheduled

Salesforce normally refuses to deploy Apex classes used by a scheduled job. `settings/Deployment.settings-meta.xml` turns on **"Allow deployments of components when corresponding Apex jobs are pending or in progress"**, so CI keeps working after the sync is scheduled.

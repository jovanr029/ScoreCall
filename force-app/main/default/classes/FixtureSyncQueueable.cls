/**
 * Runs one fixture sync and records the outcome in Sync_Log__c.
 *
 * Only failures and runs that changed data are logged, and logs older than
 * 14 days are deleted: the DE orgs have 5 MB of data storage (see #23).
 *
 *   System.enqueueJob(new FixtureSyncQueueable());   // scripts/apex/run-fixture-sync.apex
 */
public with sharing class FixtureSyncQueueable implements Queueable, Database.AllowsCallouts {
  @TestVisible
  private static final Integer KEEP_LOGS_DAYS = 14;

  public void execute(QueueableContext context) {
    Datetime started = System.now();
    Sync_Log__c log = null;
    try {
      FixtureSyncService.SyncResult result = new FixtureSyncService().run();
      if (hasChanges(result)) {
        log = new Sync_Log__c(
          Status__c = 'Success',
          Summary__c = result.summary()
        );
      }
    } catch (Exception e) {
      // The service rolls back its own DML, so a failed run wrote nothing.
      log = new Sync_Log__c(
        Status__c = 'Failed',
        Summary__c = e.getMessage().left(255),
        Error__c = (e.getTypeName() +
          ': ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString())
          .left(32768)
      );
    }

    if (log != null) {
      log.Started__c = started;
      log.Finished__c = System.now();
      insert log;
    }
    deleteOldLogs();
  }

  @TestVisible
  private static Boolean hasChanges(FixtureSyncService.SyncResult result) {
    return result.fixturesChanged +
      result.teamsChanged +
      result.gameweeksCreated +
      result.gameweeksLocked + result.seasonTeamsChanged > 0;
  }

  private static void deleteOldLogs() {
    Datetime cutoff = System.now().addDays(-KEEP_LOGS_DAYS);
    delete [SELECT Id FROM Sync_Log__c WHERE CreatedDate < :cutoff];
  }
}

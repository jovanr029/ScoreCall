/**
 * The schedule for the fixture sync: every 30 minutes.
 *
 *   FixtureSyncJob (Schedulable) -> FixtureSyncQueueable (callouts) -> FixtureSyncService
 *
 * A Schedulable can't make callouts, and a class can't be both Schedulable and
 * Queueable, so this class only enqueues FixtureSyncQueueable.
 *
 * Scheduled jobs run as the user who scheduled them: that user needs the
 * ScoreCall_Admin permission set (data access + the FootballData credential).
 *
 *   FixtureSyncJob.scheduleEveryHalfHour();   // scripts/apex/schedule-fixture-sync.apex
 *   FixtureSyncJob.unschedule();
 */
public with sharing class FixtureSyncJob implements Schedulable {
  public static final String JOB_NAME_PREFIX = 'ScoreCall fixture sync';

  /** Salesforce cron can't say "every 30 minutes", so: one job at :00, one at :30. */
  private static final Map<String, String> CRON_BY_JOB_NAME = new Map<String, String>{
    JOB_NAME_PREFIX + ' :00' => '0 0 * * * ?',
    JOB_NAME_PREFIX + ' :30' => '0 30 * * * ?'
  };

  /** (Re)schedules the two jobs. Safe to run again: existing ones are replaced. */
  public static List<Id> scheduleEveryHalfHour() {
    unschedule();
    List<Id> jobIds = new List<Id>();
    for (String jobName : CRON_BY_JOB_NAME.keySet()) {
      jobIds.add(
        System.schedule(
          jobName,
          CRON_BY_JOB_NAME.get(jobName),
          new FixtureSyncJob()
        )
      );
    }
    return jobIds;
  }

  /** Removes the scheduled sync jobs (e.g. at the end of the season). */
  public static void unschedule() {
    String namePattern = JOB_NAME_PREFIX + '%';
    for (CronTrigger job : [
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name LIKE :namePattern
    ]) {
      System.abortJob(job.Id);
    }
  }

  public void execute(SchedulableContext context) {
    System.enqueueJob(new FixtureSyncQueueable());
  }
}

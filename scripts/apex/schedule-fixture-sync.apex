// Schedules the fixture sync every 30 minutes (two jobs: at :00 and :30).
// Safe to run again: existing ScoreCall sync jobs are replaced, never duplicated.
//
//   sf apex run --file scripts/apex/schedule-fixture-sync.apex --target-org <alias>
//
// The jobs run as the user who runs this script: that user needs ScoreCall_Admin.
// To stop the sync: FixtureSyncJob.unschedule();

List<Id> jobIds = FixtureSyncJob.scheduleEveryHalfHour();
System.debug('FIXTURE_SYNC scheduled: ' + jobIds.size() + ' jobs ' + jobIds);

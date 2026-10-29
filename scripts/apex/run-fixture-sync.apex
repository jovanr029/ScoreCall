// Runs the fixture sync once, now (asynchronously, like the scheduled job).
//
//   sf apex run --file scripts/apex/run-fixture-sync.apex --target-org <alias>
//
// The result appears in the Sync Logs tab within a minute (only when the run
// failed or changed something). Needs ScoreCall_Admin and the API key in the org.

Id jobId = System.enqueueJob(new FixtureSyncQueueable());
System.debug(
  'FIXTURE_SYNC queued as job ' +
    jobId +
    '. Check the Sync Logs tab in a minute.'
);

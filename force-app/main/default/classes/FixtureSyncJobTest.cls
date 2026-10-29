@IsTest
private class FixtureSyncJobTest {
  @IsTest
  static void scheduleCreatesTwoJobsAndReschedulingDoesNotDuplicate() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.startTest();
      FixtureSyncJob.scheduleEveryHalfHour();
      List<Id> jobIds = FixtureSyncJob.scheduleEveryHalfHour();
      Test.stopTest();

      Assert.areEqual(2, jobIds.size());
      List<CronTrigger> jobs = [
        SELECT CronExpression, CronJobDetail.Name
        FROM CronTrigger
        WHERE CronJobDetail.Name LIKE 'ScoreCall fixture sync%'
        ORDER BY CronJobDetail.Name
      ];
      Assert.areEqual(
        2,
        jobs.size(),
        'Rescheduling replaces, never duplicates'
      );
      Assert.areEqual('0 0 * * * ?', jobs[0].CronExpression);
      Assert.areEqual('0 30 * * * ?', jobs[1].CronExpression);
    }
  }

  @IsTest
  static void unscheduleRemovesTheJobs() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.startTest();
      FixtureSyncJob.scheduleEveryHalfHour();
      FixtureSyncJob.unschedule();
      Test.stopTest();

      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM CronTrigger
          WHERE CronJobDetail.Name LIKE 'ScoreCall fixture sync%'
        ]
      );
    }
  }

  @IsTest
  static void scheduledExecutionEnqueuesTheSync() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.setMock(HttpCalloutMock.class, new FootballDataMock());

      Test.startTest();
      new FixtureSyncJob().execute((SchedulableContext) null);
      Assert.areEqual(
        1,
        Limits.getQueueableJobs(),
        'Hands over to the queueable'
      );
      Test.stopTest();
    }
  }
}

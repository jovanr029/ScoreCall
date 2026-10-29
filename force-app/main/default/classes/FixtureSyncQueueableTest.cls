@IsTest
private class FixtureSyncQueueableTest {
  @IsTest
  static void successfulRunWithChangesIsLogged() {
    System.runAs(TestDataFactory.adminUser()) {
      Test.setMock(HttpCalloutMock.class, new FootballDataMock());

      Test.startTest();
      System.enqueueJob(new FixtureSyncQueueable());
      Test.stopTest(); // runs the queueable

      Sync_Log__c log = [
        SELECT Status__c, Summary__c, Started__c, Finished__c, Error__c
        FROM Sync_Log__c
      ];
      Assert.areEqual('Success', log.Status__c);
      Assert.isTrue(
        log.Summary__c.contains('Fixtures changed: 4'),
        log.Summary__c
      );
      Assert.isNotNull(log.Started__c);
      Assert.isNotNull(log.Finished__c);
      Assert.isNull(log.Error__c);
      Assert.areEqual(4, [SELECT COUNT() FROM Fixture__c]);
    }
  }

  @IsTest
  static void failedRunIsLoggedWithTheError() {
    System.runAs(TestDataFactory.adminUser()) {
      FootballDataMock mock = new FootballDataMock();
      mock.statusByPath.put('/matches', 403);
      mock.bodyByPath.put(
        '/matches',
        '{"message":"The resource you are looking for is restricted."}'
      );
      Test.setMock(HttpCalloutMock.class, mock);

      Test.startTest();
      System.enqueueJob(new FixtureSyncQueueable());
      Test.stopTest();

      Sync_Log__c log = [
        SELECT Status__c, Summary__c, Error__c
        FROM Sync_Log__c
      ];
      Assert.areEqual('Failed', log.Status__c);
      Assert.isTrue(log.Summary__c.contains('HTTP 403'), log.Summary__c);
      Assert.isTrue(
        log.Error__c.contains('FootballDataException'),
        log.Error__c
      );
      Assert.areEqual(0, [SELECT COUNT() FROM Fixture__c], 'Nothing written');
    }
  }

  @IsTest
  static void runWithoutChangesIsNotLogged() {
    FixtureSyncService.SyncResult nothing = new FixtureSyncService.SyncResult();
    Assert.isFalse(FixtureSyncQueueable.hasChanges(nothing));

    FixtureSyncService.SyncResult oneLock = new FixtureSyncService.SyncResult();
    oneLock.gameweeksLocked = 1;
    Assert.isTrue(FixtureSyncQueueable.hasChanges(oneLock));
  }

  @IsTest
  static void logsOlderThanFourteenDaysAreDeleted() {
    System.runAs(TestDataFactory.adminUser()) {
      Sync_Log__c old = new Sync_Log__c(
        Status__c = 'Success',
        Summary__c = 'old'
      );
      Sync_Log__c recent = new Sync_Log__c(
        Status__c = 'Success',
        Summary__c = 'recent'
      );
      insert new List<Sync_Log__c>{ old, recent };
      Test.setCreatedDate(old.Id, System.now().addDays(-15));
      Test.setCreatedDate(recent.Id, System.now().addDays(-13));
      Test.setMock(HttpCalloutMock.class, new FootballDataMock());

      Test.startTest();
      System.enqueueJob(new FixtureSyncQueueable());
      Test.stopTest();

      Set<String> summaries = new Set<String>();
      for (Sync_Log__c log : [SELECT Summary__c FROM Sync_Log__c]) {
        summaries.add(log.Summary__c);
      }
      Assert.isFalse(summaries.contains('old'));
      Assert.isTrue(summaries.contains('recent'));
    }
  }
}

@IsTest
private class GameweekTriggerHandlerTest {
  @IsTest
  static void keySetOnInsertAndSameNumberTwiceRejected() {
    Season__c season = TestDataFactory.createSeason();
    Gameweek__c gameweek = TestDataFactory.createGameweek(season.Id, 8);

    Assert.areEqual(
      season.Id + '-8',
      [SELECT Unique_Key__c FROM Gameweek__c WHERE Id = :gameweek.Id]
      .Unique_Key__c
    );
    TestAssert.duplicateRejected(
      new Gameweek__c(Name = 'Duplicate', Season__c = season.Id, Number__c = 8)
    );
  }

  @IsTest
  static void keyFollowsNumberChangeOnUpdate() {
    Season__c season = TestDataFactory.createSeason();
    Gameweek__c gameweek = TestDataFactory.createGameweek(season.Id, 8);

    // Send only the changed field: Season__c is a non-reparentable master-detail.
    update new Gameweek__c(Id = gameweek.Id, Number__c = 9);

    Assert.areEqual(
      season.Id + '-9',
      [SELECT Unique_Key__c FROM Gameweek__c WHERE Id = :gameweek.Id]
      .Unique_Key__c
    );
  }

  @IsTest
  static void wholeSeasonInsertedInOneBatch() {
    Season__c season = TestDataFactory.createSeason();
    List<Gameweek__c> gameweeks = new List<Gameweek__c>();
    for (Integer i = 1; i <= 38; i++) {
      gameweeks.add(
        new Gameweek__c(Name = 'GW ' + i, Season__c = season.Id, Number__c = i)
      );
    }

    insert gameweeks;

    Assert.areEqual(
      38,
      [
        SELECT COUNT()
        FROM Gameweek__c
        WHERE Unique_Key__c LIKE :season.Id + '-%'
      ]
    );
  }
}

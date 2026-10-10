/**
 * Unit tests for the key format. No DML: records are built in memory with
 * fake IDs. The database behaviour (duplicates rejected) is tested in the
 * trigger handler tests.
 */
@IsTest
private class UniqueKeyServiceTest {
  private static Integer fakeIdCounter = 0;

  private static Id fakeId(Schema.SObjectType type) {
    fakeIdCounter++;
    String suffix = String.valueOf(fakeIdCounter).leftPad(12, '0');
    return Id.valueOf(type.getDescribe().getKeyPrefix() + suffix);
  }

  @IsTest
  static void seasonTeamKey() {
    Season_Team__c record = new Season_Team__c(
      Season__c = fakeId(Season__c.SObjectType),
      Team__c = fakeId(Team__c.SObjectType)
    );

    UniqueKeyService.setKeys(new List<Season_Team__c>{ record });

    Assert.areEqual(
      record.Season__c + '-' + record.Team__c,
      record.Unique_Key__c
    );
  }

  @IsTest
  static void gameweekKeyUsesWholeNumber() {
    Gameweek__c record = new Gameweek__c(
      Season__c = fakeId(Season__c.SObjectType),
      Number__c = 8.0
    );

    UniqueKeyService.setKeys(new List<Gameweek__c>{ record });

    Assert.areEqual(
      record.Season__c + '-8',
      record.Unique_Key__c,
      'Decimal 8.0 must become 8'
    );
  }

  @IsTest
  static void predictionKeyIncludesOwnerFixtureAndGameweek() {
    Prediction__c record = new Prediction__c(
      OwnerId = UserInfo.getUserId(),
      Fixture__c = fakeId(Fixture__c.SObjectType),
      Gameweek__c = fakeId(Gameweek__c.SObjectType)
    );

    UniqueKeyService.setKeys(new List<Prediction__c>{ record });

    Assert.areEqual(
      record.OwnerId + '-' + record.Fixture__c + '-' + record.Gameweek__c,
      record.Unique_Key__c
    );
  }

  @IsTest
  static void tablePredictionHasTeamAndPositionKeys() {
    Table_Prediction__c record = new Table_Prediction__c(
      OwnerId = UserInfo.getUserId(),
      Season__c = fakeId(Season__c.SObjectType),
      Team__c = fakeId(Team__c.SObjectType),
      Predicted_Position__c = 5
    );

    UniqueKeyService.setKeys(new List<Table_Prediction__c>{ record });

    String prefix = record.OwnerId + '-' + record.Season__c + '-';
    Assert.areEqual(prefix + record.Team__c, record.Team_Key__c);
    Assert.areEqual(prefix + '5', record.Position_Key__c);
  }

  @IsTest
  static void leagueMemberKey() {
    League_Member__c record = new League_Member__c(
      League__c = fakeId(League__c.SObjectType),
      User__c = UserInfo.getUserId()
    );

    UniqueKeyService.setKeys(new List<League_Member__c>{ record });

    Assert.areEqual(
      record.League__c + '-' + record.User__c,
      record.Unique_Key__c
    );
  }

  @IsTest
  static void missingNumberGivesKeyWithoutNumber() {
    Gameweek__c record = new Gameweek__c(
      Season__c = fakeId(Season__c.SObjectType)
    );

    UniqueKeyService.setKeys(new List<Gameweek__c>{ record });

    Assert.areEqual(record.Season__c + '-', record.Unique_Key__c);
  }
}

@IsTest
private class TablePredictionTriggerHandlerTest {
  @IsTest
  static void keysSetOnInsertAndDuplicateTeamOrPositionRejected() {
    Season__c season = TestDataFactory.createSeason();
    List<Team__c> teams = TestDataFactory.createTeams(2);
    Table_Prediction__c first = new Table_Prediction__c(
      Season__c = season.Id,
      Team__c = teams[0].Id,
      Predicted_Position__c = 1
    );
    insert first;

    first = [
      SELECT Team_Key__c, Position_Key__c
      FROM Table_Prediction__c
      WHERE Id = :first.Id
    ];
    String prefix = UserInfo.getUserId() + '-' + season.Id + '-';
    Assert.areEqual(prefix + teams[0].Id, first.Team_Key__c);
    Assert.areEqual(prefix + '1', first.Position_Key__c);

    TestAssert.duplicateRejected(
      new Table_Prediction__c(
        Season__c = season.Id,
        Team__c = teams[0].Id,
        Predicted_Position__c = 2
      )
    );
    TestAssert.duplicateRejected(
      new Table_Prediction__c(
        Season__c = season.Id,
        Team__c = teams[1].Id,
        Predicted_Position__c = 1
      )
    );
  }

  @IsTest
  static void positionKeyFollowsPositionChangeOnUpdate() {
    Season__c season = TestDataFactory.createSeason();
    Team__c team = TestDataFactory.createTeams(1)[0];
    Table_Prediction__c prediction = new Table_Prediction__c(
      Season__c = season.Id,
      Team__c = team.Id,
      Predicted_Position__c = 1
    );
    insert prediction;

    prediction.Predicted_Position__c = 4;
    update prediction;

    Assert.areEqual(
      UserInfo.getUserId() + '-' + season.Id + '-4',
      [
        SELECT Position_Key__c
        FROM Table_Prediction__c
        WHERE Id = :prediction.Id
      ]
      .Position_Key__c
    );
  }
}

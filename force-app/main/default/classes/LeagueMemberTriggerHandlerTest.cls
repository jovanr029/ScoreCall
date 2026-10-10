@IsTest
private class LeagueMemberTriggerHandlerTest {
  @IsTest
  static void keySetOnInsertAndJoiningTwiceRejected() {
    System.runAs(TestDataFactory.adminUser()) {
      League__c league = TestDataFactory.createLeague('Friends');
      League_Member__c member = new League_Member__c(
        League__c = league.Id,
        User__c = UserInfo.getUserId()
      );
      insert member;

      Assert.areEqual(
        league.Id + '-' + UserInfo.getUserId(),
        [SELECT Unique_Key__c FROM League_Member__c WHERE Id = :member.Id]
        .Unique_Key__c
      );
      TestAssert.duplicateRejected(
        new League_Member__c(
          League__c = league.Id,
          User__c = UserInfo.getUserId()
        )
      );
    }
  }

  @IsTest
  static void sameUserCanJoinSeveralLeagues() {
    System.runAs(TestDataFactory.adminUser()) {
      League__c friends = TestDataFactory.createLeague('Friends');
      League__c work = TestDataFactory.createLeague('Work');

      insert new List<League_Member__c>{
        new League_Member__c(
          League__c = friends.Id,
          User__c = UserInfo.getUserId()
        ),
        new League_Member__c(
          League__c = work.Id,
          User__c = UserInfo.getUserId()
        )
      };

      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM League_Member__c
          WHERE User__c = :UserInfo.getUserId()
        ]
      );
    }
  }

  @IsTest
  static void keyFollowsUserChangeOnUpdate() {
    System.runAs(TestDataFactory.adminUser()) {
      League__c friends = TestDataFactory.createLeague('Friends');
      League_Member__c member = new League_Member__c(
        League__c = friends.Id,
        User__c = UserInfo.getUserId()
      );
      insert member;

      User otherUser = [
        SELECT Id
        FROM User
        WHERE IsActive = TRUE AND Id != :UserInfo.getUserId()
        LIMIT 1
      ];
      // Send only the changed field: League__c is a non-reparentable master-detail.
      update new League_Member__c(Id = member.Id, User__c = otherUser.Id);

      Assert.areEqual(
        friends.Id + '-' + otherUser.Id,
        [SELECT Unique_Key__c FROM League_Member__c WHERE Id = :member.Id]
        .Unique_Key__c
      );
    }
  }
}

@IsTest
private class FriendSignupTriggerHandlerTest {
  private static Integer assignments(Id userId) {
    return [
      SELECT COUNT()
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :userId
        AND PermissionSet.Name = :FriendSignupTriggerHandler.PERMISSION_SET
    ];
  }

  private static User newPlayer(String alias) {
    User player = TestDataFactory.buildUser(
      alias,
      'Minimum Access - Salesforce'
    );
    insert player;
    return player;
  }

  @IsTest
  static void signupEventAssignsScoreCallPlayer() {
    User carol = newPlayer('carol');
    User dave = newPlayer('dave');

    Test.startTest();
    EventBus.publish(
      new List<Friend_Signup__e>{
        new Friend_Signup__e(User_Id__c = carol.Id),
        new Friend_Signup__e(User_Id__c = dave.Id)
      }
    );
    Test.stopTest(); // delivers the events

    Assert.areEqual(1, assignments(carol.Id));
    Assert.areEqual(1, assignments(dave.Id));
  }

  @IsTest
  static void doesNothingWhenAlreadyAssigned() {
    User carol = newPlayer('carol');
    TestDataFactory.assignPermissionSet(
      carol.Id,
      FriendSignupTriggerHandler.PERMISSION_SET
    );

    Test.startTest();
    EventBus.publish(new Friend_Signup__e(User_Id__c = carol.Id));
    Test.stopTest();

    Assert.areEqual(1, assignments(carol.Id), 'No duplicate assignment');
  }

  /**
   * In production the Automated Process user runs this. Running it as a
   * minimum-access user, who can't manage permission sets, proves it doesn't
   * depend on the running user's access (#31): it still sees carol's existing
   * assignment (no duplicate) and assigns dave.
   */
  @IsTest
  static void worksForAUserWhoCannotManagePermissionSets() {
    User carol = newPlayer('carol');
    User dave = newPlayer('dave');
    User nobody = newPlayer('nobody');
    TestDataFactory.assignPermissionSet(
      carol.Id,
      FriendSignupTriggerHandler.PERMISSION_SET
    );

    System.runAs(nobody) {
      Test.startTest();
      FriendSignupTriggerHandler.assignPlayer(new Set<Id>{ carol.Id, dave.Id });
      Test.stopTest();
    }

    Assert.areEqual(1, assignments(carol.Id), 'No duplicate assignment');
    Assert.areEqual(1, assignments(dave.Id));
  }
}

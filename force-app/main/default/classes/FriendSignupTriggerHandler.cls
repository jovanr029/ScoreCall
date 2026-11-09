/**
 * Assigns ScoreCall_Player to friends who just signed up on the site.
 *
 * The sign-up runs as the site's guest user, which can't query or assign
 * permission sets. It publishes a Friend_Signup__e event instead; platform
 * event triggers run as the Automated Process user, in their own transaction
 * (so no MIXED_DML with the contact the sign-up created).
 *
 * without sharing: assigns permission sets to users the running user doesn't
 * own; only ever ScoreCall_Player, only to the users in the events.
 */
public without sharing class FriendSignupTriggerHandler extends TriggerHandler {
  public static final String PERMISSION_SET = 'ScoreCall_Player';

  protected override void afterInsert(List<SObject> newRecords) {
    Set<Id> userIds = new Set<Id>();
    for (Friend_Signup__e signup : (List<Friend_Signup__e>) newRecords) {
      userIds.add(Id.valueOf(signup.User_Id__c));
    }
    assignPlayer(userIds);
  }

  @TestVisible
  private static void assignPlayer(Set<Id> userIds) {
    Id permissionSetId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :PERMISSION_SET
    ]
    .Id;
    for (PermissionSetAssignment existing : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE AssigneeId IN :userIds AND PermissionSetId = :permissionSetId
    ]) {
      userIds.remove(existing.AssigneeId);
    }

    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (Id userId : userIds) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = userId,
          PermissionSetId = permissionSetId
        )
      );
    }
    insert assignments;
  }
}

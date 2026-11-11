/**
 * Assigns ScoreCall_Player to friends who just signed up on the site.
 *
 * The sign-up runs as the site's guest user, which can't query or assign
 * permission sets. It publishes a Friend_Signup__e event instead; platform
 * event triggers run as the Automated Process user, in their own transaction
 * (so no MIXED_DML with the contact the sign-up created).
 *
 * System mode: assigns permission sets to users the running user doesn't
 * own; only ever ScoreCall_Player, only to the users in the events. The
 * queries and the insert say so explicitly (WITH SYSTEM_MODE,
 * AccessLevel.SYSTEM_MODE): "without sharing" alone doesn't lift the running
 * user's access since API 67 (#31).
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
      WITH SYSTEM_MODE
    ]
    .Id;
    for (PermissionSetAssignment existing : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE AssigneeId IN :userIds AND PermissionSetId = :permissionSetId
      WITH SYSTEM_MODE // other users' assignments
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
    // System mode: assigning a permission set to other users.
    Database.insert(assignments, AccessLevel.SYSTEM_MODE);
  }
}

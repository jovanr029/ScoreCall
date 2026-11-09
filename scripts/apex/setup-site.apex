// One-time setup for the friends' sign-up page, once per org (and again if
// the ScoreCall Players account is ever recreated).
//
//   sf apex run --file scripts/apex/setup-site.apex --target-org <org>
//
// The sign-up runs as the site's guest user, which can't query accounts or
// profiles. This script, run by the PO, finds or creates the "ScoreCall
// Players" account and stores its Id and the ScoreCall Friend profile's Id in
// ScoreCall Settings. The invite code and username suffix are set by hand in
// Setup (see docs/onboarding.md); this script keeps them as they are.
//
// The running user needs the ScoreCall Admin role: the account that holds the
// friends must be owned by someone with a role.

final String ACCOUNT_NAME = 'ScoreCall Players';

User runningUser = [
  SELECT Id, UserRoleId
  FROM User
  WHERE Id = :UserInfo.getUserId()
];
if (runningUser.UserRoleId == null) {
  throw new IllegalArgumentException(
    'Give yourself the ScoreCall Admin role first (see docs/onboarding.md).'
  );
}

List<Account> accounts = [
  SELECT Id
  FROM Account
  WHERE Name = :ACCOUNT_NAME
  LIMIT 1
];
Account players;
if (accounts.isEmpty()) {
  players = new Account(Name = ACCOUNT_NAME, OwnerId = runningUser.Id);
  insert players;
} else {
  players = accounts[0];
}

ScoreCall_Settings__c settings = ScoreCall_Settings__c.getOrgDefaults();
if (settings.Id == null) {
  settings.SetupOwnerId = UserInfo.getOrganizationId();
}
settings.Players_Account_Id__c = players.Id;
settings.Friend_Profile_Id__c = [
  SELECT Id
  FROM Profile
  WHERE Name = 'ScoreCall Friend'
]
.Id;
upsert settings;

System.debug(
  LoggingLevel.INFO,
  'Sign-up set up. Invite code set: ' +
    String.isNotBlank(settings.Invite_Code__c) +
    ', username suffix: ' +
    settings.Username_Suffix__c
);

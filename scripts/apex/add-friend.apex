// Adds a friend as a ScoreCall site user (Customer Community licence).
//
//   1. Fill in the friend's details below.
//   2. sf apex run --file scripts/apex/add-friend.apex --target-org <org>
//   3. sf org assign permset --name ScoreCall_Player --on-behalf-of <username> --target-org <org>
//
// Creates a contact on the "ScoreCall Players" account (created on first use)
// and a site user with the ScoreCall Friend profile (Customer Community licence). When the site is
// published, Salesforce emails the friend a welcome link to set their password.
//
// The permission set is a separate step (3): Apex can't insert a setup object
// (PermissionSetAssignment) in the same transaction as Account/Contact
// (MIXED_DML_OPERATION).
//
// Before the first run in an org, the running user needs a role (ScoreCall Admin):
// the account that holds the friends must be owned by someone with a role.
// See docs/onboarding.md.

String firstName = 'Test';
String lastName = 'Friend';
String email = 'test.friend@example.com';
// Usernames are unique across all Salesforce orgs, so add a suffix per org.
String usernameSuffix = '.scorecall';
String timeZone = 'Europe/Belgrade';

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

Contact friend = new Contact(
  AccountId = players.Id,
  FirstName = firstName,
  LastName = lastName,
  Email = email
);
insert friend;

Profile communityProfile = [
  SELECT Id
  FROM Profile
  WHERE Name = 'ScoreCall Friend'
];
String alias = (firstName.left(1) + lastName).left(8);
User siteUser = new User(
  ContactId = friend.Id,
  ProfileId = communityProfile.Id,
  FirstName = firstName,
  LastName = lastName,
  Email = email,
  Username = email + usernameSuffix,
  Alias = alias,
  CommunityNickname = (firstName +
    '.' +
    lastName +
    '.' +
    Datetime.now().getTime())
    .left(40),
  TimeZoneSidKey = timeZone,
  LocaleSidKey = 'en_GB',
  LanguageLocaleKey = 'en_US',
  EmailEncodingKey = 'UTF-8'
);
// Sends the site's welcome email (with the set-password link) once the site is live.
Database.DMLOptions options = new Database.DMLOptions();
options.EmailHeader.triggerUserEmail = true;
options.OptAllOrNone = true; // with DMLOptions, errors are silent unless this is set
Database.insert(siteUser, options);

System.debug(
  LoggingLevel.INFO,
  'Added ' +
    siteUser.Username +
    '. Next: sf org assign permset --name ScoreCall_Player --on-behalf-of ' +
    siteUser.Username
);

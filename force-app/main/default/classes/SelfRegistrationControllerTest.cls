/**
 * Sign-up rules, run as the site's guest user: that's who calls the
 * controller on the Register page, and the guest can't use most setup and
 * standard objects (Account, Contact, Profile, permission sets...). Running as
 * an admin would hide exactly those problems.
 *
 * Site.createExternalUser and Site.login don't work in tests, so the friend's
 * user is created here in setup and the controller "creates" it via
 * SelfRegistrationController.testUserId.
 */
@IsTest
private class SelfRegistrationControllerTest {
  private static final String CODE = 'GoalGoal26';
  private static final String SUFFIX = '.sc-test';
  private static final String PASSWORD = 'Test-Only-Pass-123';
  private static final String EXISTING_EMAIL = 'carol@example.com';

  @TestSetup
  static void setup() {
    // The friends' account must be owned by a user with a role.
    User owner = TestDataFactory.buildUser('owner', 'System Administrator');
    owner.UserRoleId = [
      SELECT Id
      FROM UserRole
      WHERE DeveloperName = 'ScoreCall_Admin'
    ]
    .Id;
    insert owner;

    // The guest gets exactly what a real org gives it (docs/onboarding.md),
    // so the tests don't depend on whether that step was done in this org.
    Id guestId = guest().Id;
    if (
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE AssigneeId = :guestId AND PermissionSet.Name = 'ScoreCall_Guest'
      ] == 0
    ) {
      TestDataFactory.assignPermissionSet(guestId, 'ScoreCall_Guest');
    }

    // Each System.runAs block is a separate context, so setup objects (User)
    // and data (Account, Contact, custom setting) don't mix (MIXED_DML).
    Account players = new Account(Name = 'ScoreCall Players');
    Contact carol = new Contact(LastName = 'carol', Email = EXISTING_EMAIL);
    System.runAs(owner) {
      insert players;
      carol.AccountId = players.Id;
      insert carol;
    }

    Id friendProfileId = [
      SELECT Id
      FROM Profile
      WHERE Name = 'ScoreCall Friend'
    ]
    .Id;
    System.runAs(owner) {
      User friend = TestDataFactory.buildUser('carol', 'ScoreCall Friend');
      friend.ContactId = carol.Id;
      friend.Username = EXISTING_EMAIL + SUFFIX;
      insert friend;
    }

    System.runAs(owner) {
      insert new ScoreCall_Settings__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        Invite_Code__c = CODE,
        Username_Suffix__c = SUFFIX,
        Players_Account_Id__c = players.Id,
        Friend_Profile_Id__c = friendProfileId
      );
    }
  }

  /** The ScoreCall site's guest user (exists once the site is deployed). */
  private static User guest() {
    return [
      SELECT Id
      FROM User
      WHERE UserType = 'Guest' AND Profile.Name = 'ScoreCall Profile'
      LIMIT 1
    ];
  }

  private static User carol() {
    return [SELECT Id FROM User WHERE Username = :(EXISTING_EMAIL + SUFFIX)];
  }

  private static Id register(String email, String inviteCode) {
    return SelfRegistrationController.register(
      'Dave',
      'Friend',
      email,
      PASSWORD,
      inviteCode,
      'Europe/Belgrade'
    );
  }

  /** Runs register() as the guest and returns its error message. */
  private static String registerError(String email, String inviteCode) {
    String message;
    System.runAs(guest()) {
      try {
        register(email, inviteCode);
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }
    Assert.isNotNull(message, 'Expected the sign-up to be refused');
    return message;
  }

  @IsTest
  static void signUpAsTheGuestGivesTheFriendScoreCallPlayer() {
    User friend = carol();
    SelfRegistrationController.testUserId = friend.Id;

    Test.startTest();
    System.runAs(guest()) {
      Assert.areEqual(
        friend.Id,
        SelfRegistrationController.register(
          'Dave',
          'Friend',
          'dave@example.com',
          PASSWORD,
          '  goalgoal26 ', // not case-sensitive, spaces ignored
          'Europe/Belgrade'
        )
      );
    }
    Test.stopTest(); // delivers Friend_Signup__e to FriendSignupTrigger

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :friend.Id
          AND PermissionSet.Name = :FriendSignupTriggerHandler.PERMISSION_SET
      ]
    );
  }

  @IsTest
  static void wrongCodeIsRefused() {
    Assert.areEqual(
      'That invite code isn\'t right.',
      registerError('dave@example.com', 'guess')
    );
  }

  @IsTest
  static void signUpIsClosedWithoutACode() {
    ScoreCall_Settings__c settings = ScoreCall_Settings__c.getOrgDefaults();
    settings.Invite_Code__c = null;
    update settings;

    Assert.areEqual(
      'Sign-up is closed. Ask the organiser for an invite.',
      registerError('dave@example.com', CODE)
    );
  }

  @IsTest
  static void signUpNeedsTheSetupScript() {
    ScoreCall_Settings__c settings = ScoreCall_Settings__c.getOrgDefaults();
    settings.Players_Account_Id__c = null;
    update settings;

    Assert.areEqual(
      'Sign-up isn\'t set up yet. Ask the organiser.',
      registerError('dave@example.com', CODE)
    );
  }

  @IsTest
  static void missingOrInvalidDetailsAreRefused() {
    Assert.areEqual(
      'Please enter a valid email address.',
      registerError('not-an-email', CODE)
    );

    String blankName;
    String blankPassword;
    System.runAs(guest()) {
      try {
        SelfRegistrationController.register(
          ' ',
          'Friend',
          'dave@example.com',
          PASSWORD,
          CODE,
          null
        );
      } catch (AuraHandledException e) {
        blankName = e.getMessage();
      }
      try {
        SelfRegistrationController.register(
          'Dave',
          'Friend',
          'dave@example.com',
          ' ',
          CODE,
          null
        );
      } catch (AuraHandledException e) {
        blankPassword = e.getMessage();
      }
    }
    Assert.areEqual('Please enter your first and last name.', blankName);
    Assert.areEqual('Please choose a password.', blankPassword);
  }

  @IsTest
  static void salesforceErrorsBecomeFriendlyMessages() {
    // The guest user can't check seats in advance, so a full org shows up
    // as a licence error when the user is created.
    Assert.areEqual(
      SelfRegistrationController.FULL,
      SelfRegistrationController.createErrorMessage(
        new DmlException('LICENSE_LIMIT_EXCEEDED, License Limit Exceeded')
      )
    );
    Assert.areEqual(
      'Your password must have at least 8 characters.',
      SelfRegistrationController.createErrorMessage(
        new DmlException('Your password must have at least 8 characters.')
      ),
      'Other errors are shown as they are'
    );
    Assert.areEqual(
      SelfRegistrationController.ALREADY_REGISTERED,
      SelfRegistrationController.createErrorMessage(
        new DmlException('DUPLICATE_USERNAME, Duplicate Username.')
      ),
      'The guest can\'t see other users, so a duplicate shows up here'
    );
  }

  @IsTest
  static void usernameIsTheEmailPlusTheSuffix() {
    Assert.areEqual(
      'carol@example.com.x',
      SelfRegistrationController.username(
        ' Carol@Example.com ',
        new ScoreCall_Settings__c(Username_Suffix__c = '.x')
      )
    );
    Assert.areEqual(
      'carol@example.com',
      SelfRegistrationController.username(
        'carol@example.com',
        new ScoreCall_Settings__c()
      )
    );
  }

  @IsTest
  static void timeZoneFallsBackToTheDefault() {
    Assert.areEqual(
      'Europe/London',
      SelfRegistrationController.validTimeZone('Europe/London')
    );
    Assert.areEqual(
      'Europe/Belgrade',
      SelfRegistrationController.validTimeZone('Not/AZone')
    );
    Assert.areEqual(
      'Europe/Belgrade',
      SelfRegistrationController.validTimeZone(null)
    );
  }

  @IsTest
  static void loginOutsideASiteFails() {
    // Site.login returns null outside a site request (and in every test).
    String message;
    System.runAs(guest()) {
      try {
        SelfRegistrationController.login(
          'dave@example.com',
          PASSWORD,
          '/scorecall/'
        );
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }
    Assert.isTrue(message.contains('logging in failed'), message);
  }
}

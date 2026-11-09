/**
 * Sign-up for friends on the site (#28). Called by the selfRegistration LWC on
 * the site's Register page, so it runs as the site's guest user.
 *
 *   register()  checks the invite code, creates the friend (contact on "ScoreCall Players", user with
 *               the ScoreCall Friend profile and their own password) and
 *               publishes Friend_Signup__e, which assigns ScoreCall_Player.
 *   login()     logs the new friend in; returns the URL to go to.
 *
 * The guest user can't query Account, Contact, Profile, UserRole, UserLicense
 * or permission sets, not even without sharing (SelfRegistrationControllerTest
 * runs as the guest to prove the rest works). So:
 *   - the account and profile Ids come from ScoreCall Settings, filled in by
 *     scripts/apex/setup-site.apex;
 *   - Site.createExternalUser creates the contact and user (the supported way
 *     for a guest) and enforces the seat limit;
 *   - the permission set is assigned by FriendSignupTrigger, which runs as the
 *     Automated Process user.
 *
 * without sharing: the guest user has no access to the records involved;
 * every input is validated here. Nothing is returned except the new user's Id
 * and the login URL.
 */
public without sharing class SelfRegistrationController {
  @TestVisible
  private static final String FULL = 'ScoreCall is full: all player places are taken. Ask the organiser.';
  @TestVisible
  private static final String ALREADY_REGISTERED = 'There is already an account for this email. Log in, or use "Forgot your password?".';
  private static final String DEFAULT_TIME_ZONE = 'Europe/Belgrade';
  // Not EMAIL: Apex names are case-insensitive, so it would clash with the
  // email parameter.
  private static final Pattern EMAIL_FORMAT = Pattern.compile(
    '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'
  );

  /**
   * Site.createExternalUser only works in a real site request, never in a
   * test. Tests set the user it should "create" here.
   */
  @TestVisible
  private static Id testUserId;

  @AuraEnabled
  public static Id register(
    String firstName,
    String lastName,
    String email,
    String password,
    String inviteCode,
    String timeZone
  ) {
    ScoreCall_Settings__c settings = ScoreCall_Settings__c.getOrgDefaults();
    checkInviteCode(settings, inviteCode);
    if (
      String.isBlank(settings.Players_Account_Id__c) ||
      String.isBlank(settings.Friend_Profile_Id__c)
    ) {
      throw error('Sign-up isn\'t set up yet. Ask the organiser.');
    }

    if (String.isBlank(firstName) || String.isBlank(lastName)) {
      throw error('Please enter your first and last name.');
    }
    if (
      String.isBlank(email) || !EMAIL_FORMAT.matcher(email.trim()).matches()
    ) {
      throw error('Please enter a valid email address.');
    }
    if (String.isBlank(password)) {
      throw error('Please choose a password.');
    }

    // No "email already used" check here: the guest user can't see other
    // users. Site.createExternalUser refuses a duplicate username instead.
    String username = username(email, settings);
    User friend = new User(
      FirstName = firstName.trim(),
      LastName = lastName.trim(),
      Email = email.trim(),
      Username = username,
      Alias = (firstName.trim().left(1) + lastName.trim()).left(8),
      CommunityNickname = (firstName.trim() +
        '.' +
        lastName.trim() +
        '.' +
        Crypto.getRandomInteger())
        .left(40),
      ProfileId = settings.Friend_Profile_Id__c,
      TimeZoneSidKey = validTimeZone(timeZone),
      LocaleSidKey = 'en_GB',
      LanguageLocaleKey = 'en_US',
      EmailEncodingKey = 'UTF-8'
    );
    Id userId = createExternalUser(
      friend,
      settings.Players_Account_Id__c,
      password
    );

    // Delivered after commit; FriendSignupTrigger assigns ScoreCall_Player.
    // publish() reports failures in its result instead of throwing. Throwing
    // here rolls back the new user, so nobody is left without access.
    Database.SaveResult published = EventBus.publish(
      new Friend_Signup__e(User_Id__c = userId)
    );
    if (!published.isSuccess()) {
      throw error('Sign-up didn\'t work. Please try again later.');
    }
    return userId;
  }

  /** Logs the new friend in and returns the URL to send the browser to. */
  @AuraEnabled
  public static String login(String email, String password, String startUrl) {
    String username = username(email, ScoreCall_Settings__c.getOrgDefaults());
    PageReference page = Site.login(username, password, startUrl);
    if (page == null) {
      throw error('Your account is ready, but logging in failed. Log in.');
    }
    return page.getUrl();
  }

  private static void checkInviteCode(
    ScoreCall_Settings__c settings,
    String inviteCode
  ) {
    String expected = settings.Invite_Code__c;
    if (String.isBlank(expected)) {
      throw error('Sign-up is closed. Ask the organiser for an invite.');
    }
    if (
      String.isBlank(inviteCode) ||
      !expected.trim().equalsIgnoreCase(inviteCode.trim())
    ) {
      throw error('That invite code isn\'t right.');
    }
  }

  @TestVisible
  private static String username(String email, ScoreCall_Settings__c settings) {
    String suffix = settings.Username_Suffix__c == null
      ? ''
      : settings.Username_Suffix__c.trim();
    return email.trim().toLowerCase() + suffix;
  }

  /**
   * Site.createExternalUser is the supported way for a guest to create a site
   * user: it creates the contact and the user, sets the password (checked
   * against the password policy) and fails when no licence is left.
   */
  private static Id createExternalUser(
    User friend,
    Id accountId,
    String password
  ) {
    if (Test.isRunningTest()) {
      return testUserId;
    }
    try {
      return Site.createExternalUser(friend, accountId, password, false);
    } catch (Exception e) {
      // The friend sees a short message; the full error goes to the debug log
      // (set a trace flag on the site's guest user to see it).
      System.debug(
        LoggingLevel.WARN,
        'Site.createExternalUser failed: ' +
          e.getTypeName() +
          ': ' +
          e.getMessage() +
          (e instanceof Site.ExternalUserCreateException
            ? ' ' + ((Site.ExternalUserCreateException) e).getDisplayMessages()
            : '')
      );
      throw error(createErrorMessage(e));
    }
  }

  /**
   * What the friend sees when creating the user fails: the password policy's
   * own message, "ScoreCall is full" for a licence error, or "already an
   * account" for a duplicate username (the guest user can't check either in
   * advance).
   */
  @TestVisible
  private static String createErrorMessage(Exception e) {
    String text = e instanceof Site.ExternalUserCreateException
      ? String.join(
          ((Site.ExternalUserCreateException) e).getDisplayMessages(),
          ' '
        )
      : e.getMessage();
    if (text.containsIgnoreCase('licen')) {
      return FULL;
    }
    return text.containsIgnoreCase('username') ? ALREADY_REGISTERED : text;
  }

  @TestVisible
  private static String validTimeZone(String timeZone) {
    if (String.isBlank(timeZone)) {
      return DEFAULT_TIME_ZONE;
    }
    // TimeZone.getTimeZone returns GMT for an unknown id.
    String id = System.TimeZone.getTimeZone(timeZone).getID();
    return id == 'GMT' && timeZone != 'GMT' ? DEFAULT_TIME_ZONE : id;
  }

  private static AuraHandledException error(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}

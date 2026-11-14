# Friends' site and onboarding

Friends play on an Experience Cloud site: an **LWR** site called **ScoreCall** at `https://<my-domain>.my.site.com/scorecall`. It is private: everything except the login and sign-up pages needs a login. Friends **sign up themselves with an invite code** (#28); `add-friend.apex` is the fallback. Licence decision: [decisions/001-site-licence.md](decisions/001-site-licence.md).

## What's in source

| Metadata                              | What                                                                                                                                                |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `digitalExperiences/site/ScoreCall1`  | The site's pages, theme and routes. Home page = `scorecallHome` (tabs Predict, Leaderboard and All predictions), Register page = `selfRegistration` |
| `digitalExperienceConfigs/ScoreCall1` | Site URL path `/scorecall`                                                                                                                          |
| `networks/ScoreCall`                  | Site settings: members, emails, status Live, self-registration on                                                                                   |
| `sites/ScoreCall`                     | The underlying site record (the CLI created it with the site)                                                                                       |
| `profiles/ScoreCall Friend`           | Custom profile with the Customer Community licence, no permissions                                                                                  |
| `roles/ScoreCall_Admin`               | Role for the owner of the friends' account                                                                                                          |
| `permissionsets/ScoreCall_Player`     | All of a player's access (also site membership)                                                                                                     |
| `permissionsets/ScoreCall_Guest`      | The guest user (not logged in): only the sign-up Apex and its event                                                                                 |
| `objects/Friend_Signup__e`            | Platform event: "a friend signed up", assigns ScoreCall_Player                                                                                      |
| `objects/ScoreCall_Settings__c`       | Custom setting: invite code, username suffix, account and profile Ids, set per org                                                                  |

`ScoreCall1` is the name Salesforce gave the site's content when it was created; the site itself is called ScoreCall.

**Site members** are users with the **ScoreCall Friend** profile or the `ScoreCall_Player` permission set, and System Administrators (so the PO can preview the site). The profile makes a new friend a member the moment their user exists.

Every deploy is followed by a **publish** in CI; changes made in Experience Builder must be retrieved into source (`sf project retrieve start --metadata DigitalExperienceBundle:site/ScoreCall1`), otherwise the next deploy overwrites them.

## One-time setup per org (UAT, then production)

### Before the first deploy

1. **Enable Digital Experiences:** Setup → Digital Experiences → Settings → **Enable Digital Experiences**, Save. With enhanced domains (all new orgs) there is no domain to choose: the site lives at `<My Domain>.my.site.com`. It **can't be turned off** again. Without it, deploying the site metadata fails.
2. **Sender address secret** (once, for both orgs): `gh secret set SITE_SENDER_EMAIL` with the address the site's emails come from. See [ci.md](ci.md#org-specific-values-in-the-site-metadata).

### After the first deploy

3. **Verify the sender address:** Salesforce emails it a verification link. Click it.
4. **Give yourself the ScoreCall Admin role:** Setup → Users → your user → Edit → Role = ScoreCall Admin. A friend's account must be owned by someone with a role.

5. **Open sign-up:** Setup → Custom Settings → **ScoreCall Settings** → Manage → **New** (the org default, top section):
   - **Invite Code**: the code you'll send to friends. Not case-sensitive. Change it whenever you like; empty closes sign-up.
   - **Username Suffix**: `.scorecall` in production, `.scorecall-uat` in UAT. Usernames are unique across all Salesforce orgs.
6. **Let the sign-up page call Apex:** give the site's guest user the `ScoreCall_Guest` permission set. Find the guest username, then assign it:

   ```powershell
   sf data query --query "SELECT Username FROM User WHERE Profile.Name = 'ScoreCall Profile'" --target-org scorecall-uat
   sf org assign permset --name ScoreCall_Guest --on-behalf-of <guest username> --target-org scorecall-uat
   ```

7. **Connect the sign-up to the account and profile:** run the setup script once (as yourself, with the ScoreCall Admin role). It creates the **ScoreCall Players** account if it doesn't exist and stores its Id and the ScoreCall Friend profile's Id in ScoreCall Settings; it leaves the invite code and suffix alone.

   ```bash
   sf apex run --file scripts/apex/setup-site.apex --target-org scorecall-uat
   ```

Internal players (not the PO) would get both `ScoreCall_Player` and `ScoreCall_Player_App`.

## How a friend signs up

1. You send them the site URL and the invite code.
2. On the login page they click **Not a member?**, fill in name, email, a password and the code, and click **Sign up**.
3. `SelfRegistrationController` (running as the guest user) checks the code and creates a contact on **ScoreCall Players** and a user with the **ScoreCall Friend** profile and their own password, via `Site.createExternalUser`. Salesforce itself refuses a duplicate username and a sign-up when no seat is left. For a duplicate it only returns a generic error (and emails the admin), on purpose: a visitor mustn't be able to find out which emails have an account. The page then says: "We couldn't create your account. If you already have one, log in or use Forgot your password?. Otherwise, ask the organiser."
4. The controller publishes a **Friend_Signup__e** event. `FriendSignupTrigger` runs as the Automated Process user and assigns `ScoreCall_Player`, normally within a second. The page waits 3 seconds ("Setting up your account…"), then logs them in.
5. Their username is their email plus the suffix. No email is needed to sign up; "Forgot your password?" does send one.

**Why it's built this way:** the site's guest user can't query or create Account, Contact, Profile, UserRole, UserLicense, other users or permission sets, not even in a `without sharing` class. So the Ids come from ScoreCall Settings, `Site.createExternalUser` (made for guests) creates the user, and the permission set is assigned by the event trigger, which runs as a system user. `SelfRegistrationControllerTest` runs as the guest user, so a change that needs more than that fails in CI.

## Adding a friend by hand (fallback)

1. In `scripts/apex/add-friend.apex`, fill in `firstName`, `lastName`, `email` and `timeZone`. Set `usernameSuffix` per org, for example `.scorecall` in production and `.scorecall-uat` in UAT: usernames are unique across all Salesforce orgs.
2. Run it:

   ```bash
   sf apex run --file scripts/apex/add-friend.apex --target-org scorecall-prod
   ```

3. Give them the permission set (it can't be done in the same Apex transaction as the contact):

   ```bash
   sf org assign permset --name ScoreCall_Player --on-behalf-of <username> --target-org scorecall-prod
   ```

4. Salesforce emails the friend a **welcome email** with a link to set their password. They log in at the site URL with their username (their email plus the suffix).

Don't commit the script with a friend's details filled in.

The script creates the **ScoreCall Players** account the first time, a contact for the friend, and a user with the **ScoreCall Friend** profile (Customer Community licence). There are 5 Customer Community seats; see the decision for what to do when they run out.

## Removing a friend

Setup → Users → the friend → Edit → untick **Active**. That frees the seat. Their predictions stay (and still count in past leaderboards). Site users can't be deleted, only deactivated.

## Testing as a friend

From the friend's contact record: ▼ → **Log in to Experience as User**. You see the site exactly as they do, without their password. Log out from the site to return.

In a scratch org, `scripts/apex/add-friend.apex` works as is (it creates `test.friend@example.com.scorecall`), after giving the scratch admin the ScoreCall Admin role.

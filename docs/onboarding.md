# Friends' site and onboarding

Friends play on an Experience Cloud site: an **LWR** site called **ScoreCall** at `https://<my-domain>.my.site.com/scorecall`. It is private: everything needs a login, and there is no self-registration. Licence decision: [decisions/001-site-licence.md](decisions/001-site-licence.md).

## What's in source

| Metadata                              | What                                                               |
| ------------------------------------- | ------------------------------------------------------------------ |
| `digitalExperiences/site/ScoreCall1`  | The site's pages, theme and routes. Home page = `predictionEntry`  |
| `digitalExperienceConfigs/ScoreCall1` | Site URL path `/scorecall`                                         |
| `networks/ScoreCall`                  | Site settings: members, emails, status Live, no self-registration  |
| `sites/ScoreCall`                     | The underlying site record (the CLI created it with the site)      |
| `profiles/ScoreCall Friend`           | Custom profile with the Customer Community licence, no permissions |
| `roles/ScoreCall_Admin`               | Role for the owner of the friends' account                         |
| `permissionsets/ScoreCall_Player`     | All of a player's access (also site membership)                    |

`ScoreCall1` is the name Salesforce gave the site's content when it was created; the site itself is called ScoreCall.

**Site members** are users with the `ScoreCall_Player` permission set (and System Administrators, so the PO can preview the site).

Every deploy is followed by a **publish** in CI; changes made in Experience Builder must be retrieved into source (`sf project retrieve start --metadata DigitalExperienceBundle:site/ScoreCall1`), otherwise the next deploy overwrites them.

## One-time setup per org (UAT, then production)

### Before the first deploy

1. **Enable Digital Experiences:** Setup → Digital Experiences → Settings → **Enable Digital Experiences**, Save. With enhanced domains (all new orgs) there is no domain to choose: the site lives at `<My Domain>.my.site.com`. It **can't be turned off** again. Without it, deploying the site metadata fails.
2. **Sender address secret** (once, for both orgs): `gh secret set SITE_SENDER_EMAIL` with the address the site's emails come from. See [ci.md](ci.md#org-specific-values-in-the-site-metadata).

### After the first deploy

3. **Verify the sender address:** Salesforce emails it a verification link. Click it.
4. **Give yourself the ScoreCall Admin role:** Setup → Users → your user → Edit → Role = ScoreCall Admin. A friend's account must be owned by someone with a role.

Internal players (not the PO) would get both `ScoreCall_Player` and `ScoreCall_Player_App`.

## Adding a friend

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

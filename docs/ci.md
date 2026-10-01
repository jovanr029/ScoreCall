# CI/CD

ScoreCall uses GitHub Actions. The workflows live in `.github/workflows/`.

```
PR opened / updated ──► PR checks
                          ├─ quality:  ESLint · Prettier check · LWC Jest
                          └─ validate: check-only deploy + RunLocalTests against UAT

Merge to main ────────► Deploy
                          ├─ uat:        deploy to scorecall-uat (automatic)
                          └─ production: deploy to scorecall-prod (waits for manual approval)
```

## PR checks (`pr.yml`)

- **quality** needs no org. It runs the same npm scripts you can run locally: `npm run lint`, `npm run prettier:verify` and `npm run test:unit`.
- **validate** runs `sf project deploy validate` against UAT. Salesforce compiles the metadata and runs all local Apex tests, then rolls everything back, so nothing is changed in UAT. This catches deploy errors and failing tests before merge without using scratch org limits (the Dev Hub only allows 6 per day).
- A new push to the same PR cancels the previous run.
- PRs from forks skip `validate`, because forks never get access to secrets.

## Deploy (`deploy.yml`)

- Runs on every push to `main`, which in practice means every merged PR. It can also be started by hand: **Actions → Deploy → Run workflow**.
- **uat** deploys straight away.
- **production** uses the `production` GitHub Environment, which has a required reviewer. The run pauses until you click **Review deployments → Approve** on the run page.
- Deployments are queued, never run in parallel.
- Both jobs deploy the whole `force-app` folder and run `RunLocalTests`.

## Branch protection

`main` is protected:

- Changes only via pull request.
- The `quality` and `validate` checks must pass, and the branch must be up to date with `main`.
- The rules apply to admins too, so nobody can push to `main` directly.

## Secrets

The orgs are authenticated with **SFDX auth URLs** (`force://...`), which contain a refresh token. Treat them like passwords.

| Secret             | Where                           | Org              |
| ------------------ | ------------------------------- | ---------------- |
| `SF_AUTH_URL_UAT`  | Repository secret               | `scorecall-uat`  |
| `SF_AUTH_URL_PROD` | `production` environment secret | `scorecall-prod` |

### Setting or rotating a secret

Run these in PowerShell from the project folder. The auth URL is piped straight into GitHub and never printed.

```powershell
(sf org auth show-sfdx-auth-url --target-org scorecall-uat --json | ConvertFrom-Json).result.sfdxAuthUrl | gh secret set SF_AUTH_URL_UAT
(sf org auth show-sfdx-auth-url --target-org scorecall-prod --json | ConvertFrom-Json).result.sfdxAuthUrl | gh secret set SF_AUTH_URL_PROD --env production
```

**Important:** `sf org logout` revokes the refresh token, and that breaks CI. If you log out of an org or re-authorize it, run the matching command again.

## Troubleshooting

- **`validate` fails with an auth error:** the secret is missing or has been revoked. Set it again (see above).
- **Prettier check fails:** run `npm run prettier` locally and commit the result. The pre-commit hook normally does this for you.
- **Deploy is stuck at "Waiting":** the production job is waiting for your approval on the run page.

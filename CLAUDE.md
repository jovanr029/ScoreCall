# ScoreCall

Premier League score-prediction game built on Salesforce. Each gameweek, players (the product owner and their friends) predict the score of every match. Friends use the app through an Experience Cloud site.

## Game rules

- **Correct outcome** (home win / draw / away win): 3 points.
- **Exact score**: +5 bonus, so 8 points in total.
- A correctly predicted draw counts as a correct outcome.
- Predictions can be edited until the **gameweek deadline**, which is 1 hour before the gameweek's first kickoff. After that, all predictions for the gameweek are locked.

## Orgs

| Alias            | Purpose                               | How changes get there          |
| ---------------- | ------------------------------------- | ------------------------------ |
| `scorecall-prod` | Production + Dev Hub                  | CI only, after merge to `main` |
| `scorecall-uat`  | UAT / acceptance testing              | CI only                        |
| scratch orgs     | Day-to-day development, one per story | `sf project deploy start`      |

- Never deploy to `scorecall-prod` or `scorecall-uat` by hand. Always pass `--target-org` explicitly for anything that touches them.
- The project's default `target-org` (in `.sf/config.json`, which is gitignored) should be the current scratch org.
- Scratch org definition: `config/project-scratch-def.json` (Communities enabled).

## Workflow

1. Each piece of work starts as a story (GitHub issue).
2. Branch off `main`: `feature/<issue#>-<short-name>`, `fix/...`, or `chore/...`.
3. Build and test in a scratch org.
4. Open a PR to `main`. CI must pass (lint, Prettier check, LWC Jest, Apex tests).
5. Squash-merge, then CI deploys.

Don't commit directly to `main`. Commit only when asked.

## Roles

- The user is the **product owner** and a **co-developer** who is learning LWC and Experience Cloud (experienced in core Salesforce/Apex).
- **LWC is written by the user.** Claude explains, scaffolds only when asked, and reviews the code. Don't write finished LWC components unless the user explicitly asks.
- Claude builds Apex, metadata, CI, and tooling by default, and explains the non-obvious parts.

## Conventions

- API version 67.0, no namespace, source in `force-app/main/default`.
- Line endings are LF (enforced by `.gitattributes`).
- Apex: bulkified, `with sharing` by default, `WITH USER_MODE` / `Security.stripInaccessible` for data exposed to site users. Every class has a test class (`<ClassName>Test`) and should reach at least 90% coverage; aim at behaviour, not just lines.
- Triggers: one trigger per object that delegates to a handler class, with no logic in the trigger body.
- LWC: camelCase folder names, Jest tests in `__tests__/` next to the component.
- Access goes through permission sets, never profiles.

## Commands

```bash
# Create a scratch org for a story and make it the default
sf org create scratch --definition-file config/project-scratch-def.json --alias scorecall-dev --duration-days 7 --set-default

# Deploy source / pull changes made in the org
sf project deploy start
sf project retrieve start

# Tests
sf apex run test --test-level RunLocalTests --result-format human --wait 10
npm run test:unit

# Lint and format
npm run lint
npm run prettier:verify
```

The Husky pre-commit hook runs Prettier, ESLint, and related LWC Jest tests on staged files.

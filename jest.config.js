const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  // .claude/ holds Claude Code worktrees: full copies of the project on other
  // branches. Their tests would run against this branch's components.
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver", "<rootDir>/.claude/"],
  testPathIgnorePatterns: [
    ...(jestConfig.testPathIgnorePatterns || ["/node_modules/"]),
    "<rootDir>/.claude/"
  ]
};

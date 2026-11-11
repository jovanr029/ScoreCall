import { createElement } from "lwc";
import Leaderboard, { reduceError } from "c/leaderboard";
import getLeaderboard from "@salesforce/apex/LeaderboardController.getLeaderboard";

jest.mock(
  "@salesforce/apex/LeaderboardController.getLeaderboard",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

function standings(overrides = {}) {
  return {
    seasonName: "2026/27",
    gameweekId: null,
    gameweeks: [
      { gameweekId: "a01GW8", name: "2026/27 GW 8" },
      { gameweekId: "a01GW7", name: "2026/27 GW 7" }
    ],
    rows: [
      {
        rank: 1,
        userId: "005A",
        name: "Alice",
        points: 16,
        exactScores: 2,
        isCurrentUser: false
      },
      {
        rank: 2,
        userId: "005C",
        name: "Carol",
        points: 11,
        exactScores: 1,
        isCurrentUser: true
      },
      {
        rank: 2,
        userId: "005D",
        name: "Dave",
        points: 11,
        exactScores: 1,
        isCurrentUser: false
      }
    ],
    ...overrides
  };
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function mount() {
  const element = createElement("c-leaderboard", { is: Leaderboard });
  document.body.appendChild(element);
  return element;
}

function cells(row) {
  return [...row.querySelectorAll("td")].map((cell) => cell.textContent);
}

describe("c-leaderboard", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a spinner until the standings arrive", () => {
    const element = mount();
    expect(
      element.shadowRoot.querySelector("lightning-spinner")
    ).not.toBeNull();
  });

  it("shows ranks, shared places and highlights the current user", async () => {
    const element = mount();
    getLeaderboard.emit(standings());
    await flush();

    const rows = [...element.shadowRoot.querySelectorAll("tbody tr")];
    expect(rows.map(cells)).toEqual([
      ["1", "Alice", "16", "2"],
      ["2", "Carol", "11", "1"],
      ["2", "Dave", "11", "1"]
    ]);
    expect(rows[1].classList.contains("me")).toBe(true);
    expect(rows[0].classList.contains("me")).toBe(false);
    expect(element.shadowRoot.querySelector(".subtitle").textContent).toBe(
      "Season 2026/27"
    );
  });

  it("asks for the whole season first, then the picked gameweek", async () => {
    const element = mount();
    // null = whole season; the test adapter drops null parameters
    expect(getLeaderboard.getLastConfig().gameweekId ?? null).toBeNull();

    getLeaderboard.emit(standings());
    await flush();
    const picker = element.shadowRoot.querySelector("lightning-combobox");
    expect(picker.options.map((option) => option.label)).toEqual([
      "Whole season",
      "2026/27 GW 8",
      "2026/27 GW 7"
    ]);

    picker.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a01GW7" } })
    );
    await flush();
    expect(getLeaderboard.getLastConfig()).toEqual({ gameweekId: "a01GW7" });
    getLeaderboard.emit(standings({ gameweekId: "a01GW7" }));
    await flush();
    expect(element.shadowRoot.querySelector(".subtitle").textContent).toBe(
      "2026/27 GW 7"
    );

    picker.dispatchEvent(new CustomEvent("change", { detail: { value: "" } }));
    await flush();
    expect(getLeaderboard.getLastConfig().gameweekId ?? null).toBeNull();
  });

  it("explains an empty table", async () => {
    const element = mount();
    getLeaderboard.emit(standings({ rows: [] }));
    await flush();

    expect(element.shadowRoot.querySelector("table")).toBeNull();
    expect(element.shadowRoot.querySelector(".empty")).not.toBeNull();
  });

  it("shows the error when the standings can't be loaded", async () => {
    const element = mount();
    getLeaderboard.error({ message: "Insufficient access" });
    await flush();

    expect(element.shadowRoot.querySelector(".error").textContent).toBe(
      "Insufficient access"
    );
  });
});

describe("reduceError", () => {
  it("prefers the Apex message", () => {
    expect(reduceError({ body: { message: "From Apex" } })).toBe("From Apex");
    expect(reduceError(undefined)).toBe("Unknown error");
  });
});

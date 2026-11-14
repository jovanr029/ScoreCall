import { createElement } from "lwc";
import GameweekPredictions, { reduceError } from "c/gameweekPredictions";
import getGameweekPredictions from "@salesforce/apex/GameweekPredictionsController.getGameweekPredictions";

jest.mock(
  "@salesforce/apex/GameweekPredictionsController.getGameweekPredictions",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

function prediction(userId, name, home, away, extra = {}) {
  return {
    userId,
    name,
    homeGoals: home,
    awayGoals: away,
    status: "Scored",
    points: 0,
    exactScore: false,
    isCurrentUser: false,
    ...extra
  };
}

function gameweek(overrides = {}) {
  return {
    gameweekId: "a01GW7",
    name: "2026/27 GW 7",
    previousGameweekId: "a01GW6",
    nextGameweekId: null,
    players: [
      { userId: "005C", name: "Carol", points: 11, isCurrentUser: true },
      { userId: "005A", name: "Alice", points: 8, isCurrentUser: false }
    ],
    matches: [
      {
        fixtureId: "a02M1",
        homeTeam: "Arsenal",
        awayTeam: "Chelsea",
        status: "Finished",
        homeGoals: 2,
        awayGoals: 1,
        predictions: [
          prediction("005C", "Carol", 2, 1, {
            points: 8,
            exactScore: true,
            isCurrentUser: true
          }),
          prediction("005A", "Alice", null, null, { status: null })
        ]
      },
      {
        fixtureId: "a02M2",
        homeTeam: "Leeds",
        awayTeam: "Spurs",
        status: "Postponed",
        homeGoals: null,
        awayGoals: null,
        predictions: [
          prediction("005C", "Carol", 1, 1, {
            status: "Voided",
            isCurrentUser: true
          }),
          prediction("005A", "Alice", 0, 2, { status: "Voided" })
        ]
      }
    ],
    ...overrides
  };
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function mount() {
  const element = createElement("c-gameweek-predictions", {
    is: GameweekPredictions
  });
  document.body.appendChild(element);
  return element;
}

function lines(matchElement) {
  return [...matchElement.querySelectorAll("li")].map((li) =>
    [...li.querySelectorAll("span")].map((span) => span.textContent)
  );
}

describe("c-gameweek-predictions", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a spinner until the predictions arrive", () => {
    const element = mount();
    expect(
      element.shadowRoot.querySelector("lightning-spinner")
    ).not.toBeNull();
  });

  it("shows every player's prediction and points per match", async () => {
    const element = mount();
    getGameweekPredictions.emit(gameweek());
    await flush();

    expect(element.shadowRoot.querySelector(".gameweek").textContent).toBe(
      "2026/27 GW 7"
    );
    const totals = [...element.shadowRoot.querySelectorAll(".total")];
    expect(totals.map((total) => total.textContent)).toEqual([
      "Carol 11",
      "Alice 8"
    ]);
    expect(totals[0].classList.contains("me")).toBe(true);

    const matches = [...element.shadowRoot.querySelectorAll(".match")];
    expect(matches[0].querySelector(".result").textContent).toBe("2–1");
    expect(lines(matches[0])).toEqual([
      ["Carol", "2–1", "+8"],
      ["Alice", "–", ""]
    ]);
    expect(
      matches[0].querySelector("li .points").classList.contains("exact")
    ).toBe(true);

    // A postponed match: no result yet, predictions voided
    expect(matches[1].querySelector(".result")).toBeNull();
    expect(matches[1].querySelector(".status").textContent).toBe("Postponed");
    expect(lines(matches[1])[1]).toEqual(["Alice", "0–2", "Void"]);
  });

  it("starts with the latest gameweek and moves back with the arrow", async () => {
    const element = mount();
    expect(
      getGameweekPredictions.getLastConfig().gameweekId ?? null
    ).toBeNull();

    getGameweekPredictions.emit(gameweek());
    await flush();
    expect(element.shadowRoot.querySelector(".next").disabled).toBe(true);

    element.shadowRoot.querySelector(".previous").click();
    await flush();
    expect(getGameweekPredictions.getLastConfig()).toEqual({
      gameweekId: "a01GW6"
    });
  });

  it("explains when no deadline has passed yet", async () => {
    const element = mount();
    getGameweekPredictions.emit({ players: [], matches: [] });
    await flush();

    expect(element.shadowRoot.querySelector(".empty")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".match")).toBeNull();
  });

  it("says so when nobody predicted the gameweek", async () => {
    const element = mount();
    getGameweekPredictions.emit(
      gameweek({
        players: [],
        matches: [{ ...gameweek().matches[0], predictions: [] }]
      })
    );
    await flush();

    expect(element.shadowRoot.querySelector(".no-players")).not.toBeNull();
  });

  it("shows the Apex refusal", async () => {
    const element = mount();
    // The test adapter puts this object in error.body, like a real Apex error.
    getGameweekPredictions.error({
      message:
        "Other players' predictions are visible after the gameweek deadline."
    });
    await flush();

    expect(element.shadowRoot.querySelector(".error").textContent).toBe(
      "Other players' predictions are visible after the gameweek deadline."
    );
  });
});

describe("reduceError", () => {
  it("prefers the Apex message", () => {
    expect(reduceError({ body: { message: "From Apex" } })).toBe("From Apex");
    expect(reduceError(undefined)).toBe("Unknown error");
  });
});

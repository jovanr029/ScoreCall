import { createElement } from "lwc";
import PredictionEntry, {
  formatDuration,
  reduceError
} from "c/predictionEntry";
import getGameweek from "@salesforce/apex/PredictionController.getGameweek";
import saveGameweekPredictions from "@salesforce/apex/PredictionController.saveGameweekPredictions";
import { refreshApex } from "@salesforce/apex";

// The wired Apex method becomes a test wire adapter: the test decides what it
// "returns" with emit() / error().
jest.mock(
  "@salesforce/apex/PredictionController.getGameweek",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// The imperative Apex method is a plain mock function.
jest.mock(
  "@salesforce/apex/PredictionController.saveGameweekPredictions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const IN_TWO_DAYS = new Date(Date.now() + 2 * 24 * 3600 * 1000).toISOString();
const YESTERDAY = new Date(Date.now() - 24 * 3600 * 1000).toISOString();

function gameweek(overrides = {}) {
  return {
    gameweekId: "a01GW9",
    name: "2026/27 GW 9",
    gameweekNumber: 9,
    deadline: IN_TWO_DAYS,
    locked: false,
    previousGameweekId: "a01GW8",
    nextGameweekId: "a01GW10",
    fixtures: [
      {
        fixtureId: "a02F1",
        homeTeam: "Arsenal",
        awayTeam: "Chelsea",
        kickoff: IN_TWO_DAYS,
        status: "Scheduled",
        predictedHome: 2,
        predictedAway: 1,
        predictionStatus: "Open"
      },
      {
        fixtureId: "a02F2",
        homeTeam: "Liverpool",
        awayTeam: "Man City",
        kickoff: IN_TWO_DAYS,
        status: "Scheduled"
      }
    ],
    ...overrides
  };
}

/** Lets pending promises and re-renders settle. */
function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function mount() {
  const element = createElement("c-prediction-entry", { is: PredictionEntry });
  document.body.appendChild(element);
  return element;
}

function inputs(element) {
  return [...element.shadowRoot.querySelectorAll("lightning-input")];
}

/** The lightning-input stub has an empty reportValidity(); real fields return true when valid. */
function makeFieldsValid(element) {
  inputs(element).forEach((input) => {
    input.reportValidity = jest.fn(() => true);
  });
}

function changeScore(input, value) {
  input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
}

describe("c-prediction-entry", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a spinner until the gameweek arrives", () => {
    const element = mount();
    expect(
      element.shadowRoot.querySelector("lightning-spinner")
    ).not.toBeNull();
  });

  it("renders the fixtures with existing predictions pre-filled", async () => {
    const element = mount();
    getGameweek.emit(gameweek());
    await flush();

    const names = [...element.shadowRoot.querySelectorAll(".team-name")].map(
      (n) => n.textContent
    );
    expect(names).toEqual(["Arsenal", "Chelsea", "Liverpool", "Man City"]);
    const fields = inputs(element);
    expect(fields).toHaveLength(4);
    expect(fields[0].value).toBe(2);
    expect(fields[1].value).toBe(1);
    expect(fields[2].value).toBeUndefined();
    expect(element.shadowRoot.querySelector(".countdown").textContent).toMatch(
      /^1d 23h left$|^2d 0h left$/
    );
  });

  it("asks Apex for the next open gameweek first, then the one chosen with the arrows", async () => {
    const element = mount();
    // null means "let Apex choose"; the test adapter drops null parameters
    expect(getGameweek.getLastConfig().gameweekId ?? null).toBeNull();

    getGameweek.emit(gameweek());
    await flush();
    element.shadowRoot.querySelector("lightning-button-icon.next").click();
    await flush();

    expect(getGameweek.getLastConfig()).toEqual({ gameweekId: "a01GW10" });
  });

  it("enables Save only after a change, then saves the edited predictions", async () => {
    saveGameweekPredictions.mockResolvedValue(gameweek());
    const toastHandler = jest.fn();
    const element = mount();
    element.addEventListener("lightning__showtoast", toastHandler);
    getGameweek.emit(gameweek());
    await flush();

    const save = element.shadowRoot.querySelector("lightning-button.save");
    expect(save.disabled).toBe(true);

    changeScore(inputs(element)[2], "0");
    changeScore(inputs(element)[3], "3");
    await flush();
    expect(save.disabled).toBe(false);
    expect(element.shadowRoot.querySelector(".unsaved")).not.toBeNull();

    makeFieldsValid(element);
    save.click();
    await flush();

    expect(saveGameweekPredictions).toHaveBeenCalledWith({
      gameweekId: "a01GW9",
      predictions: [{ fixtureId: "a02F2", homeGoals: 0, awayGoals: 3 }]
    });
    expect(refreshApex).toHaveBeenCalled();
    expect(toastHandler).toHaveBeenCalled();
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("success");
  });

  it("shows the Apex error message when saving fails", async () => {
    saveGameweekPredictions.mockRejectedValue({
      body: { message: "The deadline for 2026/27 GW 9 has passed." }
    });
    const toastHandler = jest.fn();
    const element = mount();
    element.addEventListener("lightning__showtoast", toastHandler);
    getGameweek.emit(gameweek());
    await flush();

    changeScore(inputs(element)[0], "4");
    await flush();
    makeFieldsValid(element);
    element.shadowRoot.querySelector("lightning-button.save").click();
    await flush();

    const toast = toastHandler.mock.calls[0][0].detail;
    expect(toast.variant).toBe("error");
    expect(toast.message).toBe("The deadline for 2026/27 GW 9 has passed.");
    expect(refreshApex).not.toHaveBeenCalled();
  });

  it("is read-only once locked, and shows results and points", async () => {
    const element = mount();
    getGameweek.emit(
      gameweek({
        locked: true,
        deadline: YESTERDAY,
        fixtures: [
          {
            fixtureId: "a02F1",
            homeTeam: "Arsenal",
            awayTeam: "Chelsea",
            kickoff: YESTERDAY,
            status: "Finished",
            homeGoals: 2,
            awayGoals: 1,
            predictedHome: 2,
            predictedAway: 1,
            predictionStatus: "Scored",
            points: 8,
            exactScore: true
          }
        ]
      })
    );
    await flush();

    expect(inputs(element).every((input) => input.disabled)).toBe(true);
    expect(
      element.shadowRoot.querySelector("lightning-button.save")
    ).toBeNull();
    expect(element.shadowRoot.querySelector(".locked-text")).not.toBeNull();
    const result = element.shadowRoot.querySelector(".result");
    expect(result.textContent).toContain("Result 2–1");
    expect(result.textContent).toContain("+8");
  });

  it("disables a postponed match", async () => {
    const element = mount();
    const data = gameweek();
    data.fixtures[1].status = "Postponed";
    getGameweek.emit(data);
    await flush();

    const fields = inputs(element);
    expect(fields[0].disabled).toBe(false);
    expect(fields[2].disabled).toBe(true);
    expect(element.shadowRoot.querySelector(".status").textContent).toBe(
      "Postponed"
    );
  });

  it("shows the error when the gameweek can't be loaded", async () => {
    const element = mount();
    getGameweek.error({ message: "Insufficient access" });
    await flush();

    expect(element.shadowRoot.querySelector(".error").textContent).toBe(
      "Insufficient access"
    );
  });

  it("stops its countdown timer when removed from the page", () => {
    const clearSpy = jest.spyOn(window, "clearInterval");
    const element = mount();
    document.body.removeChild(element);
    expect(clearSpy).toHaveBeenCalled();
    clearSpy.mockRestore();
  });
});

describe("formatDuration", () => {
  it("formats days, hours, minutes and seconds", () => {
    expect(formatDuration(2 * 86400000 + 3 * 3600000)).toBe("2d 3h");
    expect(formatDuration(5 * 3600000 + 7 * 60000)).toBe("5h 7m");
    expect(formatDuration(4 * 60000 + 9000)).toBe("4m 9s");
    expect(formatDuration(-1)).toBe("0m");
  });
});

describe("reduceError", () => {
  it("prefers the Apex message", () => {
    expect(reduceError({ body: { message: "From Apex" } })).toBe("From Apex");
    expect(reduceError(new Error("Plain"))).toBe("Plain");
    expect(reduceError(undefined)).toBe("Unknown error");
  });
});

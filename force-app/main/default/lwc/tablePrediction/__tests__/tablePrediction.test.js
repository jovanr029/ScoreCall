import { createElement } from "lwc";
import TablePrediction, { reduceError } from "c/tablePrediction";
import getTablePrediction from "@salesforce/apex/TablePredictionController.getTablePrediction";
import saveTablePrediction from "@salesforce/apex/TablePredictionController.saveTablePrediction";
import { refreshApex } from "@salesforce/apex";
import Toast from "lightning/toast";

jest.mock(
  "@salesforce/apex/TablePredictionController.getTablePrediction",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TablePredictionController.saveTablePrediction",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
const IN_A_WEEK = new Date(Date.now() + 7 * 86400000).toISOString();
const YESTERDAY = new Date(Date.now() - 86400000).toISOString();

function row(teamId, name, shortName, predicted, current, points) {
  return {
    teamId,
    teamName: name,
    shortName,
    predictedPosition: predicted,
    currentPosition: current,
    points
  };
}

const TABLE = [
  row("T1", "Arsenal", "ARS", 1, 1),
  row("T2", "Chelsea", "CHE", 2, 2),
  row("T3", "Liverpool", "LIV", 3, 3)
];

function openView(overrides = {}) {
  return {
    seasonId: "a00S",
    seasonName: "2026/27",
    deadline: IN_A_WEEK,
    isOpen: true,
    isFinished: false,
    hasSaved: false,
    myTable: TABLE,
    players: [],
    ...overrides
  };
}

function closedView() {
  return openView({
    deadline: YESTERDAY,
    isOpen: false,
    hasSaved: true,
    myTable: [
      row("T1", "Arsenal", "ARS", 1, 1, 20),
      row("T2", "Chelsea", "CHE", 2, 3, 15),
      row("T3", "Liverpool", "LIV", 3, 2, 15)
    ],
    players: [
      {
        userId: "005D",
        name: "Dave",
        points: 50,
        isCurrentUser: false,
        rows: [
          row("T3", "Liverpool", "LIV", 1, 2, 15),
          row("T1", "Arsenal", "ARS", 2, 1, 15),
          row("T2", "Chelsea", "CHE", 3, 3, 20)
        ]
      },
      {
        userId: "005C",
        name: "Carol",
        points: 50,
        isCurrentUser: true,
        rows: [
          row("T1", "Arsenal", "ARS", 1, 1, 20),
          row("T2", "Chelsea", "CHE", 2, 3, 15),
          row("T3", "Liverpool", "LIV", 3, 2, 15)
        ]
      }
    ]
  });
}

/**
 * Lets every pending promise and re-render settle. A macrotask (setTimeout 0)
 * runs only after all queued microtasks, however long the save chain is;
 * counting microtask ticks made the save tests flaky when Jest ran files in
 * parallel.
 */
function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount() {
  const element = createElement("c-table-prediction", {
    is: TablePrediction
  });
  document.body.appendChild(element);
  return element;
}

function teamNames(element) {
  return [...element.shadowRoot.querySelectorAll(".team.full")].map(
    (team) => team.textContent
  );
}

describe("c-table-prediction", () => {
  // Spy on the lightning/toast stub the component itself imports. A
  // jest.mock() of the module was flaky: with files running in parallel the
  // component sometimes got the stub and the test checked the mock.
  beforeEach(() => {
    jest.spyOn(Toast, "show").mockImplementation(() => {});
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.restoreAllMocks();
  });

  it("starts from the table Apex gives and can't move past the ends", async () => {
    const element = mount();
    getTablePrediction.emit(openView());
    await flush();

    expect(teamNames(element)).toEqual(["Arsenal", "Chelsea", "Liverpool"]);
    const ups = element.shadowRoot.querySelectorAll(".up");
    const downs = element.shadowRoot.querySelectorAll(".down");
    expect(ups[0].disabled).toBe(true);
    expect(downs[2].disabled).toBe(true);
    expect(element.shadowRoot.querySelector(".save").disabled).toBe(true);
  });

  it("moves teams up and down and saves the new order", async () => {
    saveTablePrediction.mockResolvedValue(openView({ hasSaved: true }));
    const element = mount();
    getTablePrediction.emit(openView());
    await flush();

    // Liverpool up to 2nd, then Arsenal down to 2nd
    element.shadowRoot.querySelectorAll(".up")[2].click();
    await flush();
    expect(teamNames(element)).toEqual(["Arsenal", "Liverpool", "Chelsea"]);
    element.shadowRoot.querySelectorAll(".down")[0].click();
    await flush();
    expect(teamNames(element)).toEqual(["Liverpool", "Arsenal", "Chelsea"]);
    expect(element.shadowRoot.querySelector(".unsaved")).not.toBeNull();

    const save = element.shadowRoot.querySelector(".save");
    expect(save.disabled).toBe(false);
    save.click();
    await flush();

    expect(saveTablePrediction).toHaveBeenCalledWith({
      seasonId: "a00S",
      teamIds: ["T3", "T1", "T2"]
    });
    expect(Toast.show).toHaveBeenCalledWith(
      expect.objectContaining({ variant: "success" }),
      expect.anything()
    );
    expect(refreshApex).toHaveBeenCalled();
  });

  it("shows the Apex refusal when saving fails", async () => {
    saveTablePrediction.mockRejectedValue({
      body: { message: "The table prediction deadline has passed." }
    });
    const element = mount();
    getTablePrediction.emit(openView());
    await flush();

    element.shadowRoot.querySelectorAll(".up")[1].click();
    await flush();
    element.shadowRoot.querySelector(".save").click();
    await flush();

    expect(Toast.show).toHaveBeenCalledWith(
      expect.objectContaining({
        variant: "error",
        message: "The table prediction deadline has passed."
      }),
      expect.anything()
    );
  });

  it("is read-only after the deadline and shows any player's table", async () => {
    const element = mount();
    getTablePrediction.emit(closedView());
    await flush();

    expect(element.shadowRoot.querySelector(".up")).toBeNull();
    expect(element.shadowRoot.querySelector(".save")).toBeNull();
    // The current user's own table first
    expect(teamNames(element)).toEqual(["Arsenal", "Chelsea", "Liverpool"]);
    expect(element.shadowRoot.querySelector(".total").textContent).toBe(
      "Points if it ended today: 50"
    );

    const picker = element.shadowRoot.querySelector(".player-picker");
    expect(picker.options.map((option) => option.label)).toEqual([
      "Dave (50)",
      "Carol (50)"
    ]);
    picker.dispatchEvent(
      new CustomEvent("change", { detail: { value: "005D" } })
    );
    await flush();
    expect(teamNames(element)).toEqual(["Liverpool", "Arsenal", "Chelsea"]);
  });

  it("explains when table predictions aren't open yet", async () => {
    const element = mount();
    getTablePrediction.emit(openView({ deadline: null, isOpen: false }));
    await flush();

    expect(element.shadowRoot.querySelector(".not-open")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".save")).toBeNull();
  });

  it("shows the error when the table can't be loaded", async () => {
    const element = mount();
    getTablePrediction.error({ message: "Insufficient access" });
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

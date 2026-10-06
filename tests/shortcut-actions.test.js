const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const root = path.join(__dirname, "..");
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(root, "ShortcutActions.js"), "utf8"), context);

test("newTask IPC handler connects to the deferred focus path", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8");
  assert.match(panel, /function newTask\(\): void \{ root\.openNewTaskFromHotkey\(\) \}/);
  assert.match(panel, /ShortcutActions\.openNewTask\(root, function\(callback\) \{\s*Qt\.callLater\(callback\)/);
});

test("composer focus retains the unsaved-editor guard", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8");
  const fieldStart = panel.indexOf("id: addField");
  const buttonStart = panel.indexOf("id: addBtnWrap", fieldStart);
  assert.notEqual(fieldStart, -1);
  assert.notEqual(buttonStart, -1);
  const focusHandler = panel.slice(fieldStart, buttonStart);

  assert.match(panel, /function focusNewTaskComposer\(\) \{\s*if \(addField\) addField\.forceActiveFocus\(\)\s*\}/);
  assert.match(focusHandler, /root\.requestCloseEditor\(\{ type: "dismiss", thenCompose: true \}\)/);
  assert.match(focusHandler, /if \(root\.editDirty\) \{\s*[\s\S]*?return\s*\}/);
});

test("new-task action opens Tasks before deferring composer focus", () => {
  const events = [];
  let focusCallback;
  let createdTasks = 0;
  const panel = {
    viewMode: "about",
    openFromHotkey() { events.push("open"); },
    focusNewTaskComposer() { events.push("focus"); },
    addTask() { createdTasks++; },
  };

  context.openNewTask(panel, (callback) => {
    events.push("defer");
    focusCallback = callback;
  });

  assert.equal(panel.viewMode, "tasks");
  assert.deepEqual(events, ["open", "defer"]);
  assert.equal(createdTasks, 0);

  focusCallback();
  assert.deepEqual(events, ["open", "defer", "focus"]);
  assert.equal(createdTasks, 0);
});

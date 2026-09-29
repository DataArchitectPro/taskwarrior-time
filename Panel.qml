import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "i18n.js" as I18n

Panel {
  id: root
  moduleName: "taskwarrior-time"
  ipcTarget: "taskwarrior-time"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var snapshot: ({
    ok: true,
    available: true,
    tasks: [],
    projects: [],
    pending: 0,
    actionable: 0,
    active: null,
    label: "\uf0ae",
    tooltip: "",
    waiting: 0
  })

  property string viewMode: "tasks" // tasks | projects | about
  property string groupBy: setting("defaultGroupBy", "project")
  property string expandedUuid: ""
  property string pendingDeleteUuid: ""
  property string pendingClearProject: ""
  property string projectFilter: ""
  property int cursorIndex: -1
  property bool cursorActive: false
  property string busyUuid: ""
  property string lastError: ""

  property bool formFocused: false
  property bool showFilterPanel: false
  property int datePickerCount: 0

  // Survives ListView delegate teardown. Flat strings — QML `var` maps
  // are unreliable across snapshot swaps after deps/status mutations.
  property string editUuid: ""
  property string editDescription: ""
  property string editDetails: ""
  property string editWaitingFor: ""
  property string editOutcome: ""
  property string editPriority: ""
  property string editProject: ""
  property string editScheduled: ""
  property string editDue: ""
  property bool editActive: false
  property string editBaselineJson: ""
  property var pendingEditorClose: null
  property string pendingEditorReseedUuid: ""
  property var _cmdQueue: []
  property bool debugLogging: false
  property string debugLogPath: ""
  property string debugSessionId: ""
  property string uiLanguage: "system" // system | ru | en
  property var _logQueue: []
  property bool _logFlushScheduled: false
  readonly property string pluginVersion: "1.0.2"
  readonly property string githubUrl: "https://github.com/DataArchitectPro/taskwarrior-time"
  readonly property string changelogUrl: "https://github.com/DataArchitectPro/taskwarrior-time/blob/master/CHANGELOG.md"
  readonly property string newIssueUrl: "https://github.com/DataArchitectPro/taskwarrior-time/issues/new"
  readonly property string marketplaceUrl: "https://plugins.omarchy.org/plugin.html?id=taskwarrior-time"

  readonly property bool editDirty: {
    // Touch every draft field so the binding re-evaluates on edits.
    var _ = root.editDescription + "\n" + root.editDetails + "\n" + root.editWaitingFor
      + "\n" + root.editOutcome + "\n" + root.editPriority + "\n" + root.editProject
      + "\n" + root.editScheduled + "\n" + root.editDue
    if (!root.editActive || !root.editBaselineJson) return false
    return JSON.stringify(root.editValues()) !== root.editBaselineJson
  }

  function refreshEditBaseline() {
    root.editBaselineJson = JSON.stringify(root.editValues())
  }

  function beginEditFromTask(task) {
    if (!task || !task.uuid) return
    root.editUuid = String(task.uuid)
    root.editDescription = task.description || ""
    root.editDetails = String(task.details || "")
    root.editWaitingFor = task.waitingFor || ""
    root.editOutcome = task.outcome || ""
    root.editPriority = task.priority || ""
    root.editProject = task.project || ""
    root.editScheduled = Model.formatEditableDateTime(task.scheduled)
    root.editDue = Model.formatEditableDateTime(task.due)
    root.editActive = true
    root.refreshEditBaseline()
  }

  function clearEditBuffer() {
    root.editUuid = ""
    root.editDescription = ""
    root.editDetails = ""
    root.editWaitingFor = ""
    root.editOutcome = ""
    root.editPriority = ""
    root.editProject = ""
    root.editScheduled = ""
    root.editDue = ""
    root.editActive = false
    root.editBaselineJson = ""
  }

  function editValues() {
    return {
      description: root.editDescription,
      details: root.editDetails,
      waitingFor: root.editWaitingFor,
      outcome: root.editOutcome,
      priority: root.editPriority,
      project: root.editProject,
      scheduled: root.editScheduled,
      due: root.editDue
    }
  }

  function writeEditValues(values) {
    root.editDescription = values.description || ""
    root.editDetails = values.details || ""
    root.editWaitingFor = values.waitingFor || ""
    root.editOutcome = values.outcome || ""
    root.editPriority = values.priority || ""
    root.editProject = values.project || ""
    root.editScheduled = values.scheduled || ""
    root.editDue = values.due || ""
    root.editActive = true
  }

  // Bumped after every snapshot apply so the open editor re-applies the
  // buffer once the new ListView delegate exists.
  property int editRestoreSeq: 0
  property bool editGuard: false
  // Keep the task list scrolled where the user left it across snapshot
  // swaps only when the row model must be replaced (add/delete/reorder).
  property real _preserveContentY: -1
  property int dataRev: 0
  property var rows: []
  // After a done/undone toggle, keep the task visible briefly so the user
  // sees the new checkbox/strike state even if the filter would hide it.
  property var doneHoldUntil: ({})
  readonly property int doneHoldMs: 1800
  // Theme accent (follows Omarchy / OS theme), same as other active UI chrome.
  readonly property color doneCheckColor: Color.accent
  readonly property real doneCheckSize: Style.font.title * 2.15
  // Priority colors from the active Omarchy theme palette (colors.toml),
  // same source Color.urgent / accent use — so they track OS theme switches.
  // High=red, Mid=green, Low=blue. Due chips: today=orange, tomorrow=yellow.
  property color themeRed: Color.urgent
  property color themeGreen: Color.accent
  property color themeBlue: Color.accent
  property color themeOrange: Color.accent
  property color themeYellow: Color.accent
  readonly property color priorityHighColor: root.themeRed
  readonly property color priorityMiddleColor: root.themeGreen
  readonly property color priorityLowColor: root.themeBlue

  function priorityColor(priority) {
    if (priority === "H") return root.priorityHighColor
    if (priority === "M") return root.priorityMiddleColor
    if (priority === "L") return root.priorityLowColor
    return root.dim
  }

  function dueMetaColor(task) {
    if (!task) return root.dim
    var bucket = Model.dueBucket(task)
    if (bucket === "overdue") return root.urgent
    if (bucket === "today") return root.themeOrange
    if (bucket === "tomorrow") return root.themeYellow
    return root.dim
  }

  // Meta strip = table columns (project flex + fixed badge tracks). Empty
  // slots keep their width so priority/due/blocked never shift across rows.
  FontMetrics {
    id: metaCaptionMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
  FontMetrics {
    id: metaPriMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }
  function metaTextWidth(metrics, text) {
    return Math.ceil(metrics.boundingRect(String(text || "")).width)
  }
  readonly property real metaPriWidth: Math.max(
    root.metaTextWidth(metaPriMetrics, root.tr("priH")),
    root.metaTextWidth(metaPriMetrics, root.tr("priM")),
    root.metaTextWidth(metaPriMetrics, root.tr("priL"))
  )
  readonly property real metaDueWidth: Math.max(
    root.metaTextWidth(metaCaptionMetrics, root.tr("dueOverdue")),
    root.metaTextWidth(metaCaptionMetrics, root.tr("dueToday")),
    root.metaTextWidth(metaCaptionMetrics, root.tr("dueTomorrow")),
    root.metaTextWidth(metaCaptionMetrics, "00.00.0000")
  )
  readonly property real metaBlockedWidth: root.metaTextWidth(metaCaptionMetrics, root.tr("blocked"))

  function applyThemePalette(raw) {
    var red = ""
    var green = ""
    var blue = ""
    var orange = ""
    var yellow = ""
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      var key = match[1]
      var val = match[2]
      if (key === "red" || key === "color1") red = val
      else if (key === "green" || key === "color2") green = val
      else if (key === "blue" || key === "color4") blue = val
      else if (key === "orange") orange = val
      else if (key === "yellow" || key === "color3") yellow = val
    }
    root.themeRed = red || Color.urgent
    root.themeGreen = green || Color.accent
    root.themeBlue = blue || Color.accent
    root.themeOrange = orange || yellow || Color.accent
    root.themeYellow = yellow || orange || Color.accent
  }

  FileView {
    id: themeColorsFile
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyThemePalette(text())
    onFileChanged: reload()
    onLoadFailed: root.applyThemePalette("")
  }

  // Theme switches push colors.toml via shell IPC into Color (FileView there
  // is startup-only). Reload our palette whenever foundational roles change.
  Connections {
    target: Color
    function onUrgentChanged() { themeColorsFile.reload() }
    function onAccentChanged() { themeColorsFile.reload() }
    function onForegroundChanged() { themeColorsFile.reload() }
  }

  function isDoneHoldActive(uuid) {
    var until = root.doneHoldUntil[String(uuid || "")]
    return !!(until && Date.now() < until)
  }

  function markDoneHold(uuid) {
    var id = String(uuid || "")
    if (!id) return
    var next = {}
    var cur = root.doneHoldUntil || {}
    for (var k in cur)
      next[k] = cur[k]
    next[id] = Date.now() + root.doneHoldMs
    root.doneHoldUntil = next
    if (doneHoldTimer)
      doneHoldTimer.restart()
  }

  function clearDoneHold(uuid) {
    var id = String(uuid || "")
    var cur = root.doneHoldUntil || {}
    if (!cur[id]) return
    var next = {}
    for (var k in cur)
      if (k !== id) next[k] = cur[k]
    root.doneHoldUntil = next
  }

  function sweepDoneHolds() {
    var now = Date.now()
    var cur = root.doneHoldUntil || {}
    var next = {}
    var expired = false
    for (var k in cur) {
      if (cur[k] > now)
        next[k] = cur[k]
      else
        expired = true
    }
    if (!expired) {
      var any = false
      for (var _ in next) { any = true; break }
      if (!any && doneHoldTimer)
        doneHoldTimer.stop()
      return
    }
    root.doneHoldUntil = next
    root.rebuildRows(true)
    var left = false
    for (var __ in next) { left = true; break }
    if (!left && doneHoldTimer)
      doneHoldTimer.stop()
  }

  function applyLocalTaskStatus(uuid, status) {
    var id = String(uuid || "")
    if (!id) return
    function patch(t) {
      if (!t || String(t.uuid) !== id) return
      t.status = status
      if (status === "completed")
        t.timerActive = false
    }
    var tasks = (root.snapshot && root.snapshot.tasks) ? root.snapshot.tasks : []
    for (var i = 0; i < tasks.length; i++)
      patch(tasks[i])
    for (var r = 0; r < root.rows.length; r++) {
      if (root.rows[r] && root.rows[r].type === "task")
        patch(root.rows[r].task)
    }
    root.dataRev++
  }

  function requestEditorRestore() {
    if (!root.editActive || !root.expandedUuid) return
    if (root.editUuid !== String(root.expandedUuid)) return
    root.editRestoreSeq++
  }

  function restoreListScroll() {
    if (root._preserveContentY < 0) return
    var y = root._preserveContentY
    function apply() {
      if (!listView) return
      var maxY = Math.max(0, listView.contentHeight - listView.height)
      listView.contentY = Math.min(Math.max(0, y), maxY)
    }
    apply()
    Qt.callLater(apply)
  }

  function currentFilterSpec() {
    // Build a fresh object from live properties — do not read `filterSpec`
    // from change handlers; QML may still hold a stale binding object.
    return {
      status: root.filterStatus,
      project: root.projectFilter,
      priority: root.filterPriority,
      due: root.filterDue,
      search: root.filterSearch,
      blocked: root.filterBlocked,
      timer: root.filterTimer
    }
  }

  function rebuildRows(forceReplace) {
    var tasks = (root.snapshot && root.snapshot.tasks) ? root.snapshot.tasks : []
    var spec = root.currentFilterSpec()
    var filtered = []
    for (var i = 0; i < tasks.length; i++) {
      var task = tasks[i]
      if (Model.matchesAdvanced(task, spec))
        filtered.push(task)
      else if (task && root.isDoneHoldActive(task.uuid))
        filtered.push(task)
    }
    var next = Model.flattenRows(Model.buildGroups(filtered, "pass", root.groupBy, root.tr))
    if (!forceReplace && root.rows.length > 0 && Model.patchRowsInPlace(root.rows, next)) {
      // Same structure — mutate tasks in place so ListView keeps delegates
      // and scroll position (no jump on save / deps).
      root.dataRev++
      return false
    }
    // Two-step assign so ListView always notices the model change (JS array
    // replacement is unreliable when going empty→non-empty in one shot).
    root.rows = []
    root.rows = next
    root.dataRev++
    return true
  }

  // Advanced filter (defaults ≈ former "All" = open pending/waiting)
  property string filterStatus: "open"   // all|open|pending|waiting|completed|active
  property string filterPriority: ""     // "" | H|M|L|__none__
  property string filterDue: ""          // "" | overdue|today|week|later|none|soon
  property string filterSearch: ""
  property string filterBlocked: ""      // "" | blocked|blocking|clear
  property string filterTimer: ""        // "" | running|idle

  // Add form
  property string addDescription: ""
  property string addPriority: ""
  property string addProject: ""
  property string addScheduled: ""
  property string addDue: ""
  property string addStatus: "waiting"
  property string addWaitingFor: ""
  property var addDepUuids: []
  property bool addStartTimer: false
  property bool showAddAdvanced: false
  property bool composerExpanded: false
  property bool showAddExtras: false // legacy alias — unused

  function collapseComposer() {
    root.composerExpanded = false
    root.showAddAdvanced = false
    if (addField && addField.activeFocus)
      addField.focus = false
  }

  function collapseFilterPanel() {
    root.showFilterPanel = false
  }

  function collapseExpandedTask() {
    root.requestCloseEditor({ type: "dismiss" })
  }

  function requestCloseEditor(action) {
    action = action || { type: "dismiss" }
    if (!root.expandedUuid) {
      root.applyEditorClose(action)
      return
    }
    if (!root.editDirty) {
      root.applyEditorClose(action)
      return
    }
    root.pendingEditorClose = action
    confirmUnsaved.selectedIndex = 0
    confirmUnsaved.opened = true
  }

  function applyEditorClose(action) {
    action = action || { type: "dismiss" }
    root.pendingEditorClose = null
    if (confirmUnsaved) confirmUnsaved.opened = false

    if (action.type === "switch" && action.uuid) {
      root.expandedUuid = String(action.uuid)
      return
    }

    root.expandedUuid = ""
    root.clearEditBuffer()

    if (action.thenCompose) {
      root.composerExpanded = true
      Qt.callLater(function () {
        if (addField) addField.forceActiveFocus()
      })
    }
    if (action.thenHide)
      root.controller.hide()
  }

  function confirmUnsavedSave() {
    var act = root.pendingEditorClose || { type: "dismiss" }
    confirmUnsaved.opened = false
    root.pendingEditorClose = null
    var uuid = root.editUuid || root.expandedUuid
    if (!uuid) {
      root.applyEditorClose(act)
      return
    }
    var task = null
    for (var i = 0; i < root.rows.length; i++) {
      if (root.rows[i] && root.rows[i].type === "task" && root.rows[i].task
          && String(root.rows[i].task.uuid) === String(uuid)) {
        task = root.rows[i].task
        break
      }
    }
    if (!task)
      task = Model.findTask((root.snapshot && root.snapshot.tasks) || [], uuid)
    if (!task) {
      root.applyEditorClose(act)
      return
    }
    var v = root.editValues()
    root.pendingEditorClose = act
    root.saveTask(task, v.description, v.project, v.priority, v.scheduled, v.due, v.details)
    var follow = root.pendingEditorClose
    root.pendingEditorClose = null
    if (follow && follow.type === "switch" && follow.uuid)
      root.expandedUuid = String(follow.uuid)
    else if (follow && follow.thenCompose) {
      root.composerExpanded = true
      Qt.callLater(function () {
        if (addField) addField.forceActiveFocus()
      })
    } else if (follow && follow.thenHide) {
      root.controller.hide()
    }
  }

  function confirmUnsavedContinue() {
    confirmUnsaved.opened = false
    root.pendingEditorClose = null
    if (addField && addField.activeFocus)
      addField.focus = false
  }

  function confirmUnsavedDiscard() {
    var act = root.pendingEditorClose || { type: "dismiss" }
    confirmUnsaved.opened = false
    root.pendingEditorClose = null
    root.clearEditBuffer()
    root.applyEditorClose(act)
  }

  function dismissOverlays() {
    root.collapseFilterPanel()
    root.collapseComposer()
    root.collapseExpandedTask()
  }

  // Close the innermost transient UI on Escape. Returns true if something
  // was dismissed (caller should not close the whole panel).
  function dismissEscapeOverlay() {
    if (confirmUnsaved && confirmUnsaved.opened) return false
    if (confirmDelete && confirmDelete.opened) return false
    if (confirmClear && confirmClear.opened) return false

    function closePicker(field) {
      if (field && field.popupOpen) {
        field.discardPicker()
        return true
      }
      return false
    }
    // Only top-level date fields — delegate ids collide with editScheduled/editDue strings.
    if (closePicker(addScheduledField) || closePicker(addDueField))
      return true

    function closeDropdown(dd) {
      if (dd && typeof dd.close === "function" && dd.popupOpen) {
        dd.close()
        return true
      }
      return false
    }
    if (closeDropdown(groupDropdown)
        || closeDropdown(filterStatusDropdown)
        || closeDropdown(projectFilterDropdown)
        || closeDropdown(filterPriorityDropdown)
        || closeDropdown(filterDueDropdown)
        || closeDropdown(filterTimerDropdown)
        || closeDropdown(filterBlockedDropdown)
        || closeDropdown(priorityCombo)
        || closeDropdown(projectCombo)
        || closeDropdown(addDepCombo)) {
      return true
    }

    if (root.renameFrom !== "") {
      root.cancelRenameProject()
      root._refocusKeyCatcher()
      return true
    }
    if (root.showFilterPanel) {
      root.collapseFilterPanel()
      root._refocusKeyCatcher()
      return true
    }
    if (root.composerExpanded) {
      root.collapseComposer()
      root._refocusKeyCatcher()
      return true
    }
    if (root.expandedUuid) {
      root.collapseExpandedTask()
      root._refocusKeyCatcher()
      return true
    }
    return false
  }

  function _refocusKeyCatcher() {
    root.formFocused = false
    Qt.callLater(function () {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function escapeFromField(event) {
    if (root.dismissEscapeOverlay())
      event.accepted = true
  }

  // Uniform action hotkeys across editor / composer / confirm dialogs:
  //   Ctrl+Enter  — commit (save / add / confirm)
  //   Esc         — cancel (already via dismissEscapeOverlay)
  //   Ctrl+Delete — destroy (delete task / discard unsaved)
  readonly property string hkHintCommit: " · Ctrl+Enter"
  readonly property string hkHintCancel: " · Esc"
  readonly property string hkHintDestroy: " · Ctrl+Delete"
  readonly property bool anyConfirmOpen: !!(
    (confirmUnsaved && confirmUnsaved.opened)
    || (confirmDelete && confirmDelete.opened)
    || (confirmClear && confirmClear.opened)
  )

  function findTaskByUuid(uuid) {
    uuid = String(uuid || "")
    if (!uuid) return null
    for (var i = 0; i < root.rows.length; i++) {
      var row = root.rows[i]
      if (row && row.type === "task" && row.task && String(row.task.uuid) === uuid)
        return row.task
    }
    return Model.findTask((root.snapshot && root.snapshot.tasks) || [], uuid)
  }

  function hotkeyCommit() {
    if (confirmUnsaved && confirmUnsaved.opened) {
      root.confirmUnsavedSave()
      return
    }
    if (confirmDelete && confirmDelete.opened) {
      root.confirmDeleteTask()
      return
    }
    if (confirmClear && confirmClear.opened) {
      root.confirmClearProjectAction()
      return
    }
    if (root.renameFrom !== "") {
      root.renameProject()
      return
    }
    if (root.expandedUuid) {
      if (!root.editDirty) return
      var task = root.findTaskByUuid(root.expandedUuid)
      if (!task) return
      var v = root.editValues()
      root.saveTask(task, v.description, v.project, v.priority, v.scheduled, v.due, v.details)
      return
    }
    if (root.composerExpanded) {
      root.addTask()
      return
    }
    if (root.viewMode === "projects" && newProjectField
        && String(newProjectField.text || "").trim() !== "") {
      root.createProjectName()
    }
  }

  function hotkeyDestroy() {
    if (confirmUnsaved && confirmUnsaved.opened) {
      root.confirmUnsavedDiscard()
      return
    }
    if (confirmDelete && confirmDelete.opened) {
      root.confirmDeleteTask()
      return
    }
    if (confirmClear && confirmClear.opened) {
      root.confirmClearProjectAction()
      return
    }
    if (root.expandedUuid) {
      var task = root.findTaskByUuid(root.expandedUuid)
      if (task) root.requestDelete(task)
    }
  }

  function hotkeyCancelConfirm() {
    if (confirmUnsaved && confirmUnsaved.opened) {
      root.confirmUnsavedContinue()
      return
    }
    if (confirmDelete && confirmDelete.opened) {
      confirmDelete.opened = false
      root.pendingDeleteUuid = ""
      return
    }
    if (confirmClear && confirmClear.opened) {
      confirmClear.opened = false
      root.pendingClearProject = ""
    }
  }

  function maybeCollapseComposer() {
    Qt.callLater(function () {
      if (!root.composerExpanded) return
      // Still interacting with the create form (fields, dropdowns, calendars).
      if (composerScope && composerScope.activeFocus) return
      if (root.datePickerCount > 0) return
      if (priorityCombo && priorityCombo.popupOpen) return
      if (projectCombo && projectCombo.popupOpen) return
      if (addDepCombo && addDepCombo.popupOpen) return
      if (addScheduledField && addScheduledField.fieldFocused) return
      if (addDueField && addDueField.fieldFocused) return
      if (addField && addField.activeFocus) return
      if (addDetailsField && addDetailsField.activeFocus) return
      if (addWaitingForField && addWaitingForField.activeFocus) return
      if (addOutcomeField && addOutcomeField.activeFocus) return
      root.collapseComposer()
    })
  }

  onExpandedUuidChanged: {
    if (root.expandedUuid) {
      root.showFilterPanel = false
      root.collapseComposer()
    } else {
      root.formFocused = false
    }
  }

  onComposerExpandedChanged: {
    if (root.composerExpanded)
      root.showFilterPanel = false
    else
      root.formFocused = false
  }

  onShowFilterPanelChanged: {
    if (root.showFilterPanel) {
      root.collapseComposer()
      root.collapseExpandedTask()
    } else {
      root.formFocused = false
    }
  }

  onViewModeChanged: {
    root.collapseFilterPanel()
    root.collapseComposer()
    root.collapseExpandedTask()
    root.cancelRenameProject()
  }


  // Project form
  property string newProjectName: ""
  property string renameFrom: ""
  property string renameTo: ""

  readonly property string localeName: {
    var loc = Qt.locale()
    if (loc && loc.uiLanguages && loc.uiLanguages.length > 0)
      return String(loc.uiLanguages[0])
    return loc ? String(loc.name || "") : ""
  }
  function tr(key) { return I18n.t(key, root.localeName, root.uiLanguage) }

  readonly property bool uiRussian: {
    if (root.uiLanguage === "ru") return true
    if (root.uiLanguage === "en") return false
    var loc = String(root.localeName || "").toLowerCase().replace(/-/g, "_")
    var lang = loc.split(".")[0].split("_")[0]
    return lang === "ru"
  }
  // Prefer i18n; if a stale module still returns an old title, override.
  readonly property string tasksHeaderTitle: {
    var s = root.tr("titleInProgress")
    if (s === "titleInProgress" || s === "Tasks in progress" || s === "Задачи в работе" || s === "Tasks")
      return "Taskwarrior Time"
    return s
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string helperPath: {
    var value = String(Qt.resolvedUrl("bin/taskwarrior-time"))
    if (value.indexOf("file://") === 0) return decodeURIComponent(value.substring(7))
    return value
  }

  // projectFilter: "" = all; "__none__" = no project; else project name
  readonly property var projectList: (snapshot && snapshot.projects) ? snapshot.projects : []

  readonly property var filterSpec: ({
    status: root.filterStatus,
    project: root.projectFilter,
    priority: root.filterPriority,
    due: root.filterDue,
    search: root.filterSearch,
    blocked: root.filterBlocked,
    timer: root.filterTimer
  })

  readonly property int activeFilterCount: Model.countActiveFilters(root.filterSpec)

  readonly property bool filterStatusActive: root.filterStatus !== "open"
  readonly property bool filterProjectActive: root.projectFilter !== ""
  readonly property bool filterPriorityActive: root.filterPriority !== ""
  readonly property bool filterDueActive: root.filterDue !== ""
  readonly property bool filterTimerActive: root.filterTimer !== ""
  readonly property bool filterBlockedActive: root.filterBlocked !== ""
  readonly property bool filterSearchActive: String(root.filterSearch || "").trim() !== ""
  readonly property color filterActiveColor: Color.accent
  readonly property color filterIdleLabelColor: root.dim

  function filterFieldFill(active) {
    return active ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
  }

  readonly property var filteredTasks: {
    var _ = root.dataRev
    var tasks = (root.snapshot && root.snapshot.tasks) ? root.snapshot.tasks : []
    var spec = root.currentFilterSpec()
    var out = []
    for (var i = 0; i < tasks.length; i++) {
      if (Model.matchesAdvanced(tasks[i], spec)) out.push(tasks[i])
    }
    return out
  }

  function setProjectFilter(value) {
    var next = (value === "__all__" || value === undefined || value === null) ? "" : String(value)
    root.projectFilter = next
    if (projectFilterDropdown)
      projectFilterDropdown.value = next
  }

  function clearAdvancedFilters() {
    root.filterStatus = "open"
    root.filterPriority = ""
    root.filterDue = ""
    root.filterSearch = ""
    root.filterBlocked = ""
    root.filterTimer = ""
    root.setProjectFilter("")
    if (filterStatusDropdown) filterStatusDropdown.value = "open"
    if (filterPriorityDropdown) filterPriorityDropdown.value = ""
    if (filterDueDropdown) filterDueDropdown.value = ""
    if (filterBlockedDropdown) filterBlockedDropdown.value = ""
    if (filterTimerDropdown) filterTimerDropdown.value = ""
    if (filterSearchField) filterSearchField.text = ""
  }

  onProjectFilterChanged: {
    if (projectFilterDropdown && projectFilterDropdown.value !== root.projectFilter)
      projectFilterDropdown.value = root.projectFilter
    Qt.callLater(function () { root.rebuildRows(true) })
  }
  onGroupByChanged: root.rebuildRows(true)
  onFilterStatusChanged: Qt.callLater(function () { root.rebuildRows(true) })
  onFilterPriorityChanged: Qt.callLater(function () { root.rebuildRows(true) })
  onFilterDueChanged: Qt.callLater(function () { root.rebuildRows(true) })
  onFilterSearchChanged: Qt.callLater(function () { root.rebuildRows(true) })
  onFilterBlockedChanged: Qt.callLater(function () { root.rebuildRows(true) })
  onFilterTimerChanged: Qt.callLater(function () { root.rebuildRows(true) })

  readonly property var projectFilterOptions: {
    var opts = [
      { value: "", label: root.tr("allProjects") },
      { value: "__none__", label: root.tr("projectNone") }
    ]
    for (var i = 0; i < root.projectList.length; i++)
      opts.push({ value: root.projectList[i], label: root.projectList[i] })
    return opts
  }

  readonly property string label: snapshot && snapshot.label ? snapshot.label : "\uf0ae"

  function open() {
    root.controller.show()
    refresh()
  }

  function openFromHotkey() {
    root.controller.show()
    refresh()
  }

  function close() {
    confirmDelete.opened = false
    confirmClear.opened = false
    if (confirmUnsaved) confirmUnsaved.opened = false
    root.pendingEditorClose = null
    root.collapseComposer()
    // Closing the panel discards the open editor; ask if dirty.
    if (root.expandedUuid && root.editDirty) {
      root.pendingEditorClose = { type: "dismiss", thenHide: true }
      confirmUnsaved.selectedIndex = 0
      confirmUnsaved.opened = true
      return
    }
    root.expandedUuid = ""
    root.clearEditBuffer()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Mirror helper MAX_PAYLOAD_BYTES so QML never keeps an oversized snapshot.
  readonly property int maxSnapshotChars: 1800000

  function applyData(text) {
    try {
      var raw = String(text || "")
      if (raw.length > root.maxSnapshotChars) {
        root.lastError = "snapshot exceeds size limit"
        root.dlog("snapshot.reject", { bytes: raw.length, limit: root.maxSnapshotChars }, "error")
        root.editGuard = false
        return
      }
      var data = JSON.parse(raw || "{}")
      var reseedUuid = root.pendingEditorReseedUuid
      root.pendingEditorReseedUuid = ""
      if (listView)
        root._preserveContentY = listView.contentY
      root.editGuard = true
      root.snapshot = data
      root.lastError = data.error ? String(data.error) : ""
      // Always replace when the list was empty so the first export after
      // startup reliably populates ListView.
      var replaced = root.rebuildRows(root.rows.length === 0)
      var expandedTask = root.expandedUuid
        ? Model.findTask((data.tasks || []), root.expandedUuid)
        : null
      root.dlog("snapshot.apply", {
        replaced: replaced,
        reseed: !!reseedUuid,
        tasks: (data.tasks && data.tasks.length) || 0,
        pending: data.pending,
        waiting: data.waiting,
        ok: data.ok !== false,
        available: !!data.available,
        timewAvailable: !!data.timewAvailable,
        error: root.lastError,
        viewMode: root.viewMode,
        groupBy: root.groupBy,
        pluginVersion: root.pluginVersion,
        expandedUuid: root.expandedUuid,
        expandedDepends: expandedTask ? Model.toJsArray(expandedTask.depends) : []
      }, root.lastError ? "warn" : "info")
      if (!replaced)
        root._preserveContentY = -1
      if (reseedUuid) {
        var saved = Model.findTask(data.tasks || [], reseedUuid)
        if (saved)
          root.beginEditFromTask(saved)
      }
      Qt.callLater(function () {
        if (replaced || reseedUuid)
          root.requestEditorRestore()
        root.editGuard = false
        if (replaced) {
          Qt.callLater(function () {
            root.restoreListScroll()
            root._preserveContentY = -1
          })
        }
      })
    } catch (e) {
      root.editGuard = false
      root._preserveContentY = -1
      root.lastError = String(e)
      root.dlog("snapshot.error", { error: String(e), pluginVersion: root.pluginVersion }, "error")
      console.warn("taskwarrior-time: bad JSON", e)
    }
  }

  function refresh() {
    // Don't contend with an in-flight mutation for the Taskwarrior lock.
    if (cmdProc.running || exportProc.running) return
    exportProc.command = [root.helperPath, "export"]
    exportProc.running = true
  }

  function runCmd(args) {
    // Serialize against exportProc — Taskwarrior file locks make parallel
    // `task` invocations appear to hang for seconds.
    if (cmdProc.running || exportProc.running) {
      root._cmdQueue = (root._cmdQueue || []).concat([args])
      root.dlog("cmd.queue", {
        args: root._safeArgs(args),
        queueLen: root._cmdQueue.length,
        cmdRunning: !!cmdProc.running,
        exportRunning: !!exportProc.running
      })
      return
    }
    root.dlog("cmd.start", { args: root._safeArgs(args) })
    root._cmdStartedAt = Date.now()
    cmdProc.command = [root.helperPath].concat(args)
    cmdProc.running = true
  }

  property real _cmdStartedAt: 0

  function _safeArgs(args) {
    // Never put free-text task descriptions in the debug log — only flags,
    // UUIDs, and known helper verbs. Length is enough to debug hangs.
    var verbs = {
      add: 1, mod: 1, done: 1, delete: 1, start: 1, stop: 1, export: 1,
      projects: 1, "ui-settings": 1, "debug-log": 1, "extra-projects": 1,
      version: 1, env: 1
    }
    var out = []
    for (var i = 0; i < args.length; i++) {
      var a = String(args[i])
      if (a.startsWith("-") || verbs[a]) {
        out.push(a.length > 80 ? a.slice(0, 40) + "…(" + a.length + ")" : a)
      } else if (/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(a) || /^[0-9a-f]{8}$/i.test(a)) {
        out.push(a)
      } else {
        out.push("<text:" + a.length + ">")
      }
    }
    return out
  }

  function dlog(event, detail, level) {
    if (!root.debugLogging) return
    var payload = detail && typeof detail === "object" ? detail : {}
    var lvl = String(level || "info").toLowerCase()
    if (lvl !== "debug" && lvl !== "info" && lvl !== "warn" && lvl !== "error")
      lvl = "info"
    root._logQueue = (root._logQueue || []).concat([{
      event: String(event || "log"),
      level: lvl,
      json: JSON.stringify(payload)
    }])
    if (!root._logFlushScheduled) {
      root._logFlushScheduled = true
      Qt.callLater(root._flushLogQueue)
    }
  }

  function _flushLogQueue() {
    root._logFlushScheduled = false
    if (!root.debugLogging) {
      root._logQueue = []
      return
    }
    if (debugLogProc.running) {
      root._logFlushScheduled = true
      Qt.callLater(root._flushLogQueue)
      return
    }
    var q = root._logQueue
    if (!q || !q.length) return
    var item = q[0]
    root._logQueue = q.slice(1)
    debugLogProc.command = [
      root.helperPath, "debug-log",
      "--event", item.event,
      "--level", item.level || "info",
      "--component", "ui",
      "--json", item.json
    ]
    debugLogProc.running = true
  }

  function setDebugLogging(on) {
    var enabled = !!on
    settingsSetProc.command = [
      root.helperPath, "settings-set",
      enabled ? "--debug-logging" : "--no-debug-logging"
    ]
    settingsSetProc.running = true
  }

  function debugLogDir() {
    var p = String(root.debugLogPath || "").trim()
    if (p) {
      var slash = p.lastIndexOf("/")
      if (slash > 0)
        return p.substring(0, slash)
    }
    var home = ""
    try { home = String(Quickshell.env("HOME") || "") } catch (e) { home = "" }
    return (home || ".") + "/.local/share/taskwarrior-time"
  }

  function openDebugLogFolder() {
    var dir = root.debugLogDir()
    // Omarchy apps must go through uwsm-app; plain xdg-open often fails from
    // the shell process, and xdg-open rejects a "--" end-of-options marker.
    Quickshell.execDetached([
      "bash", "-lc",
      'mkdir -p -- "$1" && exec setsid uwsm-app -- nautilus --new-window "$1"',
      "taskwarrior-time-open-log-dir",
      dir
    ])
  }

  function clearDebugLogs() {
    Quickshell.execDetached([root.helperPath, "debug-log-clear"])
  }

  function setUiLanguage(lang) {
    var next = String(lang || "system")
    if (next !== "system" && next !== "ru" && next !== "en")
      next = "system"
    root.uiLanguage = next
    settingsSetProc.command = [
      root.helperPath, "settings-set",
      "--ui-language", next
    ]
    settingsSetProc.running = true
  }

  function loadDebugSettings() {
    if (settingsGetProc.running) return
    settingsGetProc.command = [root.helperPath, "settings-get"]
    settingsGetProc.running = true
  }

  function _drainCmdQueue() {
    if (cmdProc.running || exportProc.running) return
    var q = root._cmdQueue
    if (!q || !q.length) return
    var next = q[0]
    root._cmdQueue = q.slice(1)
    cmdProc.command = [root.helperPath].concat(next)
    cmdProc.running = true
  }

  // Instant UI update for depends/blocks; server sync follows via runCmd.
  function mutateDepLinks(selfUuid, otherUuid, add) {
    selfUuid = String(selfUuid || "")
    otherUuid = String(otherUuid || "")
    if (!selfUuid || !otherUuid) return

    function applyToTask(t) {
      if (!t || !t.uuid) return
      var u = String(t.uuid)
      if (u === selfUuid) {
        var deps = Model.toJsArray(t.depends)
        var has = Model.listContains(deps, otherUuid)
        if (add && !has) deps.push(otherUuid)
        if (!add && has) {
          var nd = []
          for (var i = 0; i < deps.length; i++)
            if (String(deps[i]) !== otherUuid) nd.push(deps[i])
          deps = nd
        }
        t.depends = deps
        t.blocked = deps.length > 0
      }
      if (u === otherUuid) {
        var blocks = Model.toJsArray(t.blocks)
        var hasB = Model.listContains(blocks, selfUuid)
        if (add && !hasB) blocks.push(selfUuid)
        if (!add && hasB) {
          var nb = []
          for (var j = 0; j < blocks.length; j++)
            if (String(blocks[j]) !== selfUuid) nb.push(blocks[j])
          blocks = nb
        }
        t.blocks = blocks
        t.blocking = blocks.length > 0
      }
    }

    for (var r = 0; r < root.rows.length; r++) {
      if (root.rows[r] && root.rows[r].type === "task")
        applyToTask(root.rows[r].task)
    }
    var tasks = (root.snapshot && root.snapshot.tasks) ? root.snapshot.tasks : []
    for (var t = 0; t < tasks.length; t++)
      applyToTask(tasks[t])
    root.dataRev++
    var selfAfter = Model.findTask(tasks, selfUuid)
    root.dlog("deps.mutate", {
      add: !!add,
      self: selfUuid,
      other: otherUuid,
      depends: selfAfter ? Model.toJsArray(selfAfter.depends) : [],
      dataRev: root.dataRev
    })
  }

  function addDependency(taskOrUuid, depId) {
    var uuid = ""
    if (typeof taskOrUuid === "string") uuid = taskOrUuid
    else if (taskOrUuid && taskOrUuid.uuid) uuid = String(taskOrUuid.uuid)
    var dep = depId !== undefined && depId !== null ? String(depId) : ""
    root.dlog("deps.add.click", {
      uuid: uuid,
      dep: dep,
      expandedUuid: root.expandedUuid,
      cmdRunning: !!cmdProc.running,
      exportRunning: !!exportProc.running,
      queueLen: (root._cmdQueue || []).length
    })
    if (!uuid || !dep || dep === "[object Object]") {
      root.lastError = "deps: missing uuid"
      root.dlog("deps.add.reject", { uuid: uuid, dep: dep }, "warn")
      return
    }
    root.lastError = ""
    root.mutateDepLinks(uuid, dep, true)
    root.busyUuid = uuid
    root.runCmd(["deps", "--uuid", uuid, "--add", dep])
  }

  function removeDependency(taskOrUuid, depId) {
    var uuid = ""
    if (typeof taskOrUuid === "string") uuid = taskOrUuid
    else if (taskOrUuid && taskOrUuid.uuid) uuid = String(taskOrUuid.uuid)
    var dep = depId !== undefined && depId !== null ? String(depId) : ""
    root.dlog("deps.remove.click", {
      uuid: uuid,
      dep: dep,
      cmdRunning: !!cmdProc.running,
      exportRunning: !!exportProc.running,
      queueLen: (root._cmdQueue || []).length
    })
    if (!uuid || !dep || dep === "[object Object]") {
      root.lastError = "deps: missing uuid"
      root.dlog("deps.remove.reject", { uuid: uuid, dep: dep }, "warn")
      return
    }
    root.lastError = ""
    root.mutateDepLinks(uuid, dep, false)
    root.busyUuid = uuid
    root.runCmd(["deps", "--uuid", uuid, "--remove", dep])
  }

  function addTask() {
    var desc = addField.text.trim()
    if (!desc) return
    var sched = Model.toWireDateTime(addScheduledField.text.trim())
    var due = Model.toWireDateTime(addDueField.text.trim())
    if (!Model.datesValid(sched, due)) {
      root.lastError = "scheduled > due"
      return
    }
    var status = root.addStatus || "waiting"
    var args = ["add", "--description", desc, "--status", status]
    if (priorityCombo.value) args.push("--priority", priorityCombo.value)
    if (projectCombo.value) args.push("--project", projectCombo.value)
    if (sched) args.push("--scheduled", sched)
    if (due) args.push("--due", due)
    var details = addDetailsField.text
    if (details && details.trim()) args.push("--details", details)
    if (status === "waiting" && addWaitingForField.text.trim())
      args.push("--waiting-for", addWaitingForField.text.trim())
    if (status === "completed" && addOutcomeField.text.trim())
      args.push("--outcome", addOutcomeField.text.trim())
    var deps = root.addDepUuids || []
    for (var i = 0; i < deps.length; i++) {
      if (deps[i]) args.push("--depend", String(deps[i]))
    }
    if (root.addStartTimer && status !== "completed")
      args.push("--start-timer")

    addField.text = ""
    addScheduledField.text = ""
    addDueField.text = ""
    addDetailsField.text = ""
    addWaitingForField.text = ""
    addOutcomeField.text = ""
    priorityCombo.value = ""
    projectCombo.value = ""
    root.addStatus = "waiting"
    root.addDepUuids = []
    root.addStartTimer = false
    root.showAddAdvanced = false
    root.composerExpanded = false
    runCmd(args)
    Qt.callLater(function() {
      if (addField) addField.forceActiveFocus()
    })
  }

  function addComposerDep(depUuid) {
    depUuid = String(depUuid || "")
    if (!depUuid) return
    var cur = root.addDepUuids ? root.addDepUuids.slice() : []
    if (Model.listContains(cur, depUuid)) return
    cur.push(depUuid)
    root.addDepUuids = cur
  }

  function removeComposerDep(depUuid) {
    depUuid = String(depUuid || "")
    var cur = root.addDepUuids || []
    var next = []
    for (var i = 0; i < cur.length; i++)
      if (String(cur[i]) !== depUuid) next.push(cur[i])
    root.addDepUuids = next
  }

  function toggleDone(task) {
    if (!task || !task.uuid) return
    root.busyUuid = task.uuid
    if (task.status === "completed") {
      root.applyLocalTaskStatus(task.uuid, "pending")
      root.markDoneHold(task.uuid)
      root.rebuildRows(true)
      runCmd(["status", "--uuid", task.uuid, "--status", "pending"])
    } else {
      root.applyLocalTaskStatus(task.uuid, "completed")
      root.markDoneHold(task.uuid)
      root.rebuildRows(true)
      runCmd(["done", "--uuid", task.uuid])
    }
  }

  function toggleTimer(task) {
    if (!task || !task.uuid) return
    root.busyUuid = task.uuid
    if (task.timerActive) runCmd(["stop", "--uuid", task.uuid])
    else runCmd(["start", "--uuid", task.uuid])
  }

  function requestDelete(task) {
    if (!task || !task.uuid) return
    pendingDeleteUuid = task.uuid
    confirmDelete.opened = true
  }

  function confirmDeleteTask() {
    confirmDelete.opened = false
    if (!pendingDeleteUuid) return
    root.busyUuid = pendingDeleteUuid
    runCmd(["delete", "--uuid", pendingDeleteUuid])
    pendingDeleteUuid = ""
    expandedUuid = ""
  }

  function saveTask(task, desc, project, priority, scheduled, due, details) {
    if (!task || !task.uuid) return
    if (!desc || !String(desc).trim()) return
    var schedWire = Model.toWireDateTime(scheduled === undefined || scheduled === null ? "" : String(scheduled).trim())
    var dueWire = Model.toWireDateTime(due === undefined || due === null ? "" : String(due).trim())
    if (!Model.datesValid(schedWire, dueWire)) {
      root.lastError = "scheduled > due"
      return
    }
    root.busyUuid = task.uuid
    root.pendingEditorReseedUuid = ""
    root.expandedUuid = ""
    root.clearEditBuffer()
    var args = ["modify", "--uuid", task.uuid, "--description", String(desc).trim()]
    args.push("--project", project === undefined || project === null ? "" : String(project))
    args.push("--priority", priority === undefined || priority === null ? "" : String(priority))
    args.push("--scheduled", schedWire)
    args.push("--due", dueWire)
    args.push("--details", details === undefined || details === null ? "" : String(details))
    runCmd(args)
  }

  function setStatus(task, status, waitingFor) {
    if (!task || !task.uuid) return
    root.busyUuid = task.uuid
    var args = ["status", "--uuid", task.uuid, "--status", status]
    if (status === "waiting" && waitingFor !== undefined && waitingFor !== null)
      args.push("--waiting-for", String(waitingFor))
    runCmd(args)
  }

  function saveWaitingFor(task, text) {
    if (!task || !task.uuid) return
    root.busyUuid = task.uuid
    runCmd(["waiting-for", "--uuid", task.uuid, "--text", String(text || "")])
  }

  function saveOutcome(task, text) {
    if (!task || !task.uuid) return
    root.busyUuid = task.uuid
    runCmd(["outcome", "--uuid", task.uuid, "--text", String(text || "")])
  }

  function adjustTime(task, duration, remove) {
    if (!task || !task.uuid) return
    var d = String(duration || "").trim()
    if (!d) {
      root.lastError = root.tr("adjustTimeHint")
      return
    }
    root.busyUuid = task.uuid
    var args = ["time", "--uuid", task.uuid]
    if (remove) args.push("--remove", d)
    else args.push("--add", d)
    runCmd(args)
  }

  function renameProject() {
    var from = renameFrom
    var to = renameTo.trim()
    if (!from || !to || to.indexOf(":") >= 0) return
    runCmd(["projects", "rename", "--old", from, "--new", to])
    renameFrom = ""
    renameTo = ""
  }

  function cancelRenameProject() {
    renameFrom = ""
    renameTo = ""
    root.formFocused = false
  }

  function requestClearProject(name) {
    pendingClearProject = name
    confirmClear.opened = true
  }

  function confirmClearProjectAction() {
    confirmClear.opened = false
    if (!pendingClearProject) return
    runCmd(["projects", "clear", "--old", pendingClearProject])
    if (projectFilter === pendingClearProject) setProjectFilter("")
    pendingClearProject = ""
  }

  function createProjectName() {
    var name = newProjectField.text.trim()
    if (!name || name.indexOf(":") >= 0) return
    // Persist locally (TW only knows projects once a task uses them).
    // Stay on the Projects tab so the name can be assigned to an existing task.
    runCmd(["projects", "create", "--name", name])
    newProjectField.text = ""
  }

  function moveCursor(dy) {
    cursorActive = true
    if (rows.length === 0) {
      cursorIndex = -1
      return
    }
    var next = cursorIndex
    if (next < 0) next = dy > 0 ? 0 : rows.length - 1
    else next = Math.max(0, Math.min(rows.length - 1, next + dy))
    // Skip headers when moving
    var guard = 0
    while (guard < rows.length && rows[next] && rows[next].type === "header") {
      next = Math.max(0, Math.min(rows.length - 1, next + (dy >= 0 ? 1 : -1)))
      guard++
    }
    cursorIndex = next
    listView.positionViewAtIndex(cursorIndex, ListView.Contain)
  }

  function activateCursor() {
    var t = selectedTask()
    if (t) toggleDone(t)
  }

  function expandCursor() {
    if (cursorIndex < 0 || cursorIndex >= rows.length) return
    var row = rows[cursorIndex]
    if (row.type !== "task") return
    var uuid = String(row.task.uuid)
    if (root.expandedUuid === uuid)
      root.requestCloseEditor({ type: "dismiss" })
    else if (root.expandedUuid)
      root.requestCloseEditor({ type: "switch", uuid: uuid })
    else
      root.expandedUuid = uuid
  }

  property bool enterExpand: false

  function selectedTask() {
    if (cursorIndex < 0 || cursorIndex >= rows.length) return null
    var row = rows[cursorIndex]
    return row && row.type === "task" ? row.task : null
  }

  Process {
    id: exportProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var bytes = String(text || "").length
        root.dlog("export.done", { bytes: bytes })
        if (bytes > root.maxSnapshotChars) {
          root.lastError = "snapshot exceeds size limit"
          root.dlog("export.reject", { bytes: bytes, limit: root.maxSnapshotChars }, "error")
        } else {
          root.applyData(text)
        }
        Qt.callLater(root._drainCmdQueue)
      }
    }
    onExited: function(code) {
      root.dlog("export.exit", { code: code }, code === 0 ? "info" : "warn")
      Qt.callLater(root._drainCmdQueue)
    }
  }

  Timer {
    id: doneHoldTimer
    interval: 250
    repeat: true
    onTriggered: root.sweepDoneHolds()
  }

  Process {
    id: cmdProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var ms = root._cmdStartedAt ? (Date.now() - root._cmdStartedAt) : -1
        var bytes = String(text || "").length
        root.dlog("cmd.done", { ms: ms, bytes: bytes })
        root.busyUuid = ""
        if (bytes > root.maxSnapshotChars) {
          root.lastError = "snapshot exceeds size limit"
          root.dlog("cmd.reject", { bytes: bytes, limit: root.maxSnapshotChars, ms: ms }, "error")
        } else {
          root.applyData(text)
        }
        Qt.callLater(root._drainCmdQueue)
      }
    }
    onExited: function(code) {
      var ms = root._cmdStartedAt ? (Date.now() - root._cmdStartedAt) : -1
      root.dlog("cmd.exit", { code: code, ms: ms }, code === 0 ? "info" : "warn")
      root.busyUuid = ""
      if (code !== 0) root.refresh()
      Qt.callLater(root._drainCmdQueue)
    }
  }

  Process {
    id: debugLogProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if ((root._logQueue || []).length)
        Qt.callLater(root._flushLogQueue)
    }
  }

  Process {
    id: settingsGetProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.debugLogging = !!data.debugLogging
          root.debugLogPath = String(data.logPath || "")
          root.debugSessionId = String(data.sessionId || "")
          if (data.uiLanguage === "ru" || data.uiLanguage === "en" || data.uiLanguage === "system")
            root.uiLanguage = String(data.uiLanguage)
          if (root.debugLogging)
            root.dlog("ui.settings.loaded", {
              sessionId: root.debugSessionId,
              pluginVersion: root.pluginVersion,
              uiLanguage: root.uiLanguage,
              logPath: root.debugLogPath
            })
        } catch (e) {
          console.warn("taskwarrior-time: settings-get", e)
          root.dlog("ui.settings.error", { error: String(e), source: "get" }, "error")
        }
      }
    }
  }

  Process {
    id: settingsSetProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.debugLogging = !!data.debugLogging
          root.debugLogPath = String(data.logPath || "")
          root.debugSessionId = String(data.sessionId || "")
          if (data.uiLanguage === "ru" || data.uiLanguage === "en" || data.uiLanguage === "system")
            root.uiLanguage = String(data.uiLanguage)
          // Banner already written by helper on enable; acknowledge from UI.
          if (root.debugLogging)
            root.dlog("ui.settings.enabled", {
              sessionId: root.debugSessionId,
              pluginVersion: root.pluginVersion,
              uiLanguage: root.uiLanguage,
              logPath: root.debugLogPath
            })
        } catch (e) {
          console.warn("taskwarrior-time: settings-set", e)
          root.dlog("ui.settings.error", { error: String(e), source: "set" }, "error")
        }
      }
    }
  }

  // Bar button is on BarWidget; this panel is loaded hidden.
  Item {
    width: 0
    height: 0
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    // Fixed card height so the list can fill remaining space and the
    // composer stays pinned to the bottom of the popup.
    contentHeight: panel.cappedContentHeight(Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: confirmDelete.opened || confirmClear.opened || confirmUnsaved.opened || root.formFocused || root.datePickerCount > 0
      // When a field has focus, keyCatcher is blocked and Escape never hits
      // onCloseRequested. ApplicationShortcut still receives Escape.
      Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: root.opened && root.anyConfirmOpen
        onActivated: root.hotkeyCancelConfirm()
      }
      Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: root.opened
          && keyCatcher.blocked
          && !root.anyConfirmOpen
        onActivated: {
          if (!root.dismissEscapeOverlay())
            root.close()
        }
      }
      Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        context: Qt.ApplicationShortcut
        enabled: root.opened
        onActivated: root.hotkeyCommit()
      }
      Shortcut {
        sequences: ["Ctrl+Delete", "Ctrl+Backspace"]
        context: Qt.ApplicationShortcut
        enabled: root.opened && (root.anyConfirmOpen || root.expandedUuid !== "")
        onActivated: root.hotkeyDestroy()
      }
      onCloseRequested: {
        if (root.dismissEscapeOverlay()) return
        root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: {
        if (root.enterExpand) {
          root.enterExpand = false
          root.expandCursor()
          return
        }
        root.activateCursor()
      }
      onReturnRequested: { root.enterExpand = true }
      onDeleteRequested: {
        var t = root.selectedTask()
        if (t) root.requestDelete(t)
      }
      onTextKey: function(ch) {
        var t = root.selectedTask()
        if (!t) return
        if (ch === "t" || ch === "T") root.toggleTimer(t)
        if (ch === "e" || ch === "E") root.expandCursor()
      }

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        // Header
        Item {
          Layout.fillWidth: true
          height: Math.max(headerLeft.height, headerRight.height)

          MouseArea {
            anchors.fill: parent
            z: -1
            onPressed: function(mouse) {
              root.dismissOverlays()
              mouse.accepted = false
            }
          }

          Row {
            id: headerLeft
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: root.tasksHeaderTitle
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            id: headerRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              text: root.tr("viewTasks")
              selected: root.viewMode === "tasks"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(8)
              onClicked: root.viewMode = "tasks"
            }
            Button {
              text: root.tr("viewProjects")
              selected: root.viewMode === "projects"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(8)
              onClicked: root.viewMode = "projects"
            }
            Button {
              text: root.tr("about")
              selected: root.viewMode === "about"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(8)
              onClicked: root.viewMode = "about"
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.lastError !== ""
          Layout.fillWidth: true
          text: root.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // Tasks view: advanced filter spoiler → groupBy → list → sticky composer
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.space(8)
          visible: root.viewMode === "tasks"

          // View toolbar: Filter + Group as peers (Linear/Todoist pattern)
          Column {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: Math.max(filterToolbarLeft.height, filterToolbarRight.height)

              MouseArea {
                anchors.fill: parent
                z: -1
                onPressed: function(mouse) {
                  root.collapseExpandedTask()
                  mouse.accepted = false
                }
              }

              Row {
                id: filterToolbarLeft
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Button {
                  text: (root.showFilterPanel ? "▾ " : "▸ ") + root.tr("filterSpoiler")
                    + (root.activeFilterCount > 0 ? (" · " + root.activeFilterCount) : "")
                  selected: root.showFilterPanel || root.activeFilterCount > 0
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  verticalPadding: Style.space(2)
                  horizontalPadding: Style.space(8)
                  onClicked: {
                    root.collapseExpandedTask()
                    root.collapseComposer()
                    root.showFilterPanel = !root.showFilterPanel
                  }
                }
                Button {
                  visible: root.activeFilterCount > 0
                  text: root.tr("filterClear")
                  foreground: root.dim
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  verticalPadding: Style.space(2)
                  horizontalPadding: Style.space(8)
                  onClicked: {
                    root.collapseExpandedTask()
                    root.clearAdvancedFilters()
                  }
                }
              }

              Row {
                id: filterToolbarRight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  text: root.tr("groupBy")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
                Dropdown {
                  id: groupDropdown
                  width: Style.space(120)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  value: root.groupBy
                  options: [
                    { value: "none", label: root.tr("groupNone") },
                    { value: "project", label: root.tr("groupProject") },
                    { value: "priority", label: root.tr("groupPriority") },
                    { value: "due", label: root.tr("groupDue") },
                    { value: "status", label: root.tr("groupStatus") }
                  ]
                  onChanged: function(v) {
                    root.collapseExpandedTask()
                    root.groupBy = v
                  }
                }
              }
            }

            GridLayout {
              id: filterGrid
              visible: root.showFilterPanel
              width: parent.width
              columns: 2
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(6)
              // Equal column widths regardless of label/control content.
              readonly property real colWidth: Math.max(
                1,
                (width - columnSpacing) / 2
              )

              // Two filter fields per row (label above control) to cut height.
              Column {
                Layout.preferredWidth: filterGrid.colWidth
                Layout.maximumWidth: filterGrid.colWidth
                Layout.fillWidth: true
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: root.tr("filterStatus")
                  color: root.filterStatusActive ? root.filterActiveColor : root.filterIdleLabelColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.filterStatusActive
                }
                Rectangle {
                  width: parent.width
                  radius: Style.cornerRadius
                  color: root.filterFieldFill(root.filterStatusActive)
                  implicitHeight: filterStatusDropdown.implicitHeight + Style.space(4)
                  Dropdown {
                    id: filterStatusDropdown
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Style.space(2)
                    foreground: root.foreground
                    accent: root.filterStatusActive ? root.filterActiveColor : Color.accent
                    fontFamily: root.fontFamily
                    value: root.filterStatus
                    options: [
                      { value: "open", label: root.tr("filterStatusOpen") },
                      { value: "all", label: root.tr("filterStatusAll") },
                      { value: "waiting", label: root.tr("statusWaiting") },
                      { value: "pending", label: root.tr("statusPending") },
                      { value: "active", label: root.tr("filterActive") },
                      { value: "completed", label: root.tr("statusCompleted") }
                    ]
                    onChanged: function(v) { root.filterStatus = v }
                  }
                }
              }

              Column {
                Layout.preferredWidth: filterGrid.colWidth
                Layout.maximumWidth: filterGrid.colWidth
                Layout.fillWidth: true
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: root.tr("filterProject")
                  color: root.filterProjectActive ? root.filterActiveColor : root.filterIdleLabelColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.filterProjectActive
                }
                Rectangle {
                  width: parent.width
                  radius: Style.cornerRadius
                  color: root.filterFieldFill(root.filterProjectActive)
                  implicitHeight: projectFilterDropdown.implicitHeight + Style.space(4)
                  Dropdown {
                    id: projectFilterDropdown
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Style.space(2)
                    foreground: root.foreground
                    accent: root.filterProjectActive ? root.filterActiveColor : Color.accent
                    fontFamily: root.fontFamily
                    value: root.projectFilter
                    options: root.projectFilterOptions
                    onChanged: function(v) {
                      if (v !== root.projectFilter)
                        root.setProjectFilter(v)
                    }
                  }
                }
              }

              Column {
                Layout.preferredWidth: filterGrid.colWidth
                Layout.maximumWidth: filterGrid.colWidth
                Layout.fillWidth: true
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: root.tr("priority")
                  color: root.filterPriorityActive ? root.filterActiveColor : root.filterIdleLabelColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.filterPriorityActive
                }
                Rectangle {
                  width: parent.width
                  radius: Style.cornerRadius
                  color: root.filterFieldFill(root.filterPriorityActive)
                  implicitHeight: filterPriorityDropdown.implicitHeight + Style.space(4)
                  Dropdown {
                    id: filterPriorityDropdown
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Style.space(2)
                    foreground: root.foreground
                    accent: root.filterPriorityActive ? root.filterActiveColor : Color.accent
                    fontFamily: root.fontFamily
                    value: root.filterPriority
                    options: [
                      { value: "", label: root.tr("filterAny") },
                      { value: "H", label: root.tr("priH") },
                      { value: "M", label: root.tr("priM") },
                      { value: "L", label: root.tr("priL") },
                      { value: "__none__", label: root.tr("priNone") }
                    ]
                    onChanged: function(v) { root.filterPriority = v }
                  }
                }
              }

              Column {
                Layout.preferredWidth: filterGrid.colWidth
                Layout.maximumWidth: filterGrid.colWidth
                Layout.fillWidth: true
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: root.tr("filterDue")
                  color: root.filterDueActive ? root.filterActiveColor : root.filterIdleLabelColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.filterDueActive
                }
                Rectangle {
                  width: parent.width
                  radius: Style.cornerRadius
                  color: root.filterFieldFill(root.filterDueActive)
                  implicitHeight: filterDueDropdown.implicitHeight + Style.space(4)
                  Dropdown {
                    id: filterDueDropdown
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Style.space(2)
                    foreground: root.foreground
                    accent: root.filterDueActive ? root.filterActiveColor : Color.accent
                    fontFamily: root.fontFamily
                    value: root.filterDue
                    options: [
                      { value: "", label: root.tr("filterAny") },
                      { value: "soon", label: root.tr("filterDueSoon") },
                      { value: "overdue", label: root.tr("dueOverdue") },
                      { value: "today", label: root.tr("dueToday") },
                      { value: "tomorrow", label: root.tr("dueTomorrow") },
                      { value: "week", label: root.tr("dueWeek") },
                      { value: "later", label: root.tr("dueLater") },
                      { value: "none", label: root.tr("dueNone") }
                    ]
                    onChanged: function(v) { root.filterDue = v }
                  }
                }
              }

              Column {
                Layout.preferredWidth: filterGrid.colWidth
                Layout.maximumWidth: filterGrid.colWidth
                Layout.fillWidth: true
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: root.tr("filterTimer")
                  color: root.filterTimerActive ? root.filterActiveColor : root.filterIdleLabelColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.filterTimerActive
                }
                Rectangle {
                  width: parent.width
                  radius: Style.cornerRadius
                  color: root.filterFieldFill(root.filterTimerActive)
                  implicitHeight: filterTimerDropdown.implicitHeight + Style.space(4)
                  Dropdown {
                    id: filterTimerDropdown
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Style.space(2)
                    foreground: root.foreground
                    accent: root.filterTimerActive ? root.filterActiveColor : Color.accent
                    fontFamily: root.fontFamily
                    value: root.filterTimer
                    options: [
                      { value: "", label: root.tr("filterAny") },
                      { value: "running", label: root.tr("filterTimerOn") },
                      { value: "idle", label: root.tr("filterTimerOff") }
                    ]
                    onChanged: function(v) { root.filterTimer = v }
                  }
                }
              }

              Column {
                Layout.preferredWidth: filterGrid.colWidth
                Layout.maximumWidth: filterGrid.colWidth
                Layout.fillWidth: true
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: root.tr("filterDeps")
                  color: root.filterBlockedActive ? root.filterActiveColor : root.filterIdleLabelColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.filterBlockedActive
                }
                Rectangle {
                  width: parent.width
                  radius: Style.cornerRadius
                  color: root.filterFieldFill(root.filterBlockedActive)
                  implicitHeight: filterBlockedDropdown.implicitHeight + Style.space(4)
                  Dropdown {
                    id: filterBlockedDropdown
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Style.space(2)
                    foreground: root.foreground
                    accent: root.filterBlockedActive ? root.filterActiveColor : Color.accent
                    fontFamily: root.fontFamily
                    value: root.filterBlocked
                    options: [
                      { value: "", label: root.tr("filterAny") },
                      { value: "blocked", label: root.tr("blocked") },
                      { value: "blocking", label: root.tr("blocking") },
                      { value: "clear", label: root.tr("filterDepsClear") }
                    ]
                    onChanged: function(v) { root.filterBlocked = v }
                  }
                }
              }

              Column {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: root.tr("filterSearch")
                  color: root.filterSearchActive ? root.filterActiveColor : root.filterIdleLabelColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.filterSearchActive
                }
                Rectangle {
                  width: parent.width
                  radius: Style.cornerRadius
                  color: root.filterFieldFill(root.filterSearchActive)
                  // Match select-field chrome height (dropdown row + outer pad).
                  implicitHeight: filterStatusDropdown.implicitHeight + Style.space(4)
                  TextField {
                    id: filterSearchField
                    anchors.fill: parent
                    anchors.margins: Style.space(2)
                    foreground: root.foreground
                    accent: root.filterSearchActive ? root.filterActiveColor : Color.accent
                    placeholderText: root.tr("filterSearchHint")
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    verticalPadding: Style.space(1)
                    text: root.filterSearch
                    onActiveFocusChanged: {
                      if (activeFocus) {
                        root.collapseComposer()
                        root.collapseExpandedTask()
                      }
                      root.formFocused = activeFocus
                    }
                    onTextChanged: root.filterSearch = text
                    Keys.onEscapePressed: function(event) { root.escapeFromField(event) }
                  }
                }
              }
            }
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: root.foreground
            MouseArea {
              anchors.fill: parent
              onClicked: root.dismissOverlays()
            }
          }

          // Task list fills all space between controls and sticky composer
          ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Style.space(120)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Do not collapse the open editor on scroll — the list must pan
            // with the expanded form intact. Empty-gap presses still dismiss
            // via the MouseArea below.
            // Clicks on empty list gaps — collapse create form and open editor.
            MouseArea {
              anchors.fill: parent
              z: -1
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onPressed: function(mouse) {
                root.dismissOverlays()
                mouse.accepted = false
              }
            }
            interactive: contentHeight > height
            spacing: Style.space(4)
            model: root.rows

            ScrollBar.vertical: ScrollBar {
              policy: listView.contentHeight > listView.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            delegate: Item {
              id: rowRoot
              required property var modelData
              required property int index
              width: listView.width

              readonly property bool isHeader: modelData.type === "header"
              // ListView's modelData.task is a detached copy after the model is
              // set — in-place patchRowsInPlace / mutateDepLinks update
              // root.rows[i].task, so always re-read from there via dataRev.
              readonly property var liveRow: {
                var _ = root.dataRev
                if (index < 0 || index >= root.rows.length) return null
                return root.rows[index]
              }
              readonly property var taskSrc: {
                var _ = root.dataRev
                var row = liveRow
                if (row && row.task) return row.task
                return modelData ? modelData.task : null
              }
              readonly property var task: Model.taskSnapshot(taskSrc, root.dataRev)
              readonly property var liveDepends: {
                var _ = root.dataRev
                return Model.toJsArray(taskSrc ? taskSrc.depends : null)
              }
              readonly property var liveBlocks: {
                var _ = root.dataRev
                return Model.toJsArray(taskSrc ? taskSrc.blocks : null)
              }
              readonly property bool expanded: !isHeader && task && root.expandedUuid === task.uuid
              readonly property bool hasCursor: root.cursorActive && root.cursorIndex === index
              height: rowCol.implicitHeight + (expanded ? Style.space(10) : 0)

              // Panel-level edit* strings are the source of truth across
              // ListView teardown (deps add/remove, status, timer, refresh).
              property bool suppressDraftPersist: false
              property bool editorHydrated: false
              property bool focusTitleOnSeed: false
              property bool showAdvanced: false

              function flushFieldsToDrafts() {
                var live = taskSrc || task
                if (!live) return
                // Snapshot may destroy this delegate before runCmd finishes.
                // Prefer live widget text, but never blank a non-empty buffer
                // with an empty widget (common mid-teardown).
                root.editUuid = String(live.uuid || root.expandedUuid || "")
                root.editActive = true
                var desc = editDescField.text
                if (desc !== "") root.editDescription = desc
                var details = editDetailsArea.text
                if (details !== "") root.editDetails = details
                if (editorHydrated) {
                  // Same rule as description/details: never blank a non-empty
                  // buffer with an empty widget (common while the status-gated
                  // waitingFor / outcome fields are not visible yet).
                  var waitingForText = waitingForField.text
                  if (waitingForText !== "" || (waitingForField.visible && waitingForField.width > 0))
                    root.editWaitingFor = waitingForText
                  if (outcomeField) {
                    var outcomeText = outcomeField.text
                    if (outcomeText !== "" || (outcomeField.visible && outcomeField.width > 0))
                      root.editOutcome = outcomeText
                  }
                  root.editPriority = editPriority.value
                  root.editProject = editProject.value
                  var sched = editScheduled.text
                  if (sched !== "" || root.editScheduled === "")
                    root.editScheduled = sched
                  var due = editDue.text
                  if (due !== "" || root.editDue === "")
                    root.editDue = due
                }
              }

              function syncStatusGatedFields() {
                if (!editorHydrated || suppressDraftPersist) return
                var v = root.editValues()
                if (waitingForField.visible) {
                  var wantWaiting = String(
                    v.waitingFor
                    || (rowRoot.task && rowRoot.task.waitingFor)
                    || ""
                  )
                  if (waitingForField.text !== wantWaiting) {
                    suppressDraftPersist = true
                    waitingForField.text = wantWaiting
                    suppressDraftPersist = false
                    if (wantWaiting && !root.editWaitingFor)
                      root.editWaitingFor = wantWaiting
                  }
                }
                if (outcomeField && outcomeField.visible) {
                  var wantOutcome = String(
                    v.outcome
                    || (rowRoot.task && rowRoot.task.outcome)
                    || ""
                  )
                  if (outcomeField.text !== wantOutcome) {
                    suppressDraftPersist = true
                    outcomeField.text = wantOutcome
                    suppressDraftPersist = false
                    if (wantOutcome && !root.editOutcome)
                      root.editOutcome = wantOutcome
                  }
                }
              }

              function applyEditorValues(v) {
                suppressDraftPersist = true
                editDescField.text = v.description || ""
                editDetailsArea.text = String(v.details || "")
                waitingForField.text = v.waitingFor || ""
                if (outcomeField)
                  outcomeField.text = v.outcome || ""
                editPriority.value = v.priority || ""
                editProject.value = v.project || ""
                editScheduled.text = v.scheduled || ""
                editDue.text = v.due || ""
                suppressDraftPersist = false
                // Status-gated fields may still be invisible on first hydrate;
                // re-apply once they show (see onVisibleChanged below).
                Qt.callLater(function () { rowRoot.syncStatusGatedFields() })
              }

              function hydrateEditor(fromTaskOnly) {
                if (!task) return
                var uuid = String(task.uuid)
                // Never replace an in-progress buffer with server data unless
                // forced after Save (fromTaskOnly) or opening another task.
                if (fromTaskOnly)
                  root.beginEditFromTask(task)
                else if (!root.editActive || root.editUuid !== uuid)
                  root.beginEditFromTask(task)
                applyEditorValues(root.editValues())
                editorHydrated = true
              }

              function setEditField(key, value) {
                // Per-field updates — never rewrite the whole buffer from a
                // mix of live + empty widgets (that wiped siblings on refresh).
                if (suppressDraftPersist || !editorHydrated || !task) return
                if (root.editGuard) return
                root.editUuid = String(task.uuid)
                root.editActive = true
                if (key === "description") root.editDescription = value
                else if (key === "details") root.editDetails = value
                else if (key === "waitingFor") root.editWaitingFor = value
                else if (key === "outcome") root.editOutcome = value
                else if (key === "priority") root.editPriority = value
                else if (key === "project") root.editProject = value
                else if (key === "scheduled") root.editScheduled = value
                else if (key === "due") root.editDue = value
              }

              function captureEditorValues() {
                return {
                  description: root.editDescription,
                  details: root.editDetails,
                  project: root.editProject,
                  priority: root.editPriority,
                  scheduled: root.editScheduled,
                  due: root.editDue
                }
              }

              Connections {
                target: rowRoot
                function onExpandedChanged() {
                  if (rowRoot.expanded) {
                    rowRoot.focusTitleOnSeed = true
                    Qt.callLater(function () { rowRoot.hydrateEditor(false) })
                  } else {
                    rowRoot.editorHydrated = false
                  }
                }
              }
              Connections {
                target: root
                function onEditRestoreSeqChanged() {
                  if (!rowRoot.expanded || !rowRoot.task) return
                  if (root.editUuid !== String(rowRoot.task.uuid)) return
                  Qt.callLater(function () {
                    if (!rowRoot.expanded || !rowRoot.task) return
                    if (root.editUuid !== String(rowRoot.task.uuid)) return
                    rowRoot.hydrateEditor(false)
                  })
                }
              }

              // Empty gaps in the editor (labels, spacing, row padding) are
              // mouse-transparent; without this, presses fall through to
              // ListView's dismissOverlays and collapse the open task.
              MouseArea {
                anchors.fill: parent
                enabled: rowRoot.expanded && !rowRoot.isHeader
                z: -1
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: function(mouse) { mouse.accepted = true }
                onClicked: function(mouse) { mouse.accepted = true }
              }

              Column {
                id: rowCol
                width: parent.width
                spacing: Style.space(4)

                // Section header
                PanelSectionHeader {
                  visible: rowRoot.isHeader
                  width: parent.width
                  text: rowRoot.isHeader ? String(modelData.label || "").toUpperCase() : ""
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                // Task row — card when expanded so the editor reads as one
                // surface and does not blend into the next list item.
                Rectangle {
                  visible: !rowRoot.isHeader
                  width: parent.width
                  implicitHeight: taskBody.implicitHeight + (rowRoot.expanded ? Style.space(12) : 0)
                  radius: Style.cornerRadius
                  color: "transparent"
                  border.width: rowRoot.expanded ? 1 : 0
                  border.color: rowRoot.expanded
                    ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
                    : "transparent"

                  Column {
                    id: taskBody
                    width: parent.width
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: rowRoot.expanded ? Style.space(6) : 0
                    spacing: Style.space(4)

                  Rectangle {
                    id: taskHoverBg
                    width: parent.width
                    height: Math.max(summaryRow.implicitHeight, root.doneCheckSize) + Style.space(6)
                    radius: Style.cornerRadius
                    color: rowRoot.expanded
                      ? "transparent"
                      : (rowRoot.hasCursor || taskMouse.containsMouse
                        ? Style.hoverFillFor(root.foreground, Color.accent)
                        : "transparent")

                    MouseArea {
                      id: taskMouse
                      z: 0
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.LeftButton | Qt.RightButton
                      onEntered: { root.cursorActive = true; root.cursorIndex = rowRoot.index }
                      onClicked: function(mouse) {
                        root.collapseFilterPanel()
                        root.collapseComposer()
                        root.cursorIndex = rowRoot.index
                        if (mouse.button === Qt.RightButton) {
                          root.requestDelete(rowRoot.taskSrc)
                          return
                        }
                        var uuid = String(rowRoot.taskSrc.uuid || "")
                        if (!uuid) return
                        // While editing, clicks on this row (incl. empty space
                        // around the title field) must not dismiss — only
                        // outside the editor card should collapse.
                        if (root.expandedUuid === uuid)
                          return
                        else if (root.expandedUuid)
                          root.requestCloseEditor({ type: "switch", uuid: uuid })
                        else
                          root.expandedUuid = uuid
                      }
                    }

                    // Checkbox centered on the hover strip itself (not the text column).
                    Item {
                      id: doneCheck
                      z: 1
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      width: root.doneCheckSize
                      height: root.doneCheckSize

                      Text {
                        textFormat: Text.PlainText
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "☐"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.doneCheckSize
                      }
                      Text {
                        textFormat: Text.PlainText
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        visible: !!(rowRoot.task && rowRoot.task.status === "completed")
                        text: "✓"
                        color: root.doneCheckColor
                        font.family: root.fontFamily
                        font.pixelSize: root.doneCheckSize * 0.72
                        font.bold: true
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleDone(rowRoot.taskSrc)
                      }
                    }

                    // Timer play/stop — same size and vertical centering as the done glyph.
                    Item {
                      id: timerCheck
                      z: 1
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      width: root.doneCheckSize
                      height: root.doneCheckSize

                      readonly property bool running: !!(rowRoot.task && rowRoot.task.timerActive)

                      Text {
                        textFormat: Text.PlainText
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: timerCheck.running ? "■" : "▶"
                        color: timerCheck.running ? root.doneCheckColor : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.doneCheckSize * (timerCheck.running ? 0.78 : 0.85)
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                          rowRoot.flushFieldsToDrafts()
                          root.toggleTimer(rowRoot.taskSrc)
                        }
                      }
                    }

                    Row {
                      id: summaryRow
                      z: 1
                      anchors.left: doneCheck.right
                      anchors.right: timerCheck.left
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(6)
                      anchors.rightMargin: Style.space(6)
                      spacing: Style.space(6)

                      Column {
                        width: parent.width
                        clip: true
                        spacing: 1

                        // Collapsed: plain title. Expanded: same slot becomes the editor.
                        Text {
                          textFormat: Text.PlainText
                          visible: !rowRoot.expanded
                          width: parent.width
                          text: {
                            var _ = root.dataRev
                            return rowRoot.task ? rowRoot.task.description : ""
                          }
                          color: {
                            if (rowRoot.task && rowRoot.task.status === "completed")
                              return root.dim
                            return root.foreground
                          }
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          font.strikeout: !!(rowRoot.task && rowRoot.task.status === "completed")
                          elide: Text.ElideRight
                          wrapMode: Text.NoWrap
                          maximumLineCount: 1
                        }
                        TextField {
                          id: editDescField
                          visible: rowRoot.expanded
                          width: parent.width
                          foreground: root.foreground
                          verticalPadding: Style.space(2)
                          onActiveFocusChanged: root.formFocused = activeFocus
                          onTextChanged: rowRoot.setEditField("description", text)
                          Keys.onEscapePressed: function(event) { root.escapeFromField(event) }
                          onVisibleChanged: {
                            if (!visible) return
                            Qt.callLater(function () {
                              if (!editDescField.visible) return
                              rowRoot.hydrateEditor(false)
                              if (rowRoot.focusTitleOnSeed) {
                                rowRoot.focusTitleOnSeed = false
                                editDescField.forceActiveFocus()
                              }
                            })
                          }
                        }

                        // List meta as fixed columns (scan-stable): project flexes
                        // and elides; priority / due / blocked keep reserved tracks
                        // even when empty so optional badges never shove neighbors.
                        RowLayout {
                          id: metaRow
                          visible: !rowRoot.expanded && !!(rowRoot.task && (
                            rowRoot.task.priority
                            || rowRoot.task.due
                            || rowRoot.task.scheduled
                            || rowRoot.task.project
                            || rowRoot.task.blocked
                          ))
                          width: parent.width
                          spacing: Style.space(8)

                          Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 1
                            text: rowRoot.task && rowRoot.task.project ? rowRoot.task.project : ""
                            color: root.dim
                            opacity: rowRoot.task && rowRoot.task.project ? 1 : 0
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                          }
                          Text {
                            textFormat: Text.PlainText
                            Layout.preferredWidth: root.metaPriWidth
                            Layout.minimumWidth: root.metaPriWidth
                            Layout.maximumWidth: root.metaPriWidth
                            text: rowRoot.task && rowRoot.task.priority
                              ? Model.priorityLabel(rowRoot.task.priority, root.tr)
                              : ""
                            color: root.priorityColor(rowRoot.task ? rowRoot.task.priority : "")
                            opacity: rowRoot.task && rowRoot.task.priority ? 1 : 0
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                          }
                          Text {
                            textFormat: Text.PlainText
                            Layout.preferredWidth: root.metaDueWidth
                            Layout.minimumWidth: root.metaDueWidth
                            Layout.maximumWidth: root.metaDueWidth
                            text: rowRoot.task && (rowRoot.task.due || rowRoot.task.scheduled)
                              ? Model.dueListLabel(rowRoot.task, root.tr)
                              : ""
                            color: root.dueMetaColor(rowRoot.task)
                            opacity: rowRoot.task && (rowRoot.task.due || rowRoot.task.scheduled) ? 1 : 0
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                          }
                          Text {
                            textFormat: Text.PlainText
                            Layout.preferredWidth: root.metaBlockedWidth
                            Layout.minimumWidth: root.metaBlockedWidth
                            Layout.maximumWidth: root.metaBlockedWidth
                            text: root.tr("blocked")
                            color: root.urgent
                            opacity: rowRoot.task && rowRoot.task.blocked ? 1 : 0
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                          }
                        }
                      }
                    }
                  }

                  // Expanded editor — field order follows common task UX:
                  // identity → plan → schedule → links → time → actions.
                  Column {
                    visible: rowRoot.expanded
                    width: parent.width
                    spacing: Style.space(10)

                    // —— 1. Details (title edits in-place in the summary row) ——
                    Column {
                      width: parent.width
                      spacing: Style.space(4)

                      Text {
                        textFormat: Text.PlainText
                        text: root.tr("details")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Rectangle {
                        id: editDetailsBox
                        width: parent.width
                        height: Style.space(88)
                        radius: Style.cornerRadius
                        color: Style.controlFill(editDetailsArea.activeFocus, editDetailsHover.hovered, root.foreground, Color.accent)
                        border.color: editDetailsArea.activeFocus
                          ? Color.accent
                          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                        border.width: 1

                        HoverHandler { id: editDetailsHover }

                        ScrollView {
                          anchors.fill: parent
                          anchors.margins: Style.space(6)
                          clip: true
                          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                          TextArea {
                            textFormat: Text.PlainText
                            id: editDetailsArea
                            width: editDetailsBox.width - Style.space(12)
                            wrapMode: TextArea.Wrap
                            selectByMouse: true
                            color: root.foreground
                            placeholderText: root.tr("detailsHint")
                            placeholderTextColor: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            background: Item {}
                            onActiveFocusChanged: root.formFocused = activeFocus
                            onTextChanged: rowRoot.setEditField("details", text)
                            Keys.onEscapePressed: function(event) { root.escapeFromField(event) }
                          }
                        }
                      }
                    }

                    // —— 2. Plan (status / priority / project) ————
                    Column {
                      width: parent.width
                      spacing: Style.space(4)

                      Text {
                        textFormat: Text.PlainText
                        text: root.tr("editSectionPlan")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      Text {
                        textFormat: Text.PlainText
                        text: root.tr("status")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Row {
                        spacing: Style.space(4)
                        Button {
                          text: root.tr("waiting")
                          selected: !!(rowRoot.task && rowRoot.task.status === "waiting")
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          fontSize: Style.font.caption
                          verticalPadding: Style.space(1)
                          horizontalPadding: Style.space(6)
                          onClicked: {
                            rowRoot.flushFieldsToDrafts()
                            root.setStatus(rowRoot.taskSrc, "waiting")
                          }
                        }
                        Button {
                          text: root.tr("pending")
                          selected: !!(rowRoot.task && rowRoot.task.status === "pending")
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          fontSize: Style.font.caption
                          verticalPadding: Style.space(1)
                          horizontalPadding: Style.space(6)
                          onClicked: {
                            rowRoot.flushFieldsToDrafts()
                            root.setStatus(rowRoot.taskSrc, "pending")
                          }
                        }
                        Button {
                          text: root.tr("done")
                          selected: !!(rowRoot.task && rowRoot.task.status === "completed")
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          fontSize: Style.font.caption
                          verticalPadding: Style.space(1)
                          horizontalPadding: Style.space(6)
                          onClicked: {
                            rowRoot.flushFieldsToDrafts()
                            root.setStatus(rowRoot.taskSrc, "completed")
                          }
                        }
                      }

                      Column {
                        visible: !!(rowRoot.task && rowRoot.task.status === "waiting")
                        width: parent.width
                        spacing: Style.space(4)
                        onVisibleChanged: {
                          if (visible)
                            Qt.callLater(function () { rowRoot.syncStatusGatedFields() })
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: root.tr("waitingFor")
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                        TextField {
                          id: waitingForField
                          width: parent.width
                          foreground: root.foreground
                          placeholderText: root.tr("waitingForHint")
                          verticalPadding: Style.space(2)
                          onActiveFocusChanged: root.formFocused = activeFocus
                          onTextChanged: rowRoot.setEditField("waitingFor", text)
                          onVisibleChanged: {
                            if (visible)
                              Qt.callLater(function () { rowRoot.syncStatusGatedFields() })
                          }
                          Keys.onEscapePressed: function(event) { root.escapeFromField(event) }
                          onEditingFinished: {
                            if (!rowRoot.task) return
                            var next = text.trim()
                            var prev = String(rowRoot.task.waitingFor || "")
                            if (next !== prev) {
                              root.saveWaitingFor(rowRoot.taskSrc, next)
                              root.editWaitingFor = next
                              root.refreshEditBaseline()
                            }
                          }
                          Keys.onReturnPressed: function(event) {
                            editingFinished()
                            event.accepted = true
                          }
                        }
                      }

                      Column {
                        visible: !!(rowRoot.task && rowRoot.task.status === "completed")
                        width: parent.width
                        spacing: Style.space(4)
                        onVisibleChanged: {
                          if (visible)
                            Qt.callLater(function () { rowRoot.syncStatusGatedFields() })
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: root.tr("outcome")
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                        TextField {
                          id: outcomeField
                          width: parent.width
                          foreground: root.foreground
                          placeholderText: root.tr("outcomeHint")
                          verticalPadding: Style.space(2)
                          onActiveFocusChanged: root.formFocused = activeFocus
                          onTextChanged: rowRoot.setEditField("outcome", text)
                          onVisibleChanged: {
                            if (visible)
                              Qt.callLater(function () { rowRoot.syncStatusGatedFields() })
                          }
                          Keys.onEscapePressed: function(event) { root.escapeFromField(event) }
                          onEditingFinished: {
                            if (!rowRoot.task) return
                            var next = text.trim()
                            var prev = String(rowRoot.task.outcome || "")
                            if (next !== prev) {
                              root.saveOutcome(rowRoot.taskSrc, next)
                              root.editOutcome = next
                              root.refreshEditBaseline()
                            }
                          }
                          Keys.onReturnPressed: function(event) {
                            editingFinished()
                            event.accepted = true
                          }
                        }
                      }

                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Column {
                          width: (parent.width - Style.space(8)) / 2
                          spacing: Style.space(4)

                          Text {
                            textFormat: Text.PlainText
                            text: root.tr("priority")
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                          Dropdown {
                            id: editPriority
                            width: parent.width
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            value: ""
                            options: [
                              { value: "", label: root.tr("priorityNone") },
                              { value: "H", label: root.tr("priH") },
                              { value: "M", label: root.tr("priM") },
                              { value: "L", label: root.tr("priL") }
                            ]
                            onChanged: function(v) { rowRoot.setEditField("priority", v) }
                          }
                        }

                        Column {
                          width: (parent.width - Style.space(8)) / 2
                          spacing: Style.space(4)

                          Text {
                            textFormat: Text.PlainText
                            text: root.tr("project")
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                          Dropdown {
                            id: editProject
                            width: parent.width
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            value: ""
                            options: {
                              var opts = [{ value: "", label: root.tr("projectNone") }]
                              for (var i = 0; i < root.projectList.length; i++)
                                opts.push({ value: root.projectList[i], label: root.projectList[i] })
                              if (rowRoot.task && rowRoot.task.project) {
                                var found = false
                                for (var j = 0; j < opts.length; j++) if (opts[j].value === rowRoot.task.project) found = true
                                if (!found) opts.push({ value: rowRoot.task.project, label: rowRoot.task.project })
                              }
                              var cur = editProject.value
                              if (cur) {
                                var have = false
                                for (var k = 0; k < opts.length; k++) if (opts[k].value === cur) have = true
                                if (!have) opts.push({ value: cur, label: cur })
                              }
                              return opts
                            }
                            onChanged: function(v) { rowRoot.setEditField("project", v) }
                          }
                        }
                      }
                    }

                    Button {
                      text: (rowRoot.showAdvanced ? "▾ " : "▸ ") + (
                        rowRoot.showAdvanced ? root.tr("advancedHide") : root.tr("advancedShow")
                      )
                      foreground: root.dim
                      fontFamily: root.fontFamily
                      fontSize: Style.font.caption
                      verticalPadding: Style.space(2)
                      horizontalPadding: Style.space(6)
                      onClicked: rowRoot.showAdvanced = !rowRoot.showAdvanced
                    }

                    Column {
                      visible: rowRoot.showAdvanced
                      width: parent.width
                      spacing: Style.space(10)

                    // —— 3. Schedule (start, then due) ——————————
                    Column {
                      width: parent.width
                      spacing: Style.space(4)

                      Text {
                        textFormat: Text.PlainText
                        text: root.tr("editSectionSchedule")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      GridLayout {
                        width: parent.width
                        columns: 2
                        columnSpacing: Style.space(6)
                        rowSpacing: Style.space(4)

                        Text {
                          textFormat: Text.PlainText
                          text: root.tr("startDate")
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                        DateTimeField {
                          id: editScheduled
                          Layout.fillWidth: true
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          host: root
                          text: ""
                          placeholderText: root.tr("datesHint")
                          trToday: root.tr("dueToday")
                          trClear: root.tr("dateClear")
                          trApply: root.tr("dateApply")
                          trTime: root.tr("dateTime")
                          onEditingFinished: rowRoot.setEditField("scheduled", text)
                          onAccepted: rowRoot.setEditField("scheduled", text)
                        }
                        Connections {
                          target: editScheduled
                          function onTextChanged() { rowRoot.setEditField("scheduled", editScheduled.text) }
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: root.tr("endDate")
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                        DateTimeField {
                          id: editDue
                          Layout.fillWidth: true
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          host: root
                          text: ""
                          placeholderText: root.tr("datesHint")
                          trToday: root.tr("dueToday")
                          trClear: root.tr("dateClear")
                          trApply: root.tr("dateApply")
                          trTime: root.tr("dateTime")
                          onEditingFinished: rowRoot.setEditField("due", text)
                          onAccepted: rowRoot.setEditField("due", text)
                        }
                        Connections {
                          target: editDue
                          function onTextChanged() { rowRoot.setEditField("due", editDue.text) }
                        }
                      }
                    }

                    // —— 4. Dependencies ————————————————
                    Column {
                      width: parent.width
                      spacing: Style.space(4)

                      Text {
                        textFormat: Text.PlainText
                        text: root.tr("editSectionLinks")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      Column {
                        visible: rowRoot.liveDepends.length > 0
                        width: parent.width
                        spacing: Style.space(2)

                        Text {
                          textFormat: Text.PlainText
                          text: root.tr("depends")
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Repeater {
                          model: rowRoot.liveDepends
                          Row {
                            // Avoid clashing with ListView's modelData name.
                            required property var modelData
                            readonly property string depId: String(modelData)
                            spacing: Style.space(6)
                            width: parent.width
                            Text {
                              textFormat: Text.PlainText
                              text: {
                                var _ = root.dataRev
                                var dep = Model.findTask(root.snapshot.tasks || [], parent.depId)
                                if (!dep) return parent.depId
                                var idBit = dep.id ? ("#" + dep.id + " ") : ""
                                return idBit + dep.description
                              }
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              width: parent.width - Style.space(60)
                              elide: Text.ElideRight
                            }
                            Button {
                              text: root.tr("removeDep")
                              foreground: root.urgent
                              fontFamily: root.fontFamily
                              fontSize: Style.font.caption
                              verticalPadding: Style.space(1)
                              horizontalPadding: Style.space(4)
                              onClicked: {
                                var uuid = String((rowRoot.taskSrc && rowRoot.taskSrc.uuid)
                                  || (rowRoot.task && rowRoot.task.uuid)
                                  || root.expandedUuid || "")
                                var dep = parent.depId
                                rowRoot.flushFieldsToDrafts()
                                root.removeDependency(uuid, dep)
                              }
                            }
                          }
                        }
                      }

                      Column {
                        visible: rowRoot.liveBlocks.length > 0
                        width: parent.width
                        spacing: Style.space(2)

                        Text {
                          textFormat: Text.PlainText
                          text: root.tr("blocks")
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Repeater {
                          model: rowRoot.liveBlocks
                          Row {
                            required property var modelData
                            readonly property string otherUuid: String(modelData)
                            spacing: Style.space(6)
                            width: parent.width
                            Text {
                              textFormat: Text.PlainText
                              text: {
                                var _ = root.dataRev
                                var other = Model.findTask(root.snapshot.tasks || [], parent.otherUuid)
                                if (!other) return parent.otherUuid
                                var idBit = other.id ? ("#" + other.id + " ") : ""
                                return idBit + other.description
                              }
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              width: parent.width - Style.space(60)
                              elide: Text.ElideRight
                            }
                            Button {
                              text: root.tr("removeDep")
                              foreground: root.urgent
                              fontFamily: root.fontFamily
                              fontSize: Style.font.caption
                              verticalPadding: Style.space(1)
                              horizontalPadding: Style.space(4)
                              onClicked: {
                                var selfUuid = String((rowRoot.taskSrc && rowRoot.taskSrc.uuid)
                                  || (rowRoot.task && rowRoot.task.uuid)
                                  || root.expandedUuid || "")
                                rowRoot.flushFieldsToDrafts()
                                // Reverse link: other depends on this task.
                                root.removeDependency(parent.otherUuid, selfUuid)
                              }
                            }
                          }
                        }
                      }

                      Item {
                        width: parent.width
                        height: depCombo.visible ? depCombo.implicitHeight : noDepHint.implicitHeight

                        readonly property var depOptions: {
                          var _ = root.dataRev
                          var opts = [{ value: "", label: root.tr("addDep") }]
                          var selfUuid = rowRoot.taskSrc ? String(rowRoot.taskSrc.uuid || "") : ""
                          var cands = Model.pendingForDeps(root.snapshot.tasks || [], selfUuid)
                          var deps = rowRoot.liveDepends
                          for (var i = 0; i < cands.length; i++) {
                            var c = cands[i]
                            if (Model.listContains(deps, c.uuid)) continue
                            var mark = c.status === "completed" ? " ✓" : (c.status === "waiting" ? " …" : "")
                            var idBit = c.id ? ("#" + c.id + " ") : ""
                            opts.push({ value: String(c.uuid), label: idBit + c.description + mark })
                          }
                          return opts
                        }

                        Text {
                          textFormat: Text.PlainText
                          id: noDepHint
                          visible: parent.depOptions.length <= 1
                          width: parent.width
                          text: root.tr("noDepCandidates")
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          wrapMode: Text.WordWrap
                        }

                        Dropdown {
                          id: depCombo
                          visible: parent.depOptions.length > 1
                          width: parent.width
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          value: ""
                          options: parent.depOptions
                          onChanged: function(v) {
                            root.dlog("deps.combo.changed", {
                              value: String(v || ""),
                              options: (parent.depOptions && parent.depOptions.length) || 0,
                              self: String((rowRoot.task && rowRoot.task.uuid) || "")
                            })
                            if (!v) return
                            var uuid = String((rowRoot.taskSrc && rowRoot.taskSrc.uuid)
                              || (rowRoot.task && rowRoot.task.uuid)
                              || root.expandedUuid || "")
                            rowRoot.flushFieldsToDrafts()
                            value = ""
                            root.addDependency(uuid, v)
                          }
                        }
                      }
                    }

                    // —— 5. Time tracking (secondary) ————————
                    Column {
                      visible: !!(root.snapshot && root.snapshot.timewAvailable !== false)
                      width: parent.width
                      spacing: Style.space(4)

                      Text {
                        textFormat: Text.PlainText
                        text: root.tr("editSectionTime") + (
                          rowRoot.task && rowRoot.task.todayLabel
                            ? (" — " + root.tr("todayTime") + " " + rowRoot.task.todayLabel)
                            : (" — " + root.tr("todayTime") + " 0:00")
                        )
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      Row {
                        width: parent.width
                        spacing: Style.space(6)

                        TextField {
                          id: adjustTimeField
                          width: parent.width - Style.space(160)
                          foreground: root.foreground
                          placeholderText: root.tr("adjustTimeHint")
                          verticalPadding: Style.space(2)
                          onActiveFocusChanged: root.formFocused = activeFocus
                          Keys.onEscapePressed: function(event) { root.escapeFromField(event) }
                          Keys.onReturnPressed: function(event) {
                            rowRoot.flushFieldsToDrafts()
                            root.adjustTime(rowRoot.taskSrc, text, false)
                            event.accepted = true
                          }
                        }
                        Button {
                          anchors.verticalCenter: adjustTimeField.verticalCenter
                          height: adjustTimeField.height
                          text: root.tr("timeAdd")
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          fontSize: Style.font.caption
                          verticalPadding: Style.space(2)
                          horizontalPadding: Style.space(6)
                          onClicked: {
                            rowRoot.flushFieldsToDrafts()
                            root.adjustTime(rowRoot.taskSrc, adjustTimeField.text, false)
                          }
                        }
                        Button {
                          anchors.verticalCenter: adjustTimeField.verticalCenter
                          height: adjustTimeField.height
                          text: root.tr("timeRemove")
                          foreground: root.urgent
                          fontFamily: root.fontFamily
                          fontSize: Style.font.caption
                          verticalPadding: Style.space(2)
                          horizontalPadding: Style.space(6)
                          onClicked: {
                            rowRoot.flushFieldsToDrafts()
                            root.adjustTime(rowRoot.taskSrc, adjustTimeField.text, true)
                          }
                        }
                      }
                    }

                    } // end advanced spoiler (schedule / links / time)

                    // —— 6. Actions ————————————————————————
                    Row {
                      spacing: Style.space(6)

                      // Always the same Button chrome so label baseline does
                      // not jump between dirty/idle. Idle: dimmed + eat clicks
                      // so they never fall through to the list.
                      Item {
                        id: saveWrap
                        width: saveBtn.implicitWidth
                        height: saveBtn.implicitHeight

                        Button {
                          id: saveBtn
                          anchors.fill: parent
                          text: root.tr("save") + root.hkHintCommit
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          fontSize: Style.font.caption
                          opacity: root.editDirty ? 1 : 0.4
                          onClicked: {
                            if (!root.editDirty) return
                            rowRoot.flushFieldsToDrafts()
                            var s = rowRoot.captureEditorValues()
                            root.saveTask(
                              rowRoot.taskSrc,
                              s.description,
                              s.project,
                              s.priority,
                              s.scheduled,
                              s.due,
                              s.details
                            )
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          enabled: !root.editDirty
                          hoverEnabled: true
                          preventStealing: true
                          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                          cursorShape: Qt.ArrowCursor
                          onPressed: function(mouse) { mouse.accepted = true }
                          onClicked: function(mouse) { mouse.accepted = true }
                        }
                      }

                      Button {
                        text: root.tr("cancel") + root.hkHintCancel
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        onClicked: root.requestCloseEditor({ type: "dismiss" })
                      }

                      Button {
                        text: root.tr("deleteTask") + root.hkHintDestroy
                        foreground: root.urgent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        onClicked: root.requestDelete(rowRoot.taskSrc)
                      }
                    }
                  }
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              visible: root.rows.length === 0
              text: root.snapshot.available === false ? root.tr("missingTaskwarrior") : root.tr("noTasks")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: root.foreground
            MouseArea {
              anchors.fill: parent
              onClicked: root.dismissOverlays()
            }
          }

          // Sticky bottom composer — docked to the panel bottom via Layout.
          // Title row always stays in-window; expanded fields scroll inside.
          FocusScope {
            id: composerScope
            Layout.fillWidth: true
            Layout.preferredHeight: taskComposer.implicitHeight
            Layout.alignment: Qt.AlignBottom
            implicitHeight: taskComposer.implicitHeight
            clip: true

            onActiveFocusChanged: {
              if (!activeFocus)
                root.maybeCollapseComposer()
            }

            Column {
              id: taskComposer
              width: composerScope.width
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(6)
                readonly property bool canAdd: String(addField.text || "").trim() !== ""

                TextField {
                  id: addField
                  width: parent.width - addBtnWrap.width - Style.space(6)
                  foreground: root.foreground
                  placeholderText: root.tr("addPlaceholder")
                  verticalPadding: Style.space(4)
                onActiveFocusChanged: {
                  if (activeFocus) {
                    if (root.expandedUuid) {
                      root.requestCloseEditor({ type: "dismiss", thenCompose: true })
                      if (root.editDirty) {
                        // Dialog open — don't steal focus into composer yet.
                        return
                      }
                    }
                    root.composerExpanded = true
                  } else {
                    root.maybeCollapseComposer()
                  }
                  root.formFocused = activeFocus
                    || (addDetailsField && addDetailsField.activeFocus)
                    || (addWaitingForField && addWaitingForField.activeFocus)
                    || (addScheduledField && addScheduledField.fieldFocused)
                    || (addDueField && addDueField.fieldFocused)
                    || root.datePickerCount > 0
                    || (priorityCombo && priorityCombo.popupOpen)
                    || (projectCombo && projectCombo.popupOpen)
                    || (addDepCombo && addDepCombo.popupOpen)
                }
                  onAccepted: {
                    if (parent.canAdd) root.addTask()
                  }
                  Keys.onEscapePressed: function(event) { root.escapeFromField(event) }
                }

                Item {
                  id: addBtnWrap
                  anchors.verticalCenter: addField.verticalCenter
                  width: addBtn.implicitWidth
                  height: addField.height

                  Button {
                    id: addBtn
                    anchors.fill: parent
                    text: root.tr("addTaskBtn") + root.hkHintCommit
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    verticalPadding: Style.space(4)
                    horizontalPadding: Style.space(10)
                    opacity: parent.parent.canAdd ? 1 : 0.4
                    onClicked: {
                      if (!parent.parent.canAdd) return
                      root.addTask()
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: !parent.parent.canAdd
                    hoverEnabled: true
                    preventStealing: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.ArrowCursor
                    onPressed: function(mouse) { mouse.accepted = true }
                    onClicked: function(mouse) { mouse.accepted = true }
                  }
                }
              }

              ScrollView {
                id: composerBodyScroll
                visible: root.composerExpanded
                width: parent.width
                // Cap expanded fields so the title row never leaves the panel.
                height: root.composerExpanded
                  ? Math.min(composerBody.implicitHeight + Style.space(4), Style.space(280))
                  : 0
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: contentHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                Column {
                  id: composerBody
                  width: composerBodyScroll.width
                  spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              text: root.tr("details")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              id: addDetailsBox
              width: parent.width
              height: Style.space(72)
              radius: Style.cornerRadius
              color: Style.controlFill(addDetailsField.activeFocus, addDetailsHover.hovered, root.foreground, Color.accent)
              border.color: addDetailsField.activeFocus
                ? Color.accent
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
              border.width: 1

              HoverHandler { id: addDetailsHover }

              ScrollView {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                TextArea {
                  textFormat: Text.PlainText
                  id: addDetailsField
                  width: addDetailsBox.width - Style.space(12)
                  wrapMode: TextArea.Wrap
                  selectByMouse: true
                  color: root.foreground
                  placeholderText: root.tr("detailsHint")
                  placeholderTextColor: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  background: Item {}
                  onActiveFocusChanged: root.formFocused = activeFocus
                  Keys.onEscapePressed: function(event) { root.escapeFromField(event) }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              text: root.tr("editSectionPlan")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.tr("status")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Row {
              spacing: Style.space(4)
              Button {
                text: root.tr("waiting")
                selected: root.addStatus === "waiting"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.space(1)
                horizontalPadding: Style.space(6)
                onClicked: root.addStatus = "waiting"
              }
              Button {
                text: root.tr("pending")
                selected: root.addStatus === "pending"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.space(1)
                horizontalPadding: Style.space(6)
                onClicked: root.addStatus = "pending"
              }
              Button {
                text: root.tr("done")
                selected: root.addStatus === "completed"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.space(1)
                horizontalPadding: Style.space(6)
                onClicked: root.addStatus = "completed"
              }
            }

            Column {
              visible: root.addStatus === "waiting"
              width: parent.width
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                text: root.tr("waitingFor")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              TextField {
                id: addWaitingForField
                width: parent.width
                foreground: root.foreground
                placeholderText: root.tr("waitingForHint")
                verticalPadding: Style.space(2)
                onActiveFocusChanged: root.formFocused = activeFocus
                Keys.onEscapePressed: function(event) { root.escapeFromField(event) }
              }
            }

            Column {
              visible: root.addStatus === "completed"
              width: parent.width
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                text: root.tr("outcome")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              TextField {
                id: addOutcomeField
                width: parent.width
                foreground: root.foreground
                placeholderText: root.tr("outcomeHint")
                verticalPadding: Style.space(2)
                onActiveFocusChanged: root.formFocused = activeFocus
                Keys.onEscapePressed: function(event) { root.escapeFromField(event) }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: (parent.width - Style.space(8)) / 2
                spacing: Style.space(4)

                Text {
                  textFormat: Text.PlainText
                  text: root.tr("priority")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Dropdown {
                  id: priorityCombo
                  width: parent.width
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  value: ""
                  options: [
                    { value: "", label: root.tr("priorityNone") },
                    { value: "H", label: root.tr("priH") },
                    { value: "M", label: root.tr("priM") },
                    { value: "L", label: root.tr("priL") }
                  ]
                }
              }

              Column {
                width: (parent.width - Style.space(8)) / 2
                spacing: Style.space(4)

                Text {
                  textFormat: Text.PlainText
                  text: root.tr("project")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Dropdown {
                  id: projectCombo
                  width: parent.width
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  value: ""
                  options: {
                    var opts = [{ value: "", label: root.tr("projectNone") }]
                    for (var i = 0; i < root.projectList.length; i++)
                      opts.push({ value: root.projectList[i], label: root.projectList[i] })
                    return opts
                  }
                }
              }
            }

            Button {
              text: (root.showAddAdvanced ? "▾ " : "▸ ") + (
                root.showAddAdvanced ? root.tr("advancedHide") : root.tr("advancedShow")
              )
              foreground: root.dim
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              onClicked: root.showAddAdvanced = !root.showAddAdvanced
            }

            Column {
              visible: root.showAddAdvanced
              width: parent.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: root.tr("editSectionSchedule")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: Style.space(6)
                rowSpacing: Style.space(4)

                Text {
                  textFormat: Text.PlainText
                  text: root.tr("startDate")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                DateTimeField {
                  id: addScheduledField
                  Layout.fillWidth: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  host: root
                  placeholderText: root.tr("datesHint")
                  trToday: root.tr("dueToday")
                  trClear: root.tr("dateClear")
                  trApply: root.tr("dateApply")
                  trTime: root.tr("dateTime")
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.tr("endDate")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                DateTimeField {
                  id: addDueField
                  Layout.fillWidth: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  host: root
                  placeholderText: root.tr("datesHint")
                  trToday: root.tr("dueToday")
                  trClear: root.tr("dateClear")
                  trApply: root.tr("dateApply")
                  trTime: root.tr("dateTime")
                }
              }

              Text {
                textFormat: Text.PlainText
                text: root.tr("editSectionLinks")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Column {
                visible: (root.addDepUuids || []).length > 0
                width: parent.width
                spacing: Style.space(2)

                Repeater {
                  model: root.addDepUuids || []
                  Row {
                    required property var modelData
                    readonly property string depId: String(modelData)
                    width: parent.width
                    spacing: Style.space(6)
                    Text {
                      textFormat: Text.PlainText
                      text: {
                        var dep = Model.findTask(root.snapshot.tasks || [], parent.depId)
                        if (!dep) return parent.depId
                        var idBit = dep.id ? ("#" + dep.id + " ") : ""
                        return idBit + dep.description
                      }
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      width: parent.width - Style.space(60)
                      elide: Text.ElideRight
                    }
                    Button {
                      text: root.tr("removeDep")
                      foreground: root.urgent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.caption
                      verticalPadding: Style.space(1)
                      horizontalPadding: Style.space(4)
                      onClicked: root.removeComposerDep(parent.depId)
                    }
                  }
                }
              }

              Item {
                width: parent.width
                height: addDepCombo.visible ? addDepCombo.implicitHeight : addNoDepHint.implicitHeight

                readonly property var depOptions: {
                  var opts = [{ value: "", label: root.tr("addDep") }]
                  var cands = Model.pendingForDeps(root.snapshot.tasks || [], "")
                  var deps = root.addDepUuids || []
                  for (var i = 0; i < cands.length; i++) {
                    var c = cands[i]
                    if (Model.listContains(deps, c.uuid)) continue
                    var mark = c.status === "completed" ? " ✓" : (c.status === "waiting" ? " …" : "")
                    var idBit = c.id ? ("#" + c.id + " ") : ""
                    opts.push({ value: String(c.uuid), label: idBit + c.description + mark })
                  }
                  return opts
                }

                Text {
                  textFormat: Text.PlainText
                  id: addNoDepHint
                  visible: parent.depOptions.length <= 1
                  width: parent.width
                  text: root.tr("noDepCandidates")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Dropdown {
                  id: addDepCombo
                  visible: parent.depOptions.length > 1
                  width: parent.width
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  value: ""
                  options: parent.depOptions
                  onChanged: function(v) {
                    if (!v) return
                    root.addComposerDep(v)
                    value = ""
                  }
                }
              }

              Column {
                visible: !!(root.snapshot && root.snapshot.timewAvailable !== false)
                width: parent.width
                spacing: Style.space(4)

                Text {
                  textFormat: Text.PlainText
                  text: root.tr("editSectionTime")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Toggle {
                  width: parent.width
                  label: root.tr("startTimerOnCreate")
                  checked: root.addStartTimer
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  titleSize: Style.font.caption
                  onClicked: root.addStartTimer = !root.addStartTimer
                }
              }
            }
            } // composerBody
            } // composerBodyScroll
            } // taskComposer
          } // composerScope
        }

        // Projects view
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.space(8)
          visible: root.viewMode === "projects"

          ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Style.space(120)
            clip: true
            model: {
              var rows = []
              for (var i = 0; i < root.projectList.length; i++)
                rows.push({ name: root.projectList[i], label: root.projectList[i], kind: "project" })
              return rows
            }
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
              policy: parent.contentHeight > parent.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            delegate: Rectangle {
              id: projectDelegate
              required property var modelData
              required property int index
              width: ListView.view.width
              height: projRow.implicitHeight + Style.space(8)
              radius: Style.cornerRadius
              color: root.projectFilter === modelData.name
                ? Style.hoverFillFor(root.foreground, Color.accent)
                : "transparent"

              readonly property bool renaming: root.renameFrom === modelData.name

              // Three aligned columns: name | rename | clear
              RowLayout {
                id: projRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(4)
                spacing: Style.space(6)

                Button {
                  Layout.fillWidth: true
                  Layout.preferredWidth: 1
                  Layout.alignment: Qt.AlignVCenter
                  visible: !projectDelegate.renaming
                  text: modelData.label
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.body
                  leftAlign: true
                  onClicked: {
                    root.cancelRenameProject()
                    root.setProjectFilter(modelData.name)
                    root.viewMode = "tasks"
                    root.groupBy = "project"
                  }
                }

                TextField {
                  id: renameInlineField
                  Layout.fillWidth: true
                  Layout.preferredWidth: 1
                  Layout.alignment: Qt.AlignVCenter
                  visible: projectDelegate.renaming
                  foreground: root.foreground
                  verticalPadding: Style.space(3)
                  onVisibleChanged: {
                    if (visible) {
                      text = modelData.name
                      root.renameTo = modelData.name
                      Qt.callLater(function () {
                        renameInlineField.forceActiveFocus()
                        renameInlineField.selectAll()
                      })
                    }
                  }
                  onTextChanged: {
                    if (visible)
                      root.renameTo = text
                  }
                  onAccepted: root.renameProject()
                  Keys.onEscapePressed: function(event) {
                    root.escapeFromField(event)
                  }
                }

                Button {
                  Layout.fillWidth: true
                  Layout.preferredWidth: 1
                  Layout.alignment: Qt.AlignVCenter
                  visible: modelData.kind === "project"
                  text: projectDelegate.renaming
                    ? (root.tr("save") + root.hkHintCommit)
                    : root.tr("rename")
                  foreground: root.dim
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: {
                    if (projectDelegate.renaming) {
                      root.renameProject()
                    } else {
                      root.renameFrom = modelData.name
                      root.renameTo = modelData.name
                    }
                  }
                }
                Button {
                  Layout.fillWidth: true
                  Layout.preferredWidth: 1
                  Layout.alignment: Qt.AlignVCenter
                  visible: modelData.kind === "project"
                  text: projectDelegate.renaming
                    ? (root.tr("cancel") + root.hkHintCancel)
                    : root.tr("clearProject")
                  foreground: projectDelegate.renaming ? root.dim : root.urgent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: {
                    if (projectDelegate.renaming)
                      root.cancelRenameProject()
                    else
                      root.requestClearProject(modelData.name)
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              visible: root.projectList.length === 0
              text: root.tr("noProjects")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: root.foreground
          }

          Row {
            Layout.fillWidth: true
            spacing: Style.space(6)
            TextField {
              id: newProjectField
              width: parent.width - createProjBtn.width - Style.space(6)
              foreground: root.foreground
              placeholderText: root.tr("newProject")
              verticalPadding: Style.space(4)
              onAccepted: root.createProjectName()
            }
            Button {
              id: createProjBtn
              anchors.verticalCenter: newProjectField.verticalCenter
              height: newProjectField.height
              text: root.tr("add") + root.hkHintCommit
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              verticalPadding: Style.space(4)
              onClicked: root.createProjectName()
            }
          }
        }

        // About view — hero + sections (links / language / debug)
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 0
          visible: root.viewMode === "about"

          Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: aboutBody.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: aboutBody
              width: parent.width
              spacing: Style.space(16)
              topPadding: Style.space(8)
              bottomPadding: Style.space(16)

              PanelHero {
                width: parent.width
                title: root.tr("aboutTitle")
                detail: "v" + root.pluginVersion
                meta: root.tr("aboutDeveloper") + " · " + root.tr("aboutDeveloperName")
                foreground: root.foreground
                fontFamily: root.fontFamily
                iconComponent: Component {
                  Text {
                    textFormat: Text.PlainText
                    text: "\uf0ae"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                  }
                }
              }

              PanelSeparator { foreground: root.foreground }

              Column {
                width: parent.width
                spacing: Style.space(8)

                PanelSectionHeader {
                  text: root.tr("aboutLinks").toUpperCase()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Column {
                  width: parent.width
                  spacing: Style.space(4)

                  Button {
                    width: parent.width
                    text: root.tr("aboutChangelog")
                    iconText: "\uf15c"
                    bordered: true
                    leftAlign: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    verticalPadding: Style.space(6)
                    horizontalPadding: Style.space(10)
                    onClicked: Qt.openUrlExternally(root.changelogUrl)
                  }
                  Button {
                    width: parent.width
                    text: root.tr("aboutMarketplace")
                    iconText: "\uf07a"
                    bordered: true
                    leftAlign: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    verticalPadding: Style.space(6)
                    horizontalPadding: Style.space(10)
                    onClicked: Qt.openUrlExternally(root.marketplaceUrl)
                  }
                  Button {
                    width: parent.width
                    text: root.tr("aboutNewIssue")
                    iconText: "\uf071"
                    bordered: true
                    leftAlign: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    verticalPadding: Style.space(6)
                    horizontalPadding: Style.space(10)
                    onClicked: Qt.openUrlExternally(root.newIssueUrl)
                  }
                  Button {
                    width: parent.width
                    text: root.tr("aboutGithub")
                    iconText: "\uf09b"
                    bordered: true
                    leftAlign: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    verticalPadding: Style.space(6)
                    horizontalPadding: Style.space(10)
                    onClicked: Qt.openUrlExternally(root.githubUrl)
                  }
                }
              }

              PanelSeparator { foreground: root.foreground }

              Column {
                width: parent.width
                spacing: Style.space(8)

                PanelSectionHeader {
                  text: root.tr("uiLanguage").toUpperCase()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Row {
                  spacing: Style.space(4)

                  Button {
                    text: root.tr("uiLanguageSystem")
                    selected: root.uiLanguage === "system"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    verticalPadding: Style.space(2)
                    horizontalPadding: Style.space(8)
                    onClicked: root.setUiLanguage("system")
                  }
                  Button {
                    text: root.tr("uiLanguageRu")
                    selected: root.uiLanguage === "ru"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    verticalPadding: Style.space(2)
                    horizontalPadding: Style.space(8)
                    onClicked: root.setUiLanguage("ru")
                  }
                  Button {
                    text: root.tr("uiLanguageEn")
                    selected: root.uiLanguage === "en"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    verticalPadding: Style.space(2)
                    horizontalPadding: Style.space(8)
                    onClicked: root.setUiLanguage("en")
                  }
                }
              }

              PanelSeparator { foreground: root.foreground }

              Column {
                width: parent.width
                spacing: Style.space(8)

                PanelSectionHeader {
                  text: root.tr("debugLog").toUpperCase()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Toggle {
                  width: parent.width
                  label: root.debugLogging ? root.tr("debugLogOn") : root.tr("debugLogOff")
                  description: root.debugLogPath || "~/.local/share/taskwarrior-time/debug.log"
                  checked: root.debugLogging
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  titleSize: Style.font.body
                  descriptionSize: Style.font.caption
                  onClicked: root.setDebugLogging(!root.debugLogging)
                }

                Button {
                  width: parent.width
                  text: root.tr("aboutOpenLogFolder")
                  iconText: "\uf07b"
                  bordered: true
                  leftAlign: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.body
                  verticalPadding: Style.space(6)
                  horizontalPadding: Style.space(10)
                  onClicked: root.openDebugLogFolder()
                }

                Button {
                  width: parent.width
                  text: root.tr("aboutClearLogs")
                  iconText: "\uf1f8"
                  bordered: true
                  leftAlign: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.body
                  verticalPadding: Style.space(6)
                  horizontalPadding: Style.space(10)
                  onClicked: root.clearDebugLogs()
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.tr("debugLogHint")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }
      }

      HintConfirmDialog {
        id: confirmDelete
        anchors.fill: parent
        message: root.tr("confirmDelete")
        cancelText: root.tr("cancel")
        confirmText: root.tr("confirm")
        cancelHint: "Esc"
        confirmHint: "Ctrl+Enter"
        foreground: root.foreground
        background: Color.popups.background
        fontFamily: root.fontFamily
        onCanceled: { opened = false; root.pendingDeleteUuid = "" }
        onConfirmed: root.confirmDeleteTask()
      }

      HintConfirmDialog {
        id: confirmClear
        anchors.fill: parent
        message: root.tr("confirmClearProject")
        cancelText: root.tr("cancel")
        confirmText: root.tr("confirm")
        cancelHint: "Esc"
        confirmHint: "Ctrl+Enter"
        foreground: root.foreground
        background: Color.popups.background
        fontFamily: root.fontFamily
        onCanceled: { opened = false; root.pendingClearProject = "" }
        onConfirmed: root.confirmClearProjectAction()
      }

      // Unsaved editor changes: Save / Continue / Discard
      Item {
        id: confirmUnsaved
        anchors.fill: parent
        property bool opened: false
        property int selectedIndex: 0
        visible: opened
        z: 20

        function handleKey(event) {
          if (!opened) return false
          if (event.key === Qt.Key_Escape) {
            root.confirmUnsavedContinue()
            return true
          }
          if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
              && (event.modifiers & Qt.ControlModifier)) {
            root.confirmUnsavedSave()
            return true
          }
          if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
              && (event.modifiers & Qt.ControlModifier)) {
            root.confirmUnsavedDiscard()
            return true
          }
          if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
            selectedIndex = (selectedIndex + 2) % 3
            return true
          }
          if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            selectedIndex = (selectedIndex + 1) % 3
            return true
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (selectedIndex === 0) root.confirmUnsavedSave()
            else if (selectedIndex === 1) root.confirmUnsavedContinue()
            else root.confirmUnsavedDiscard()
            return true
          }
          return false
        }

        Rectangle {
          anchors.fill: parent
          color: Util.alpha(Color.background, 0.7)
          MouseArea {
            anchors.fill: parent
            onClicked: root.confirmUnsavedContinue()
          }

          BorderSurface {
            id: unsavedCard
            width: Math.min(parent.width - Style.space(32), Style.space(420))
            height: unsavedInner.implicitHeight
              + unsavedCard.contentTopInset + unsavedCard.contentBottomInset
            anchors.centerIn: parent
            color: Color.popups.background
            borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
            padding: Style.space(24)
            radius: Style.cornerRadius

            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
              id: unsavedInner
              x: unsavedCard.contentLeftInset
              y: unsavedCard.contentTopInset
              width: unsavedCard.width - unsavedCard.contentLeftInset - unsavedCard.contentRightInset
              spacing: Style.space(20)

              Text {
                textFormat: Text.PlainText
                id: msg
                width: parent.width
                text: root.tr("unsavedChanges")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(10)

                Repeater {
                  model: [
                    { label: root.tr("unsavedSave"), hint: "Ctrl+Enter", action: "save" },
                    { label: root.tr("unsavedContinue"), hint: "Esc", action: "continue" },
                    { label: root.tr("unsavedDiscard"), hint: "Ctrl+Delete", action: "discard" }
                  ]

                  BorderSurface {
                    required property int index
                    required property var modelData
                    readonly property bool selected: confirmUnsaved.selectedIndex === index
                    readonly property bool destructive: modelData.action === "discard"

                    width: Math.max(Style.space(88), btnCol.implicitWidth + Style.space(20))
                    height: Math.max(Style.space(44), btnCol.implicitHeight + Style.space(10))
                    color: selected
                      ? (destructive ? Util.alpha(Color.urgent, 0.22) : Util.alpha(root.foreground, 0.08))
                      : "transparent"
                    borderSpec: Border.flat(
                      destructive
                        ? (selected ? Color.urgent : Util.alpha(Color.urgent, 0.56))
                        : (selected ? Color.accent : Util.alpha(root.foreground, 0.38)),
                      Style.normalBorderWidth)
                    radius: 0

                    Column {
                      id: btnCol
                      anchors.centerIn: parent
                      spacing: Style.space(1)

                      Text {
                        textFormat: Text.PlainText
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label
                        color: destructive
                          ? (selected ? Color.urgent : root.foreground)
                          : (selected ? Color.accent : root.foreground)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        textFormat: Text.PlainText
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.hint
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption * 0.85
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: confirmUnsaved.selectedIndex = index
                      onClicked: {
                        if (modelData.action === "save") root.confirmUnsavedSave()
                        else if (modelData.action === "continue") root.confirmUnsavedContinue()
                        else root.confirmUnsavedDiscard()
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  IpcHandler {
    target: "taskwarrior-time"
    function refresh(): void { root.refresh() }
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function about(): void {
      root.openFromHotkey()
      root.viewMode = "about"
    }
  }

  Component.onCompleted: {
    root.rebuildRows(true)
    root.loadDebugSettings()
    refresh()
  }
}

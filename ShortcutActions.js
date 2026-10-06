function openNewTask(panel, defer) {
  panel.viewMode = "tasks"
  panel.openFromHotkey()
  defer(function() {
    panel.focusNewTaskComposer()
  })
}

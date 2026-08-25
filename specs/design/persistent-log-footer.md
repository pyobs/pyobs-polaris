# Persistent log footer

Status: implemented, closed.

Direct request: ports pyobs-gui's `MainWindow` (`mainwindow.py`'s
`splitterLog` - a vertical splitter always showing `tableLog` below the
nav+content area, regardless of which page is selected, default height
100px). `MainWindow.qml`'s single `RowLayout` is now the top pane of a
vertical `SplitView`, with a new `qml/widgets/LogFooter.qml` as the
bottom pane (`SplitView.preferredHeight: 140`, draggable like the
Python original).

`LogFooter.qml` is a **deliberate duplicate** of `LogsView.qml`'s
rendering (time/level-colored/module/message rows, same
`entriesOfType("LogEvent")` + recompute-on-`rowsInserted`/`modelReset`
pattern) - no per-module filter, no Clear button, on direct
instruction: the Logs page is getting real filtering next, and this
footer is expected to diverge from it once that lands rather than
share one component now only to be untangled later.


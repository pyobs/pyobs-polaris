import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import pyobs.polaris

// Ports pyobs-web-client's AppLayout.vue: a left sidebar nav (Status,
// then a "Tools" group - Shell/Logs - then a conditionally-visible
// "Modules" group for device-specific pages like Roof/Auto Focus) plus a
// main content area showing whichever page is selected - RouterView's
// equivalent here is a plain StackLayout, since this project has no
// separate routing concept. Icon glyphs are plain Unicode characters
// (no bundled icon font/theme here, unlike the web client's Bootstrap
// Icons), chosen to read the same at a glance: a status dot, a
// terminal prompt, a lined page, a house, a focus-ring target.
ApplicationWindow {
    id: root
    width: 900
    height: 700
    title: "Polaris"

    Material.theme: Material.Dark

    // A sidebar entry: an icon glyph before the label, matching
    // AppLayout.vue's `d-flex align-items-center gap-2` links. Kept as an
    // inline component (Qt 6.5+) since it's only ever used within this
    // one file's sidebar, not a general-purpose widget.
    component SidebarItem: ItemDelegate {
        id: sidebarItem
        property string iconGlyph: ""

        Layout.fillWidth: true

        contentItem: RowLayout {
            spacing: 8

            Label {
                Layout.preferredWidth: 18
                horizontalAlignment: Text.AlignHCenter
                text: sidebarItem.iconGlyph
            }

            Label {
                Layout.fillWidth: true
                text: sidebarItem.text
                elide: Text.ElideRight
            }
        }
    }

    // Section header above a group of sidebar entries, matching
    // AppLayout.vue's small uppercase muted "Tools"/"Modules" labels -
    // callers pass the text already uppercased.
    component SidebarSectionLabel: Label {
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.leftMargin: 12
        Layout.bottomMargin: 2
        color: "grey"
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 1
    }

    required property var xmppClient
    required property var appSettings

    // TODO.md's "Plugin mechanism for custom module widgets", step 1: a
    // registry mapping an interface (or a specific module) to a sidebar
    // entry/page, so the "Roof"/"Auto Focus"/"Acquisition"/"Auto Guiding"/
    // "Mode" sidebar items and StackLayout pages below are generic
    // Repeaters instead of one hand-written pair per widget. Built-in
    // widgets register themselves once at startup (Component.onCompleted
    // below); step 2's PluginLoader has loaded external .qml plugins
    // register the same way, through this same registry.
    WidgetRegistry {
        id: widgetRegistry
    }

    // Step 2: scans AppSettings::pluginsDirectory for .qml files and
    // registers each one into widgetRegistry above - see PluginLoader.qml
    // for the plugin file contract. A no-op (nothing to load) while
    // pluginsDirectory is unset, its default.
    PluginLoader {
        id: pluginLoader
        xmppClient: root.xmppClient
        registry: widgetRegistry
    }

    // One Component per built-in widget, capturing root.xmppClient via
    // closure exactly like every other page below already does - declared
    // here (not inline at registration time) since Component.onCompleted
    // is imperative JS and can't declare a Component value itself.
    property Component roofComponent: Component {
        RoofView { xmppClient: root.xmppClient }
    }
    property Component autoFocusComponent: Component {
        AutoFocusView { xmppClient: root.xmppClient }
    }
    property Component acquisitionComponent: Component {
        AcquisitionView { xmppClient: root.xmppClient }
    }
    property Component autoGuidingComponent: Component {
        AutoGuidingView { xmppClient: root.xmppClient }
    }
    property Component modeComponent: Component {
        ModeView { xmppClient: root.xmppClient }
    }
    property Component weatherComponent: Component {
        WeatherView { xmppClient: root.xmppClient }
    }
    property Component telescopeComponent: Component {
        TelescopeView { xmppClient: root.xmppClient; appSettings: root.appSettings }
    }
    property Component cameraComponent: Component {
        CameraView { xmppClient: root.xmppClient }
    }

    // Per-entry visibility (same order/length as widgetRegistry.entries),
    // recomputed explicitly on every module-list change - WidgetRegistry's
    // isVisible() is a plain query, not a live binding, same as
    // ModuleListModel::hasInterface()'s existing callers. Deliberately a
    // parallel array of booleans, not a filtered subset of entries: every
    // registered widget's Component is always instantiated (see the
    // StackLayout Repeater below, over the *unfiltered* registry) - only
    // whether it's shown is dynamic. See WidgetRegistry.qml's own doc
    // comment on `entries` for why that matters (a real bug, caught live).
    property var visibilityByEntry: []

    function refreshVisibility() {
        root.visibilityByEntry = widgetRegistry.entries.map(
            (entry) => widgetRegistry.isVisible(entry, root.xmppClient.modules))
    }

    Connections {
        target: xmppClient.modules
        function onRowsInserted() { root.refreshVisibility() }
        function onRowsRemoved() { root.refreshVisibility() }
        function onModelReset() { root.refreshVisibility() }
        function onDataChanged() { root.refreshVisibility() }
    }

    Component.onCompleted: {
        widgetRegistry.registerForInterface("IRoof", { iconGlyph: "⌂", label: "Roof", component: root.roofComponent })
        widgetRegistry.registerForInterface("IAutoFocus",
            { iconGlyph: "◎", label: "Auto Focus", component: root.autoFocusComponent })
        widgetRegistry.registerForInterface("IAcquisition",
            { iconGlyph: "⊕", label: "Acquisition", component: root.acquisitionComponent })
        widgetRegistry.registerForInterface("IAutoGuiding",
            { iconGlyph: "⌖", label: "Auto Guiding", component: root.autoGuidingComponent })
        widgetRegistry.registerForInterface("IMode", { iconGlyph: "⇄", label: "Mode", component: root.modeComponent })
        widgetRegistry.registerForInterface("IWeather", { iconGlyph: "☁", label: "Weather", component: root.weatherComponent })
        widgetRegistry.registerForInterface("ITelescope", { iconGlyph: "🔭", label: "Telescope", component: root.telescopeComponent })
        widgetRegistry.registerForInterface("ICamera", { iconGlyph: "📷", label: "Camera", component: root.cameraComponent })

        pluginLoader.loadAll(root.appSettings.pluginFiles())

        root.refreshVisibility()
    }

    // The last module backing the currently-open dynamic page can
    // disconnect while that page is open - jump back to Status rather than
    // leaving the sidebar/StackLayout pointing at a now-hidden entry.
    // Static pages occupy indices 0-3 (Status/Shell/Logs/Events); dynamic
    // ones start at 4, one per widgetRegistry.entries position, in order
    // (stable regardless of visibility - see WidgetRegistry.qml).
    onVisibilityByEntryChanged: {
        const i = stack.currentIndex - 4
        if (i >= 0 && i < visibilityByEntry.length && !visibilityByEntry[i]) {
            stack.currentIndex = 0
        }
    }

    onClosing: Qt.quit()

    // Vertical split between the normal nav+content area and a persistent
    // log tail docked below it on every page - ports pyobs-gui's
    // MainWindow (mainwindow.py's splitterLog, always showing tableLog
    // beneath the nav/content splitter regardless of which page is
    // selected).
    SplitView {
        anchors.fill: parent
        orientation: Qt.Vertical

        // Horizontal split between the sidebar and the page content,
        // draggable the same way the log footer below is - the sidebar
        // was previously a fixed-width RowLayout child (Layout.preferredWidth:
        // 180, no way to resize it at all). SplitView's own handle
        // replaces the manual 1px Rectangle divider that used to sit
        // between them.
        SplitView {
            SplitView.fillHeight: true
            orientation: Qt.Horizontal

            ColumnLayout {
                SplitView.preferredWidth: 180
                SplitView.minimumWidth: 140
                spacing: 0

                Label {
                    Layout.margins: 12
                    text: "Polaris"
                    font.bold: true
                }

                SidebarItem {
                    iconGlyph: "●"
                    text: "Status"
                    highlighted: stack.currentIndex === 0
                    onClicked: stack.currentIndex = 0
                }

                SidebarSectionLabel { text: "TOOLS" }

                SidebarItem {
                    iconGlyph: "❯"
                    text: "Shell"
                    highlighted: stack.currentIndex === 1
                    onClicked: stack.currentIndex = 1
                }

                SidebarItem {
                    iconGlyph: "▤"
                    text: "Logs"
                    highlighted: stack.currentIndex === 2
                    onClicked: stack.currentIndex = 2
                }

                SidebarItem {
                    iconGlyph: "⚡"
                    text: "Events"
                    highlighted: stack.currentIndex === 3
                    onClicked: stack.currentIndex = 3
                }

                SidebarSectionLabel {
                    text: "MODULES"
                    visible: root.visibilityByEntry.some((v) => v)
                }

                // One entry per WidgetRegistry registration (not filtered
                // to currently-visible ones - see WidgetRegistry.qml's own
                // doc comment on `entries`) - position N here always
                // corresponds to StackLayout's dynamic page N below (index
                // 4 + N), since both Repeaters iterate the exact same
                // widgetRegistry.entries array in the same order.
                Repeater {
                    model: widgetRegistry.entries

                    delegate: SidebarItem {
                        required property var modelData
                        required property int index

                        iconGlyph: modelData.iconGlyph
                        text: modelData.label
                        visible: root.visibilityByEntry[index] === true
                        highlighted: stack.currentIndex === 4 + index
                        onClicked: stack.currentIndex = 4 + index
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#2d3035" }

                ColumnLayout {
                    Layout.margins: 12
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        Layout.fillWidth: true
                        text: root.xmppClient.jid
                        color: "grey"
                        elide: Text.ElideMiddle
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "Sign out"
                        onClicked: root.xmppClient.disconnectFromServer()
                    }
                }
            }

            StackLayout {
                id: stack
                SplitView.fillWidth: true
                currentIndex: 0

                StatusView {
                    Layout.margins: 16
                    xmppClient: root.xmppClient
                }

                ShellView {
                    Layout.margins: 16
                    xmppClient: root.xmppClient
                }

                LogsView {
                    Layout.margins: 16
                    xmppClient: root.xmppClient
                }

                EventsView {
                    Layout.margins: 16
                    xmppClient: root.xmppClient
                }

                // One dynamic page per WidgetRegistry registration, always
                // instantiated regardless of current visibility - Repeater
                // works as a direct StackLayout child the same way it
                // already does inside a plain Layout, injecting each
                // delegate as a StackLayout page in order (positions 4, 5,
                // 6, ... after the four static pages above, stable
                // regardless of which are currently shown in the sidebar).
                // A Loader is required here (not the widget directly)
                // since each position needs a *different* Component picked
                // at runtime - matches step 2's own planned `Loader{
                // source: ... }` mechanism for actual external plugin
                // files.
                //
                // Always eager, never gated on visibilityByEntry, on
                // purpose - see WidgetRegistry.qml's own doc comment on
                // `entries` for the real bug this avoids: instantiating a
                // widget lazily, only once its registration first becomes
                // visible, meant its internal per-module Repeater did its
                // initial bulk population against a model that could
                // already be mid-mutation from other modules concurrently
                // connecting, racing a dataChanged against that Repeater's
                // own construction and creating a spurious duplicate
                // delegate for a module that should only ever get one -
                // caught live (comparing screenshots against the
                // pre-refactor build), not by reasoning about the QML
                // alone. Every built-in widget was *always* eagerly
                // instantiated before this registry existed too, so this
                // isn't new behavior, just no longer hand-written per
                // widget.
                Repeater {
                    model: widgetRegistry.entries

                    delegate: Loader {
                        required property var modelData

                        Layout.margins: 16
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        sourceComponent: modelData.component
                    }
                }
            }
        }

        LogFooter {
            SplitView.preferredHeight: 140
            SplitView.minimumHeight: 60
            xmppClient: root.xmppClient
        }
    }
}

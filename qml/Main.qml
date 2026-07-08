import QtQuick
import pyobs.gui

// Entry point. Not a Window itself - just owns the one XmppClient
// instance (which must survive the login -> main window handoff, since
// it holds the live connection) and shows exactly one of LoginWindow /
// MainWindow at a time based on connection status, mirroring App.vue's
// status-driven swap between LoginView and AppLayout - just as two
// literal top-level windows instead of one page's body swapping,
// matching normal desktop-app conventions.
//
// QtObject, not Item: Item is a visual type that expects to belong to a
// QQuickWindow's scene graph. As the QQmlApplicationEngine root it never
// gets one (nothing ever shows it), and on this Qt 6.10.2/KWin-Wayland
// setup that silently breaks visibility of the Window children declared
// inside it - they get created (Component.onCompleted fires, no errors)
// but never actually map on the compositor. Confirmed by bisecting
// against a minimal reproduction outside this project.
//
// The child objects are held in uniquely-named properties (_client,
// _loginWindow, _mainWindow) purely because QtObject has no default
// property to assign bare child declarations to - the actual
// cross-references between them still go through `id: xmppClient`, not
// through those property names. Do not rename this to e.g.
// `property var xmppClient: XmppClient { ... }` and then write
// `xmppClient: xmppClient` on LoginWindow/MainWindow: with the property
// and the id sharing one name, that RHS `xmppClient` resolves to the
// enclosing object's *own* (not-yet-assigned) property of the same name
// before it falls back to the outer scope, so it silently binds to
// itself instead of the real client - LoginWindow/MainWindow then see
// `xmppClient` as undefined internally, exactly what happened here
// during development.
QtObject {
    property var _client: XmppClient {
        id: xmppClient
    }

    property var _settings: AppSettings {
        id: appSettings
    }

    property var _accounts: SavedAccountsModel {
        id: accountsModel
    }

    property var _loginWindow: LoginWindow {
        xmppClient: xmppClient
        appSettings: appSettings
        accountsModel: accountsModel
        visible: xmppClient.status !== "connected"
    }

    property var _mainWindow: MainWindow {
        xmppClient: xmppClient
        appSettings: appSettings
        visible: xmppClient.status === "connected"
    }
}

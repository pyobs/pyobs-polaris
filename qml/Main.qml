import QtQuick
import pyobs.gui

// Entry point. Not a Window itself - just owns the one XmppClient
// instance (which must survive the login -> main window handoff, since
// it holds the live connection) and shows exactly one of LoginWindow /
// MainWindow at a time based on connection status, mirroring App.vue's
// status-driven swap between LoginView and AppLayout - just as two
// literal top-level windows instead of one page's body swapping,
// matching normal desktop-app conventions.
Item {
    XmppClient {
        id: xmppClient
    }

    LoginWindow {
        xmppClient: xmppClient
        visible: xmppClient.status !== "connected"
    }

    MainWindow {
        xmppClient: xmppClient
        visible: xmppClient.status === "connected"
    }
}

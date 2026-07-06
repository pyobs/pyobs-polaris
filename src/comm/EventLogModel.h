#pragma once

#include <QAbstractListModel>
#include <QJsonObject>
#include <QString>
#include <QVariantList>
#include <QVector>
#include <qqmlintegration.h>

namespace comm {

// Same shape as pyobs-web-client's PyobsEvent type. Decoded from a raw JSON
// text payload (Python's Event.to_json(), see pyobs-core's events/event.py)
// - NOT the self-tagged WireValue vocabulary state/RPC use; events are
// plain JSON on the wire. `module` is derived client-side from the
// sender's JID, not itself part of the JSON payload.
struct PyobsEvent {
    QString type;
    QString module;
    double timestamp = 0;
    QString uuid;
    QJsonObject data;
};

// Bounded in-memory event log - same MAX_EVENTS-style cap as useXmpp.ts:
// unbounded growth in a long-running observatory-control session is a real
// problem, not a hypothetical one. `data`'s field order isn't preserved
// specially (unlike codec::WireDict for state) - LoggingView.vue looks up
// fields by name ("level", "message"), never iterates data generically, so
// there's nothing here that needs wire-order fidelity.
class EventLogModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Populated by XmppClient, not constructed directly in QML")

public:
    enum Role {
        TypeRole = Qt::UserRole + 1,
        ModuleRole,
        TimestampRole,
        UuidRole,
        DataRole,
    };
    Q_ENUM(Role)

    explicit EventLogModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Appends one event, dropping the oldest if already at capacity.
    void append(const PyobsEvent &event);

    // Matches useXmpp.ts's clearEvents().
    Q_INVOKABLE void clear();

    // A plain-JS-array snapshot of every currently-held event of a given
    // type (each entry a {type, module, timestamp, uuid, data} object) -
    // LogsView.qml's equivalent of LoggingView.vue's `events.value.filter(e
    // => e.type === 'LogEvent')`. QAbstractListModel doesn't give QML/JS
    // generic random-access iteration for free (only Repeater/ListView-style
    // delegate binding does), so this exists specifically so a plain QML JS
    // computed property (module filter dropdown, etc.) has something to
    // work with - recomputed on demand, not cached, since 500 entries max
    // is cheap to rescan.
    Q_INVOKABLE QVariantList entriesOfType(const QString &type) const;

private:
    static constexpr int kMaxEvents = 500;
    QVector<PyobsEvent> m_events;
};

}

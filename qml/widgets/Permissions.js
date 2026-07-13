.pragma library

// ACL / permitted-methods gating (TODO.md). Shared by every view/panel
// with an RPC-triggering Button - not duplicated per delegate the way
// findInterface()/fieldOf() are, since this is a pure predicate over
// already-decoded data (same reasoning as WireValueFormat.js's
// formatValueHtml()), and a fail-open security check is exactly the kind
// of logic where a single canonical copy matters.
//
// `permittedMethods` is ModuleListModel's PermittedMethodsRole value as
// read directly off a delegate's `required property var permittedMethods`
// (or `model.permittedMethods`) - undefined/null before the module's
// get_permitted_methods() RPC has resolved (or if it failed), a
// QVariantList of method-name strings once it has. Matching
// pyobs-gui's own BaseWidget.permitted() fallback, undefined/null means
// "permits everything", not "permits nothing".
function isPermitted(permittedMethods, methodName) {
    return permittedMethods === undefined || permittedMethods === null
        || permittedMethods.indexOf(methodName) !== -1
}

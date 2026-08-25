# Sidebar scroll indicator: Fusion's `ScrollBar` wasn't rendering at all

Status: implemented, closed.

Direct follow-up: "the scrollbar is barely visible. can we indicate
somehow that the list is longer?" Turned out worse than "barely visible"
under this project's own verification method - a screenshot with no
synthetic hover (nothing here can synthesize real pointer hover, see the
AT-SPI section's point 4) showed **zero** trace of the scrollbar at a
short window height, confirming it live rather than trusting the
Fusion-style default. Two things going on:

1. `ScrollBar`'s default look is transient (fades in only on hover/drag)
   - `policy: ScrollBar.AlwaysOn` fixes that half.
2. Overriding the attached `ScrollBar`'s `background`/`contentItem` to
   make it wider/higher-contrast (tried first) rendered *underneath* the
   sidebar items' own opaque `ItemDelegate` backgrounds instead of as a
   true overlay on top - visible proof caught live: an intentionally
   garish red/lime debug version showed only a tiny sliver peeking out
   near the "TOOLS" section label (the one spot with no opaque
   background above it), confirming the bar itself was there, just
   painted in the wrong stacking order to ever be seen normally.

Rather than keep fighting Fusion's `ScrollBar` template internals, gave
up on making the *real* scrollbar visible at all and instead drew an
independent, always-on-top indicator: a plain `Rectangle`, a sibling of
the `ScrollView` (not a child of it - a direct `Item`/`Rectangle` child
of a `ScrollView` becomes part of its *scrollable content*, not an
overlay, since `ScrollView`'s default property routes into the
Flickable), positioned from the attached `ScrollBar`'s own documented
`position`/`size` (0..1 fractions of the scrollable range) - a small
grey pill at the sidebar's right edge, `visible: sidebarScrollBar.size <
1.0` so it only appears at all when there's actually more to scroll to,
the same "the indicator not being there is itself information" property
`ScrollBar.AlwaysOn` was originally meant to provide. The real
`ScrollBar` stays attached underneath, still fully interactive for
dragging/wheel scroll - only its *visual* rendering was ever the
problem.


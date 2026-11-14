# Changelog

## 1.0.0 (unreleased)

First release.

- Every group loot roll in one window that opens by itself: one card per item (icon, name,
  type and level, seconds left, a countdown bar) with the whole group listed under it in the
  order of the party frames.
- Everyone's pick (Need, Greed, Transmog, Pass, or three dots while someone is still
  choosing) from the game's loot history, with the roll numbers spinning in as they arrive.
- The winner's row lights up with a crown and the others fade back. When you win, the item
  glows, a light sweeps the card and a soft chime plays. Ties show both numbers, and a roll
  everyone passed says so.
- Roll from the card: Need, Greed (Transmog when the game offers it) and Pass. A Need you
  can't make is greyed out with the game's reason. Blizzard's roll popups stay hidden while
  "Roll in Tutti" is on; soulbound items still get Blizzard's own confirmation. With it off
  you roll in Blizzard's popups and the cards show the group without buttons.
- A card that waits on you stays in sight: the window scrolls it into view whenever the
  cards change, nothing moves under the mouse right after your pick, and nothing folds
  under it while a card waits. In Recent rolls or Settings the count in the header shows the
  waiting card in the accent colour and leads back, and the window goes back to the rolls by
  itself 10 seconds before such a roll ends.
- Decided items fold into one line under "Done" while others are still open. The window
  closes itself after the last roll (5, 10, 20 or 30 seconds, or never), waits while the
  mouse is over it, and a new roll cancels the countdown.
- Recent rolls: the session's results (up to 100) by instance or zone and day, with
  everyone's picks one click away. Opened from the clock in the header, the addon
  compartment or `/tutti`; kept through `/reload`, cleared at login. The demo's results
  are marked "DEMO".
- A stack of an item shows its count on the item's icon, on the card and in Recent rolls.
- Raids: a card lists only the members who picked Need, Greed or Transmog, the winner and
  you, and folds everyone else into one line ("13 passed · 2 choosing") that opens.
- Item tooltips on hover, shift-click to link, ctrl-click for the dressing room. A BiS badge
  on the cards of items NaowhForever_BiS ranks for you. Polestar's note about a party
  member's quest item sits under the window.
- Settings in the window (the gear): Roll in Tutti, close after the last roll, sound when
  you win, accent (class colour or EllesmereUI's) and size (80 to 130 %). `/tutti`,
  `/tutti settings` and `/tutti demo`.
- Follows EllesmereUI's panel colour and font live; class colour accent by default. Works
  without EllesmereUI.
- Made for WoW Forever (Interface 16001).

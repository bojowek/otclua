# Loot-list configuration: native quick loot and vBot

This note records the configuration formats found in the local OTClient checkout
at `C:\Users\jakub\Documents\otclient_release`. It separates the native Tibia
15-style quick-loot list from vBot TargetBot corpse looting. They are different
systems and editing one does not configure the other.

## Short answer

There are three relevant locations:

| System | Local path | What it controls |
| --- | --- | --- |
| Native quick loot item list | `profiles/settings/<character>_containers.json` | Item IDs in the skipped or accepted quick-loot list |
| Native per-character analyser data | `profiles/characterdata/<numeric-id>/` | Analyser state, not the quick-loot list |
| luaclient per-character blacklist | `<bot-profile>/characterdata/<numeric-id>/blacklist.json` | Extra item IDs skipped by the headless corpse looter |
| vBot TargetBot | `profiles/bot/vBot_4.8/targetbot_configs/<name>.json` | Corpse items, loot containers, danger and capacity rules |

The word `containers` in the native filename is slightly misleading. The file
contains item filters. The destination container categories are supplied by the
server and selected through the quick-loot UI; they are not stored in the two
item arrays below.

## Native quick loot

The implementation is in the checkout's
`modules/game_quickloot/quickloot.lua`.

### File name and JSON shape

The file name is generated from the character name:

```lua
/settings/<lowercase-character-name-with-spaces-replaced-by-underscores>_containers.json
```

For example, the local checkout contains files such as
`profiles/settings/ben_song_containers.json`.

The JSON shape is:

```json
{
  "filter": 1,
  "loots": [
    [3582, 3577, 3283],
    [3031, 3043]
  ]
}
```

The array indexes are Lua indexes, so they start at 1:

| JSON member | UI label | Server filter byte | Meaning |
| --- | --- | ---: | --- |
| `loots[1]` | `skipped` | `0` | Blacklist: skip these item IDs |
| `loots[2]` | `accepted` | `1` | Whitelist: accept these item IDs |
| `filter` | currently selected tab | n/a | `1` selects skipped; `2` selects accepted |

An empty default file is therefore:

```json
{"filter":1,"loots":[[],[]]}
```

The numbers are client item IDs, not names. If an item has variants or a server
uses different item data, verify the ID against the active client's item data.

### Runtime flow

1. On game start, the module reads the character's `_containers.json` file.
2. It sends the selected list with
   `g_game.requestQuickLootBlackWhiteList(filter, count, itemIds)`.
3. Changing the skipped/accepted tab, adding an item, removing an item, or
   clearing the list sends the selected list again immediately.
4. On game end, both arrays are written back to the same character-named file.

The protocol map in this repository identifies the related client packet as
`0x91`, `ClientQuickLootBlackWhitelist`. The request contains the filter byte,
the item count, and the item IDs. This is why a local edit alone is not enough
for a live session: the client must send the changed list to the server.

### Destination containers

On login or when a corpse is opened, the server sends the available quick-loot
categories and their destination containers. In the local checkout this arrives
through `GameServerLootContainers` and is handled by `QuickLoot.start`.

The UI exposes categories such as Gold, Armors, Containers, Potions, Runes,
Shields, Tools and Weapons. Selecting an inventory container for a category
calls `g_game.openContainerQuickLoot(...)`. Those assignments are server-side
quick-loot settings, not entries in `<character>_containers.json`.

## `profiles/characterdata`

The requested directory contains numeric character identifiers, for example:

```text
profiles/characterdata/268741964/
```

The inspected directories contain files such as:

```text
damageinputanalyser.json
huntingsessionanalyser.json
impactanalyser.json
itemtracking.json
xpanalyser.json
```

Their contents are analyser settings and state. For example:

```json
{"trackedItems":[],"autoTrackAboveValue":0}
```

No quick-loot blacklist or whitelist was found there. The numeric directory is
therefore not the native loot-list location in this checkout. Do not move or
create `<character>_containers.json` under `profiles/characterdata`; the native
module looks under `/settings`.

This repository now uses the same character-id ownership model for its own
headless bot data. When `--bot`, `--cavebot`, or `--targetbot` is running, the
bot profile contains:

```text
<bot-profile>/characterdata/<playerId>/blacklist.json
```

The file is deliberately separate from the native `_containers.json` file and
from the shared vBot storage file:

```json
{"blacklist":[3031,3043]}
```

The IDs are skipped by corpse looting for that character only. The persistent
server `playerId` from `LoginSuccess` is used as the directory name, so two
characters using the same bot profile do not share this list. A session without
that ID (for example, an offline construction test) does not read or write a
shared fallback file.

The numeric directory is still useful evidence about ownership: these files are
scoped by the character identifier, while quick-loot files are scoped by the
lowercase character name. Treat the two scopes as separate persistence systems.

## vBot TargetBot looting

vBot loots corpses by opening the corpse as a normal container and moving
matching items into configured inventory containers. Its configuration is not
read by `game_quickloot`.

The selected TargetBot file is:

```text
<bot-profile>/targetbot_configs/<name>.json
```

The bot storage file remembers which TargetBot profile is selected:

```text
<bot-profile>/storage/profile_<N>.json
```

The TargetBot file has this relevant shape:

```json
{
  "targeting": [],
  "looting": {
    "items": [{"id": 3031, "count": 1}],
    "containers": [{"id": 2854, "count": 1}],
      "onlyConfiguredItems": true,
    "everyItem": false,
    "maxDanger": 10,
    "minCapacity": 100
  }
}
```

Meaning:

| Key | Meaning |
| --- | --- |
| `items` | Allow-list of corpse item IDs when `everyItem` is false |
| `containers` | Inventory container IDs vBot may use for loot |
| `onlyConfiguredItems` | Defaults to true. When true, only IDs in `items` are accepted, regardless of `everyItem`; set it to false to opt out. Food fallback is disabled in whitelist mode |
| `everyItem` | When true, loot every non-container item except IDs in `items` |
| `maxDanger` | Maximum TargetBot danger value at which looting is allowed |
| `minCapacity` | Minimum free capacity required before looting |

In the vBot UI, enabling **Loot every item, except these** changes `items` from
an allow-list into an ignore-list. `containers` remains the destination-container
allow-list in both modes.

For the native headless bot, server auto-loot mode is active. The server moves
accepted loot directly to the character's backpack, so the native looter does
not open corpses or move individual items. It only approaches nearby corpse
positions and sends `0x8F ClientSendQuickLoot` variant `2`. The TargetBot
`items`, `containers`, `everyItem`, `onlyConfiguredItems`, `maxDanger`,
`minCapacity`, and targeting `dontLoot` values do not control this native path.

Configure the server's own Quick Loot accepted/skip list through the server
Quick Loot UI or its native protocol. The headless client does not replace that
server list from TargetBot configuration.

The vBot implementation also mirrors the configured IDs into runtime tables
`vBot.lootItems` and `vBot.lootConainers`; those are derived values, not another
file format.

The repository's detailed vBot contract is in
[docs/vbot/config-compat-json.md](vbot/config-compat-json.md), and the behaviour
of corpse looting is described in [docs/vbot/targetbot.md](vbot/targetbot.md).

## Which system should be edited?

| Goal | Edit/configure |
| --- | --- |
| Tell the Tibia 15 quick-loot feature which item IDs to accept or skip | Native quick-loot UI, `0x91` (`filter` 0=skip, 1=accept), or `profiles/settings/<character>_containers.json` while a GUI client is closed |
| Make headless native Quick Loot accept only TargetBot items | Configure the server Quick Loot accepted list; native headless looting does not derive it from TargetBot config |
| Choose where native quick-loot categories go | Native quick-loot UI and the server-provided category mapping |
| Make vBot open corpses and move selected items | TargetBot looting panel and its `targetbot_configs/<name>.json` file |
| Make vBot use a backpack for loot | Add that backpack item ID to TargetBot `looting.containers` |
| Track item value or hunting statistics | The relevant `profiles/characterdata/<numeric-id>/*.json` analyser file |

## Safe manual editing

1. Close the OTClient before editing JSON. Both native quick loot and vBot can
   rewrite their in-memory state later and overwrite a manual change.
2. Preserve numeric item IDs and JSON array structure.
3. Keep `loots` as exactly two arrays in the native file.
4. For vBot, use objects with `id` and `count`; do not replace them with bare
   item IDs.
5. Start the client and confirm the UI shows the intended list. For a live
   server, changing the native list must also reach the server through the
   quick-loot request; a file copied into a running profile is not a live update.

## Evidence and limitations

This document is based on the local `otclient_release` source and profile data,
including `modules/game_quickloot/quickloot.lua`, the files under
`profiles/settings`, and the contents of `profiles/characterdata`. The native
module clearly establishes the local persistence format and packet call. The
server remains authoritative for the exact quick-loot category semantics and
destination rules, so private-server changes may differ from official Tibia 15
or from another OTClient fork.
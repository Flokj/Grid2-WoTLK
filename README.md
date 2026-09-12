# Grid2 2.9.31 (_WoTLK_)

Grid2 is a party/raid unit frame addon.

Grid2 is fully customizable. New zones (indicators) can be defined in unit frames to display information (statuses). The indicators can be customized and placed anywhere. Grid2 supports several types of indicators: icon, icons, square, text, bar, multibar. You can configure what statuses are displayed on each indicator.

Grid2 includes a huge amount of available statuses, but not all enabled by default, look through the configuration and familiarize yourself with the available options and statuses.

Grid2 is fast: consumes between 4 and 10 times less CPU cycles than other similar addons.

To open the configuration UI type "/grid2" or left-click the minimap Icon.


## Grid2 components

* Grid2
* Grid2 Options
* ~~Grid2 LDB~~ (_removed as of r732_)
* Grid2 AOE Heals
* Grid2 RaidDebuffs (standalone, optional)

**Raid Debuffs** and **Raid Debuffs Options** are also built into **Grid2** and **Grid2 Options** respectively.

## New as of 2.9.31 (backported from Grid2-2.9.31-bcc)

### Options UI

* Indicator statuses: current-status list with unassign, move up/down and jump-to-status buttons; available statuses grouped by category
* Aura lists: spell-name search with suggestions, Track by SpellId, spell links in the list
* Status pages: full Colors/Highlight/Duration/Value/Text sections, Load filters, Test layout mode
* Options window: fixed default size with enforced minimum size

### New Indicators

* glowborder
* icons (with delayed updates for large raids)
* multibar
* portrait
* shape
* tooltip
* privateauras (placeholder on 3.3.5a)

### New Statuses

* combat
* combat-mine
* shields
* shields-overflow
* healsaoe, heal-absorbs, phased, summon, unit-index (placeholders/no-ops on 3.3.5a where the client lacks the API)

### Raid Debuffs

* Lich King (WotLK) module active; zone matching by name for 3.3.5a

## Fork features kept

* AOE Heals with map data and chain/highlighter statuses
* FreeLayout editor, extra themes, UnitPopup menus

## How to install

1. [Download the package](https://github.com/bkader/Grid2-WoTLK/archive/refs/heads/main.zip).
2. Unpack the Zip file.
3. Open the folder `Grid2-WoTLK-main`.
4. Copy (or drag and drop) the folders into you `Wow-Directory\Interface\AddOns`.
5. Restart WoW
6. Enjoy!

## Show Love & Support

Though it's not required and I have never asked for it but people keep asking for it, if you want to show love and support, your PayPal/Paysera donations are most welcome to **bkader[at]mail.com**.

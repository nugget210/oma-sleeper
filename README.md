# Omarchy Sleeper Matchup

A theme-aware Omarchy bar widget for live Sleeper fantasy football matchups.

The compact bar score opens a two-column matchup panel containing teams, starters, bench players, positions, NFL teams, and live fantasy points. It uses Omarchy's active font and theme tokens, with optional performance and monochrome colour modes.

## Requirements

- Omarchy 4.x with `omarchy-shell`
- `curl`
- `jq`
- A public Sleeper fantasy football league

Sleeper's read-only league API does not require authentication.

## Install

```bash
gh repo clone OWNER/oma-sleeper
cd oma-sleeper
./install.sh
```

The installer copies the plugin to `~/.config/omarchy/plugins/oma-sleeper` and places it immediately before the clock.

## Set up

1. Click `NFL SETUP` in the bar.
2. Open the cog if the settings view is not already visible.
3. Paste a Sleeper league URL or numeric league ID and select **Update**.
4. Select your fantasy team.
5. Optionally enter a short bar label and choose a colour mode.
6. Select **Save**.

No league, roster, team name, or bar label is included in the plugin defaults.

## Controls

- Left click: open or close the matchup panel
- Middle click: refresh matchup data
- Cog: settings
- External-link icon: open the matchup on Sleeper
- Refresh icon: refresh immediately

## Live-game preview

The settings pane includes **Leading**, **Trailing**, and **Off** preview controls. Preview mode applies deterministic in-progress scores to the currently loaded teams and players so the bar, score rails, colours, player rows, and directional indicators can be reviewed before the season starts.

Preview scores are local and temporary. They are never sent to Sleeper, do not replace fetched matchup data, and reset when the shell restarts.

During games, each active player shows the NFL quarter, clock, and a progress rail. With at least two prior league weeks available, the current score is compared with that player's rolling fantasy average at the same game progress: green/`▲` is above pace, orange/`●` is near pace, and urgent red/`▼` is below pace. Pregame and insufficient-history states remain neutral.

The compact bar derives matchup state from the NFL games attached to both starting lineups. It shows `UPCOMING` while starter games are scheduled, `● LIVE` when any starter is playing, and `FINAL` after the relevant slate has completed. If schedule data is unavailable, no status suffix is shown rather than guessing.

Player metadata is cached once per day in `~/.cache/oma-sleeper` because Sleeper recommends fetching the full NFL player map sparingly. League, user, and roster metadata is cached for one hour. Matchup scores use adaptive refresh intervals:

- 60 seconds while an NFL game is live
- 5 minutes when a game starts within three hours
- 15 minutes while the slate is idle or completed
- Immediately when the panel opens, the refresh button is selected, or the computer wakes

Sleeper remains the source of all fantasy data. The public ESPN NFL scoreboard supplies only the live/upcoming/idle game-clock signal used to choose a refresh interval.

## Colour modes

- **Theme-aware** uses the current Omarchy accent, foreground, muted, popup, and urgent colours.
- **Performance** adds green leader emphasis while retaining Omarchy's urgent colour for the trailing team.
- **Minimal** keeps the scoreboard monochrome.

Pregame and tied matchups remain neutral. Colour is reinforced by score rails and directional symbols rather than being the only indicator.

## Uninstall

Remove `oma-sleeper` from `~/.config/omarchy/shell.json`, then remove:

```text
~/.config/omarchy/plugins/oma-sleeper
```

Restart the shell with `omarchy restart shell`.

## Data source

League, roster, matchup, and player information comes from the public [Sleeper API](https://docs.sleeper.com/).

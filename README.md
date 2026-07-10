# LEDuel Online

A Godot 4 prototype for a local 1v1 cyber-sport timing duel built around a spinning LED ring.

## Run

Open this folder in Godot 4.x and run the project. The main scene opens to the main menu.

## Controls

- Player 1 catch: `F`
- Player 2 catch: `J`
- Restart round: `R`
- Return to menu: `Esc`
- Controls can be rebound from the full-screen Options page.

## Main Menu

- `PLAY` starts the duel.
- `SELECT GAME MODE` opens the game mode selection screen.
- `OPTIONS` opens a full-screen settings page with audio, window, and control rebinding.
- `QUIT` exits the game.
- Audio sliders control Master, Music, and SFX buses.
- Window mode can be set to Windowed, Borderless, or Fullscreen.

## Prototype Rules

- Catch the spinning light inside your colored timing zone.
- `PERFECT` and `GOOD` catches build charge.
- Misses cost a little charge.
- Fill the charge bar to automatically attack the opponent.
- Full-charge attacks fire a huge particle blast.
- Full-charge attacks reverse the spinning light direction.
- First player to drop the other to zero health wins the round.

## Current Juice

- Procedural techno backing loop.
- Procedural sound effects for catches, misses, attacks, overdrive, sudden death, and wins.
- Particle bursts for `GOOD` and `PERFECT` catches.
- Numeric health and charge values on the player meters.

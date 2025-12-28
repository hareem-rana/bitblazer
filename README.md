# COAL 8086 Assembly Car Game (DOS)

## Project Overview
- A DOS-era car game written in NASM 8086 assembly for DOSBox.
- Runs in graphics mode `13h` (320×200) and renders road, lanes, a red player car, and blue obstacle cars.
- Implements multiple screens: start screen, instructions, player info input, gameplay, pause/confirmation, game-over summary.
- Features fuel management, coin collection with on-screen HUD, collision detection with spark animation, and clean exit flows.
- Background music plays via an interrupt-driven PC speaker routine that programs the PIT.

## Gameplay Instructions
- Controls:
  - `Arrow Keys`: Move the red car (left/right lane changes; up/down car movement).
  - `P`: Pause the game.
  - `ESC`: Show confirmation to exit; `Y` confirms, `N` cancels and resumes.
- Objectives:
  - Avoid blue obstacle cars; collisions end the game and show an end screen.
  - Collect coins to increase score.
  - Pick up fuel tanks to keep the fuel bar from reaching zero.
- Screens:
  - Start Screen: Static road with a randomly placed blue car. Press any key to continue.
  - Instruction Screen: Shows controls and gameplay tips.
  - Player Info: Enter name and roll number before starting.
  - Gameplay: Continuous scroll with obstacles, coins, and fuel.
  - Pause/Confirmation: In-game `ESC` asks to quit; other screens use a similar confirmation style.
  - End Screen: Displays player name, roll number, coins, fuel, and reason for game end.

## How to Run
- Requirements: `DOSBox`
- Once the project directory is mounted in DOSBox, run:
  ```bash
  GAME
  ```
## Technical Notes
- Music: Uses a hardware timer interrupt (INT 08h) to update tones; PC speaker is set via PIT ports. The ISR is minimal and chains to the original handler.
- Input: Keyboard input via BIOS INT 16h; confirmation windows are software-drawn overlays that preserve the underlying screen and restore cleanly when canceled.
- Stability: Stack discipline and interrupt unhooking are preserved on exit so DOSBox returns to the command line without artifacts.

## Game Demo
- Gameplay video: [Gameplay Demo](https://youtu.be/KYOlkGHGtVI)

## 📚 Credits & Acknowledgements

### Visual Assets 
- This project uses licensed graphical assets obtained from GameDev Market.
- The original asset files and intermediate .inc files are not included in this repository in accordance with the asset license terms.
- Graphics data is compiled directly into the executable as part of the final media product and cannot be extracted for reuse.
- Asset owner: [original creator](https://www.gamedevmarket.net/member/chiffa?orderby=recent&pricing=free&genre=&category=)
- Used under: [license](https://www.gamedevmarket.net/terms-conditions#pro-licence)

### Music & Audio
- Background music was generated using **Suno AI**.
- Used under Suno’s free-tier terms for non-commercial use.
- The generated audio was converted and adapted for playback via the **PC speaker**.
- Music is used for **demonstration and educational purposes only**.

## License
- This repository is licensed under the MIT License for the source code only. 
- Third-party assets included in the executable remain subject to their original licenses.



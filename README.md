# MT5 Utilities

This repository contains various MetaTrader 5 scripts and expert advisors.

## Weekend Close EA

`WeekendCloseEA.mq5` automatically closes all open positions around the end of the trading week.

### Features
- Runs on any chart and checks every minute (configurable).
- At 5:00 AM Brisbane time on Saturday, it closes all positions. When the United States is not on daylight saving time, the cutoff shifts to 6:00 AM.
- Each closed trade is appended to `WeekendCloseLog.csv` in the terminal's `Files` directory.

### Usage
1. Copy `WeekendCloseEA.mq5` to your **MQL5/Experts** folder and compile it in MetaEditor.
2. Attach the expert to any chart in MetaTrader 5.
3. Keep the terminal running so the EA can check the time and close positions automatically.


## Position Size EA

`PositionSizeEA.mq5` opens a simple browser page showing a Pepperstone-specific position size calculator. It no longer supports OANDA trades.

### Usage
1. Copy `PositionSizeEA.mq5` to your **MQL5/Experts** folder and compile it.
2. Attach the EA to any chart. It will open a browser window with the calculator.

## OANDA Position Size Script

`oanda_position_size.py` replicates the old OANDA calculation in Python. Run it from the command line and provide the necessary parameters described in the `--help` message.

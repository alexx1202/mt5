# mt5 Scripts

This repository contains simple example scripts for MetaTrader 5.

## Scripts

- **CryptoRiskCalculator.mq5** – calculates risk for crypto trades and saves the result to a text file.
- **scripts/FXScanner.mq5** – scans FX symbols across timeframes and exports several CSV files.
- **scripts/PositionSizeFX.mq5** – calculates forex position size with adjustable risk settings. It can fetch your OANDA balance using an API token or fall back to your Pepperstone balance.
  - Use `BalanceMode` to choose which balance is used: `BALANCE_PEPPERSTONE` or `BALANCE_OANDA`.
  - When using the OANDA mode, set `OandaAccountID` and `OandaApiToken` so the script can retrieve your balance. If the request fails you can provide `OandaBalance` manually.
  - For Pepperstone you can also supply `PepperstoneBalance` manually.
- **AUD_EMA_TraderEA.mq5** – simple EMA-based expert advisor example.

Copy the `.mq5` files to your `MQL5\Scripts` folder to use them in MT5.

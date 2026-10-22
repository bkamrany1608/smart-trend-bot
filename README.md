# Smart Trend Bot (Android, no VPS)

Trend-pullback crypto auto-trader that runs on the phone.
Virtual account (default) -> Binance Futures testnet -> live.

## Build the APK on GitHub (no local tools needed)
1. Create a new GitHub repository and upload everything in this folder (keep the `.github` folder).
2. Open the **Actions** tab -> `build-apk` -> **Run workflow** (it also runs on every push).
3. The workflow:
   - downloads real historical USDT-M futures klines from the Binance public archive,
   - runs the walk-forward backtest/optimization with the SAME engine as the app,
   - writes `assets/params.json` (only if the hold-out check passes) and `reports/optimization.md`,
   - builds `app-release.apk`.
4. Download the APK from **Releases** (latest `build-N`) or from the run's *Artifacts*.
5. If the build fails, open the failed step log and send it to Claude to fix.

## Phone setup
Allow notifications + "unrestricted battery" when asked (needed for the foreground service).
Settings tab: Telegram token/chat id, risk level, scan interval. Turn the switch in the top bar on.
If Binance is unreachable from your network the app falls back to Bybit; otherwise use a VPN on the phone.

## Layout
- `lib/core` pure-Dart strategy engine (shared by app, backtest, optimizer)
- `lib/data` free public market data (Binance mirrors, Bybit fallback)
- `lib/services` Telegram, Excel journal, Binance Futures broker, signal text parser
- `lib/ui` pages: trades, chart, manual signal, reports, training, settings
- `tool/optimize.dart`, `tools/*.py` CI helpers

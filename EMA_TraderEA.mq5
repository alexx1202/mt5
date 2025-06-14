//+------------------------------------------------------------------+
//|   AUD EMA Trader EA (Improved for beginners)                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Pepperstone EA"
#property version   "7.0"
#property strict

#include <Trade/Trade.mqh>
#include <Indicators/Trend.mqh>

//--- trading objects
CTrade  trade;
CiMA    maFast;

//--- EMA settings
input int    FastEMA_Period      = 9;    // period for the fast EMA
input double TouchPercent        = 0.005; // distance from EMA in percent

//--- risk settings
input double MinRiskAUD          = 10.0; // how much money to risk per trade
                                       // EA enforces risk within ±1 AUD of
                                       // this value
input int    StopLoss_Pips       = 15;   // fixed stop loss in pips
input int    TakeProfit_Pips     = 30;   // fixed take profit in pips (unused when RewardRiskRatio > 0)
input double RewardRiskRatio     = 2.0;  // reward:risk ratio for trades

//--- advanced options
input bool   UseATRStopLoss      = false;// use ATR-based stop instead
input double ATRMultiplier       = 1.5;  // ATR multiplier when ATR stop is on
input uint   ExpertMagic         = 20240405; // unique ID for this EA

//--- backtest settings
input bool   UseBacktestLots     = false;// use fixed lot in backtest
input double BacktestLotSize     = 0.01; // fixed lot size for backtest
input double BacktestRewardRisk  = 2.0;  // reward:risk ratio in backtest

//--- hotkey
input bool   EnableHotkey        = true; // press J to toggle the EA

//--- session settings
input int    NYCloseBrisbane     = 7;    // New York close / Asian open (Brisbane time)

//--- global variables
bool   eaEnabled      = true;     // is the EA currently active?
string currentSymbol;             // symbol we trade on
string lastStatus     = "";       // message shown on chart

//+------------------------------------------------------------------+
//| Check if current time is in the restricted window                |
//+------------------------------------------------------------------+
bool TradingTimeRestricted()
  {
   datetime utc = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   int hourBNE = dt.hour + 10;  // convert UTC to Brisbane (UTC+10)
   if(hourBNE >= 24)
      hourBNE -= 24;

   int start = (NYCloseBrisbane - 3 + 24) % 24;  // 3h before NY close
   int end   = (NYCloseBrisbane + 3) % 24;       // 3h after

   if(start < end)
      return(hourBNE >= start && hourBNE < end);
   else
      return(hourBNE >= start || hourBNE < end);
  }

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   currentSymbol = _Symbol;

   // validate inputs so they are sensible
   if(FastEMA_Period <= 0 || StopLoss_Pips <= 0 || RewardRiskRatio <= 0 ||
      TouchPercent <= 0)
    {
      Print("Error: input values must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // create EMA indicator
   if(!maFast.Create(currentSymbol, PERIOD_CURRENT, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE))
     {
      Print("Failed to create EMA. Error ", GetLastError());
      return(INIT_FAILED);
     }

   maFast.Refresh();
   trade.SetExpertMagicNumber(ExpertMagic);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   // create trade log file
   int handle = FileOpen("FX_EMA_TradeLog.csv", FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle != INVALID_HANDLE)
     {
      FileWrite(handle, "Date", "Time", "Symbol", "Type", "Lots", "Price", "SL", "TP", "ATRUsed", "Result");
      FileClose(handle);
     }
   else
      Print("Failed to open trade log file.");

   Print("=== EA INITIALIZED ===");
   Comment("EA ENABLED");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Calculate ATR stop loss in points                                |
//+------------------------------------------------------------------+
int CalculateATRPoints()
  {
   double atr[];
   if(CopyBuffer(iATR(currentSymbol, PERIOD_CURRENT, 14), 0, 0, 1, atr) > 0)
     {
      return(int)MathRound((atr[0] * ATRMultiplier) / _Point);
     }
   Print("ATR fetch failed—using fixed stop loss.");
   return(StopLoss_Pips * 10); // convert pips to points
  }

//+------------------------------------------------------------------+
//| Calculate lot size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize()
  {
   if(UseBacktestLots)
      return(BacktestLotSize);

   double tickValue = SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0)
     {
      Print("Invalid tick data.");
      return(0.0);
     }

   double pipValue = tickValue / (tickSize / _Point);
   double slPips   = UseATRStopLoss ? (double)CalculateATRPoints() / 10.0 : StopLoss_Pips;
   double riskPerLot = slPips * pipValue;
   double rawLots = MinRiskAUD / riskPerLot;

   double minLot  = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_STEP);

   double lots = MathFloor(rawLots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   // calculate final risk after rounding
   double finalRisk = lots * riskPerLot;

   // calculate allowed risk range of ±1 AUD around the requested amount
   double lowerRisk = MinRiskAUD - 1.0;
   double upperRisk = MinRiskAUD + 1.0;

   // adjust lots if risk is outside the allowed range
   if(finalRisk > upperRisk)
     lots = MathFloor(upperRisk / riskPerLot / lotStep) * lotStep;
   else if(finalRisk < lowerRisk)
     lots = MathCeil(lowerRisk / riskPerLot / lotStep) * lotStep;

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   finalRisk = lots * riskPerLot;
   if(finalRisk < lowerRisk || finalRisk > upperRisk)
     {
      Print("Risk ", finalRisk, " AUD outside limits; trade skipped.");
      return(0.0);
     }

   return(lots);
  }

//+------------------------------------------------------------------+
//| Log trade result                                                 |
//+------------------------------------------------------------------+
void LogTrade(string type, double lots, double price, double sl, double tp, string result)
  {
   string dateStr = TimeToString(TimeCurrent(), TIME_DATE);
   string timeStr = TimeToString(TimeCurrent(), TIME_SECONDS);

   int handle = FileOpen("FX_EMA_TradeLog.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle != INVALID_HANDLE)
     {
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, dateStr, timeStr, currentSymbol, type, lots, price, sl, tp, UseATRStopLoss, result);
      FileClose(handle);
     }
   else
      Print("Failed to log trade.");
  }

//+------------------------------------------------------------------+
//| Helper to open buy trade                                         |
//+------------------------------------------------------------------+
void CheckBuy(double ema)
  {
   double bid = SymbolInfoDouble(currentSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
   double threshold = ema * (TouchPercent / 100.0);

   // check the ask price because buys execute at ask
   if(ask < ema - threshold || ask > ema + threshold)
      return; // price not close enough
   if(ask <= ema)
      return; // price must approach from above

   double prevClose = iClose(currentSymbol, PERIOD_CURRENT, 1);
   double prevEMA   = maFast.Main(1);
   if(prevClose <= prevEMA)
      return; // previous candle not above EMA

   double slPoints = UseATRStopLoss ? CalculateATRPoints() : StopLoss_Pips * 10;
   double rr       = UseBacktestLots ? BacktestRewardRisk : RewardRiskRatio;
   double tpPoints = slPoints * rr;

   double sl = ask - slPoints * _Point;
   double tp = ask + tpPoints * _Point;
   double lots = CalculateLotSize();
   if(lots <= 0) return;

   if(trade.Buy(lots, currentSymbol, ask, sl, tp, "BUY|EMA"))
     {
      lastStatus = "BUY opened";
      LogTrade("BUY", lots, ask, sl, tp, "SUCCESS");
     }
   else
     {
      int err = GetLastError();
      Print("Buy failed: ", err);
      lastStatus = "BUY failed";
      LogTrade("BUY", lots, ask, sl, tp, "ERROR " + (string)err);
     }
  }

//+------------------------------------------------------------------+
//| Helper to open sell trade                                        |
//+------------------------------------------------------------------+
void CheckSell(double ema)
  {
   double bid = SymbolInfoDouble(currentSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
   double threshold = ema * (TouchPercent / 100.0);

   // check the bid price because sells execute at bid
   if(bid < ema - threshold || bid > ema + threshold)
      return;
   if(bid >= ema)
      return; // price must approach from below

   double prevClose = iClose(currentSymbol, PERIOD_CURRENT, 1);
   double prevEMA   = maFast.Main(1);
   if(prevClose >= prevEMA)
      return;

   double slPoints = UseATRStopLoss ? CalculateATRPoints() : StopLoss_Pips * 10;
   double rr       = UseBacktestLots ? BacktestRewardRisk : RewardRiskRatio;
   double tpPoints = slPoints * rr;

   double sl = bid + slPoints * _Point;
   double tp = bid - tpPoints * _Point;
   double lots = CalculateLotSize();
   if(lots <= 0) return;

   if(trade.Sell(lots, currentSymbol, bid, sl, tp, "SELL|EMA"))
     {
      lastStatus = "SELL opened";
      LogTrade("SELL", lots, bid, sl, tp, "SUCCESS");
     }
   else
     {
      int err = GetLastError();
      Print("Sell failed: ", err);
      lastStatus = "SELL failed";
      LogTrade("SELL", lots, bid, sl, tp, "ERROR " + (string)err);
     }
  }

//+------------------------------------------------------------------+
//| Execute trade logic                                              |
//+------------------------------------------------------------------+
void ExecuteTrade()
  {
  if(!eaEnabled)
      return;
   if(TradingTimeRestricted())
     {
      lastStatus = "session pause";
      return;
     }
  if(PositionSelect(currentSymbol))
      return; // already have a position on this symbol
   if(Bars(currentSymbol, PERIOD_CURRENT) < FastEMA_Period)
      return; // not enough bars to calculate EMA

   maFast.Refresh();
   double ema = maFast.Main(0);
   if(ema <= 0 || ema == DBL_MAX)
      return;

   CheckBuy(ema);
   CheckSell(ema);
  }

//+------------------------------------------------------------------+
//| Tick handler                                                     |
//+------------------------------------------------------------------+
void OnTick()
  {
   ExecuteTrade();
   Comment((eaEnabled ? "EA ENABLED" : "EA DISABLED"), " | ", lastStatus);
  }

//+------------------------------------------------------------------+
//| Hotkey toggle                                                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(EnableHotkey && id == CHARTEVENT_KEYDOWN && lparam == 74) // J key
     {
      eaEnabled = !eaEnabled;
      lastStatus = eaEnabled ? "enabled" : "disabled";
      Print("EA ", (eaEnabled ? "ENABLED" : "DISABLED"));
     }
  }

//+------------------------------------------------------------------+

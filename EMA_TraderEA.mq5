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

//--- live trading settings
input int    EmaPeriod       = 9;      // fast EMA period
input double TouchPct        = 0.005;  // allowed distance from EMA
input double RiskAUD         = 10.0;   // money to risk per trade
                                        // EA keeps risk within ±1 AUD
input int    StopPips        = 15;     // fixed stop loss in pips
input int    TakePips        = 30;     // fixed take profit (if RRTarget==0)
input double RRTarget        = 2.0;    // reward:risk ratio
input bool   UseAtrSL        = false;  // use ATR stop loss
input double AtrMult         = 1.5;    // ATR multiplier
input uint   MagicID         = 20240405; // unique ID for this EA

//--- backtest only settings
input bool   TestUseLot      = false;  // use fixed lot when backtesting
input double TestLotSize     = 0.01;   // fixed lot size in backtest
input double TestRR          = 2.0;    // reward:risk ratio in backtest

//--- other options
input bool   UseHotkey       = true;   // press J to toggle the EA
input int    NyCloseBNE      = 7;      // NY close / Asian open (Brisbane)

//--- global variables
bool   eaEnabled      = true;     // is the EA currently active?
string currentSymbol;             // symbol we trade on
string lastStatus     = "";       // message shown on chart
bool   inRestricted   = false;    // are we in the restricted time?

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

   int start = (NyCloseBNE - 3 + 24) % 24;  // 3h before NY close
   int end   = (NyCloseBNE + 3) % 24;       // 3h after

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
   if(EmaPeriod <= 0 || StopPips <= 0 || RRTarget <= 0 ||
      TouchPct <= 0)
    {
      Print("Error: input values must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // create EMA indicator
   if(!maFast.Create(currentSymbol, PERIOD_CURRENT, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE))
     {
      Print("Failed to create EMA. Error ", GetLastError());
      return(INIT_FAILED);
     }

   maFast.Refresh();
   trade.SetExpertMagicNumber(MagicID);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   // create trade log file
   int handle = FileOpen("FX_EMA_TradeLog.csv", FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle != INVALID_HANDLE)
     {
      FileWrite(handle,
               "DateServer",
               "TimeServer",
               "DateBNE",
               "TimeBNE",
               "Symbol",
               "Type",
               "Lots",
               "Price",
               "SL",
               "TP",
               "ATRUsed",
               "Result");
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
      return(int)MathRound((atr[0] * AtrMult) / _Point);
     }
   Print("ATR fetch failed—using fixed stop loss.");
   return(StopPips * 10); // convert pips to points
  }

//+------------------------------------------------------------------+
//| Calculate lot size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize()
  {
   if(TestUseLot)
      return(TestLotSize);

   double tickValue = SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_TICK_SIZE);
   int    digits    = (int)SymbolInfoInteger(currentSymbol, SYMBOL_DIGITS);
   if(tickValue <= 0 || tickSize <= 0)
     {
      Print("Invalid tick data.");
      return(0.0);
     }

   double pipSize  = MathPow(10.0, -digits + 1);
   double pipValue = tickValue * pipSize / tickSize;
   double slPips   = UseAtrSL ? (double)CalculateATRPoints() / 10.0 : StopPips;
   double riskPerLot = slPips * pipValue;
   double rawLots = RiskAUD / riskPerLot;

   double minLot  = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_STEP);

   double lots = MathFloor(rawLots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   // calculate final risk after rounding
   double finalRisk = lots * riskPerLot;

   // calculate allowed risk range of ±1 AUD around the requested amount
   double lowerRisk = RiskAUD - 1.0;
   double upperRisk = RiskAUD + 1.0;

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
   string dateStrServer = TimeToString(TimeCurrent(), TIME_DATE);
   string timeStrServer = TimeToString(TimeCurrent(), TIME_SECONDS);

   datetime utc      = TimeGMT();
   datetime bneTime  = utc + 10 * 3600; // UTC+10 for Brisbane
   string dateStrBNE = TimeToString(bneTime, TIME_DATE);
   string timeStrBNE = TimeToString(bneTime, TIME_SECONDS);

   int handle = FileOpen("FX_EMA_TradeLog.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle != INVALID_HANDLE)
     {
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle,
                dateStrServer,
                timeStrServer,
                dateStrBNE,
                timeStrBNE,
                currentSymbol,
                type,
                lots,
                price,
                sl,
                tp,
                UseAtrSL,
                result);
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
   double threshold = ema * (TouchPct / 100.0);

   // ensure price is close enough to the EMA
   if(ask < ema - threshold || ask > ema + threshold)
      return;

   double prevClose = iClose(currentSymbol, PERIOD_CURRENT, 1);
   double prevEMA   = maFast.Main(1);
   if(prevClose <= prevEMA)
      return; // previous candle not above EMA

   // price must have approached the EMA from above during this bar
   double curLow = iLow(currentSymbol, PERIOD_CURRENT, 0);
   if(curLow > ema)
      return;

   double slPoints = UseAtrSL ? CalculateATRPoints() : StopPips * 10;
   double rr       = TestUseLot ? TestRR : RRTarget;
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
   double threshold = ema * (TouchPct / 100.0);

   // ensure price is close enough to the EMA
   if(bid < ema - threshold || bid > ema + threshold)
      return;

   double prevClose = iClose(currentSymbol, PERIOD_CURRENT, 1);
   double prevEMA   = maFast.Main(1);
   if(prevClose >= prevEMA)
      return; // previous candle not below EMA

   // price must have approached the EMA from below during this bar
   double curHigh = iHigh(currentSymbol, PERIOD_CURRENT, 0);
   if(curHigh < ema)
      return;

   double slPoints = UseAtrSL ? CalculateATRPoints() : StopPips * 10;
   double rr       = TestUseLot ? TestRR : RRTarget;
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
   bool nowRestricted = TradingTimeRestricted();
   if(nowRestricted != inRestricted)
     {
      inRestricted = nowRestricted;
      if(nowRestricted)
         Print("EA has entered the restricted trading time block. Trading paused.");
      else
         Print("Restricted trading time finished. Trading can resume.");
     }
   if(nowRestricted)
     {
      lastStatus = "session pause";
      return;
     }
  if(PositionSelect(currentSymbol))
      return; // already have a position on this symbol
   if(Bars(currentSymbol, PERIOD_CURRENT) < EmaPeriod)
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
   if(UseHotkey && id == CHARTEVENT_KEYDOWN && lparam == 74) // J key
     {
      eaEnabled = !eaEnabled;
      lastStatus = eaEnabled ? "enabled" : "disabled";
      Print("EA ", (eaEnabled ? "ENABLED" : "DISABLED"));
     }
  }

//+------------------------------------------------------------------+

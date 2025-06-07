//+------------------------------------------------------------------+
//|                      FXBacktestEA                               |
//|  A simple example expert advisor showing time filtering logic.  |
//|  It avoids trading during certain Brisbane hours and weekends.  |
//|  This file demonstrates improvements suggested in a code review.|
//+------------------------------------------------------------------+
#property strict
#property version "3.1"
#include <Trade/Trade.mqh>

CTrade trade;
int logFileHandle = INVALID_HANDLE;

//--- user parameters
input bool   EnableLogging     = true;   // Turn file logging on/off
input double Risk_Percent      = 1.0;    // Risk per trade (%)
input int    ATR_Period        = 14;     // ATR period
input double ATR_SL_Multiplier = 1.0;    // ATR Stop Loss multiplier
input double R_Multiple        = 2.0;    // Reward to Risk ratio
input double Slippage          = 5;      // Max slippage in points
input int    Bounce_EMA_Period = 9;      // EMA period for bounce detection
input int    Brisbane_GMT_Offset = 10;   // Brisbane offset from GMT (hours)
input uint   MagicNumber       = 123456; // Unique identifier for EA trades

//--- indicator handles
int atrHandle;
int ema9Handle;
int ema20Handle;
int bounceHandle;

//+------------------------------------------------------------------+
//|  Simple logging function                                         |
//+------------------------------------------------------------------+
void WriteLog(const string message)
{
   if(!EnableLogging)
      return;
   if(logFileHandle != INVALID_HANDLE)
   {
      FileWrite(logFileHandle,
                TimeToString(ServerToBrisbane(TimeCurrent()), TIME_DATE|TIME_SECONDS),
                " - ", message);
      FileFlush(logFileHandle);
   }
}

//+------------------------------------------------------------------+
//|  Time conversion helpers                                         |
//+------------------------------------------------------------------+
int GetServerOffsetSeconds()
{
   return(int)(TimeCurrent() - TimeGMT());
}

//--- convert a Brisbane time to server time
datetime BrisbaneToServer(datetime brTime)
{
   int brOffset  = Brisbane_GMT_Offset * 3600;
   int srvOffset = GetServerOffsetSeconds();
   return(brTime - brOffset + srvOffset);
}

//--- convert server time to Brisbane time
datetime ServerToBrisbane(datetime srvTime)
{
   int brOffset  = Brisbane_GMT_Offset * 3600;
   int srvOffset = GetServerOffsetSeconds();
   return(srvTime + brOffset - srvOffset);
}

//+------------------------------------------------------------------+
//|  Is current time forbidden for trading?                          |
//+------------------------------------------------------------------+
bool IsForbiddenTime()
{
   datetime now_srv = TimeCurrent();
   datetime now_br  = ServerToBrisbane(now_srv);
   MqlDateTime dt;
   TimeToStruct(now_br, dt);

   // daily block between 05:00 and 09:00 Brisbane
   if(dt.hour >= 5 && dt.hour < 9)
      return true;

   // weekend block: Sat from 07:00, all Sun, Mon before 07:00
   if((dt.day_of_week == 6 && dt.hour >= 7) || dt.day_of_week == 0 || (dt.day_of_week == 1 && dt.hour < 7))
      return true;

   return false;
}

//+------------------------------------------------------------------+
//|  Helper to read ATR indicator                                    |
//+------------------------------------------------------------------+
double GetATR()
{
   double buf[];
   ArrayResize(buf, 1);
   if(CopyBuffer(atrHandle, 0, 1, 1, buf) != 1)
   {
      Print("Error copying ATR");
      return(-1);
   }
   return(buf[0]);
}

//--- is EMA9 above EMA20 on current and previous bars?
bool IsBullishSequence()
{
   double buf9[], buf20[];
   ArraySetAsSeries(buf9, true);
   ArraySetAsSeries(buf20, true);
   ArrayResize(buf9, 2);
   ArrayResize(buf20, 2);
   if(CopyBuffer(ema9Handle, 0, 0, 2, buf9) != 2 || CopyBuffer(ema20Handle, 0, 0, 2, buf20) != 2)
   {
      Print("Error copying EMAs");
      return false;
   }
   return(buf9[0] > buf20[0] && buf9[1] > buf20[1]);
}

//--- is EMA9 below EMA20 on current and previous bars?
bool IsBearishSequence()
{
   double buf9[], buf20[];
   ArraySetAsSeries(buf9, true);
   ArraySetAsSeries(buf20, true);
   ArrayResize(buf9, 2);
   ArrayResize(buf20, 2);
   if(CopyBuffer(ema9Handle, 0, 0, 2, buf9) != 2 || CopyBuffer(ema20Handle, 0, 0, 2, buf20) != 2)
   {
      Print("Error copying EMAs");
      return false;
   }
   return(buf9[0] < buf20[0] && buf9[1] < buf20[1]);
}

//--- check the 10 previous candles for the largest body and return true
//    if it was bullish
bool LargestCandleWasBullish()
{
   MqlRates candles[10];
   if(CopyRates(_Symbol, _Period, 1, 10, candles) != 10)
   {
      Print("Error copying rates");
      return false;
   }
   double maxBody = 0;
   bool wasBull = false;
   for(int i = 0; i < 10; i++)
   {
      double body = MathAbs(candles[i].close - candles[i].open);
      if(body > maxBody)
      {
         maxBody = body;
         wasBull = (candles[i].close > candles[i].open);
      }
   }
   return wasBull;
}

//--- same as above but check if the largest candle was bearish
bool LargestCandleWasBearish()
{
   MqlRates candles[10];
   if(CopyRates(_Symbol, _Period, 1, 10, candles) != 10)
   {
      Print("Error copying rates");
      return false;
   }
   double maxBody = 0;
   bool wasBear = false;
   for(int i = 0; i < 10; i++)
   {
      double body = MathAbs(candles[i].close - candles[i].open);
      if(body > maxBody)
      {
         maxBody = body;
         wasBear = (candles[i].close < candles[i].open);
      }
   }
   return wasBear;
}

//+------------------------------------------------------------------+
//|  Calculate lot size based on risk                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPips)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (Risk_Percent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize == 0 || tickValue == 0)
   {
      Print("Invalid tick size/value");
      return 0.0;
   }

   double pipVal   = tickValue / (tickSize / _Point);
   double rawLots  = riskMoney / (stopLossPips * pipVal);

   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   // Normalize volume to broker requirements
   double normalized = NormalizeDouble(rawLots, (int)MathLog10(1.0/lotStep));
   normalized = MathMax(minLot, MathMin(normalized, maxLot));
   return(normalized);
}

//+------------------------------------------------------------------+
//|  Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(EnableLogging)
   {
      logFileHandle = FileOpen("EA_Forbidden_Log.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(logFileHandle == INVALID_HANDLE)
         Print("Failed to open log file");
      else
         WriteLog("=== Log Start ===");
   }

   //--- set up trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints((int)Slippage);

   //--- create indicators
   atrHandle    = iATR(_Symbol, _Period, ATR_Period);
   ema9Handle   = iMA(_Symbol, _Period, 9, 0, MODE_EMA, PRICE_CLOSE);
   ema20Handle  = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE);
   bounceHandle = iMA(_Symbol, _Period, Bounce_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(atrHandle == INVALID_HANDLE || ema9Handle == INVALID_HANDLE ||
      ema20Handle == INVALID_HANDLE || bounceHandle == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }

   Print("EA Initialized");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|  Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   // run logic only on a new completed bar
   static datetime lastBar = 0;
   MqlRates bars[2];
   if(CopyRates(_Symbol, _Period, 0, 2, bars) != 2)
      return;
   if(bars[1].time == lastBar)
      return;
   lastBar = bars[1].time;

   double atr = GetATR();
   if(atr <= 0.0)
      return;

   double slP = atr * ATR_SL_Multiplier; // stop loss in price
   double tpP = slP * R_Multiple;        // take profit distance

   //--- last closed candle
   MqlRates bar = bars[1];

   //--- value of bounce EMA at previous bar
   double buf[];
   ArrayResize(buf,1);
   if(CopyBuffer(bounceHandle, 0, 1, 1, buf) != 1)
      Print("Error copying bounce EMA");
   double bounceVal = buf[0];

   //--- signal generation
   bool buySignal  = (bar.close < bar.open)
                     && IsBullishSequence()
                     && LargestCandleWasBullish()
                     && (bar.low <= bounceVal);
   bool sellSignal = (bar.close > bar.open)
                     && IsBearishSequence()
                     && LargestCandleWasBearish()
                     && (bar.high >= bounceVal);

   //--- check forbidden period
   if(IsForbiddenTime())
   {
      if(buySignal)
         WriteLog("Prevented BUY during forbidden time");
      if(sellSignal)
         WriteLog("Prevented SELL during forbidden time");

      // close any open positions for this symbol
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            WriteLog(StringFormat("Liquidating position #%I64u during forbidden time", ticket));
            trade.PositionClose(ticket);
         }
      }
      return;
   }

   //--- only trade if no positions or pending orders exist
   if(PositionsTotal() != 0 || OrdersTotal() != 0)
      return;

   //--- execute trades
   if(buySignal)
   {
      WriteLog("Executing BUY trade");
      double price   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slPrice = price - slP;
      double tpPrice = price + tpP;
      double volume  = CalculateLotSize(slP/_Point);

      if(trade.Buy(volume, _Symbol, price, slPrice, tpPrice))
         WriteLog("BUY placed successfully");
      else
         WriteLog(StringFormat("BUY failed: %s", trade.ResultComment()));
   }
   else if(sellSignal)
   {
      WriteLog("Executing SELL trade");
      double price   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double slPrice = price + slP;
      double tpPrice = price - tpP;
      double volume  = CalculateLotSize(slP/_Point);

      if(trade.Sell(volume, _Symbol, price, slPrice, tpPrice))
         WriteLog("SELL placed successfully");
      else
         WriteLog(StringFormat("SELL failed: %s", trade.ResultComment()));
   }
}

//+------------------------------------------------------------------+
//|  Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   WriteLog("=== Log End ===");
   if(logFileHandle != INVALID_HANDLE)
      FileClose(logFileHandle);

   if(atrHandle    != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(ema9Handle   != INVALID_HANDLE) IndicatorRelease(ema9Handle);
   if(ema20Handle  != INVALID_HANDLE) IndicatorRelease(ema20Handle);
   if(bounceHandle != INVALID_HANDLE) IndicatorRelease(bounceHandle);

   Print("EA Deinitialized");
}
//+------------------------------------------------------------------+

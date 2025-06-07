//+------------------------------------------------------------------+
//|   Auto Trendline Trader + Position Sizer EA (Improved v4.0)     |
//+------------------------------------------------------------------+
#property copyright "2024"
#property version   "4.0"
#property strict

#include <Trade\Trade.mqh>
#include <Object.mqh>

CTrade trade;

// ENUMS
enum ENUM_RISK_MODE   { RISK_FIXED_PERCENT = 0, RISK_FIXED_AUD = 1 };
enum ENUM_TARGET_MODE { TARGET_FIXED_PERCENT = 0, TARGET_FIXED_AUD = 1 };

// INPUTS
input string          TrendlineName   = "EntryLine";         // Trendline object name
input ENUM_ORDER_TYPE TradeType       = ORDER_TYPE_BUY;       // BUY or SELL
input ENUM_RISK_MODE  RiskMode        = RISK_FIXED_PERCENT;   // Risk mode
input double          FixedRiskAUD    = 50.0;                 // Fixed risk amount
input double          RiskPercent     = 1.0;                  // Percent risk per trade
input double          StopLossPoints  = 30.0;                 // Stop loss in points
input bool            UseATRStop      = false;                // Use ATR-based stop loss
input int             ATRPeriod       = 14;                   // ATR period
input double          ATRMultiplier   = 1.5;                  // ATR multiplier
input ENUM_TARGET_MODE TargetMode     = TARGET_FIXED_PERCENT; // TP mode
input double          TargetFixedAUD  = 20.0;                 // Fixed AUD TP or percent

//+------------------------------------------------------------------+
int OnInit()
  {
   // basic input validation
   if(RiskPercent <= 0 || RiskPercent > 100)
     {
      Print("Error: RiskPercent must be between 0 and 100.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(StopLossPoints <= 0 && !UseATRStop)
     {
      Print("Error: StopLossPoints must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   Print("EA initialized. Waiting for trendline '" + TrendlineName + "'.");
   return(INIT_SUCCEEDED);
  }

// helper: calculate ATR stop loss points
int CalcATRPoints()
  {
   double atr[];
   if(CopyBuffer(iATR(_Symbol,_Period,ATRPeriod),0,0,1,atr)>0)
      return((int)MathRound(atr[0]*ATRMultiplier/_Point));
   Print("Warning: ATR value invalid. Using default StopLossPoints.");
   return((int)StopLossPoints);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   static bool  detected = false;
   static bool  warnedAuto = false;
   static double lastAsk = 0.0, lastBid = 0.0;

   double currAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Only one position at a time
   if(PositionSelect(_Symbol))
      return;

   // Check trendline presence
   if(ObjectFind(0, TrendlineName) < 0)
     {
      detected = false;
      return;
     }

   // Confirm detection once
   if(!detected)
     {
      detected = true;
      Print("Detected trendline '" + TrendlineName + "'. Monitoring for touches.");
      lastAsk = currAsk;
      lastBid = currBid;
      return;
     }

   // Retrieve endpoints safely
   ResetLastError();
   datetime t1 = (datetime)ObjectGetInteger(0, TrendlineName, OBJPROP_TIME, 0);
   if(_LastError!=0)
     {
      Print("Error reading trendline time 1: ", _LastError);
      return;
     }
   datetime t2 = (datetime)ObjectGetInteger(0, TrendlineName, OBJPROP_TIME, 1);
   if(_LastError!=0)
     {
      Print("Error reading trendline time 2: ", _LastError);
      return;
     }
   ResetLastError();
   double p1 = ObjectGetDouble(0, TrendlineName, OBJPROP_PRICE, 0);
   if(_LastError!=0)
     {
      Print("Error reading trendline price 1: ", _LastError);
      return;
     }
   double p2 = ObjectGetDouble(0, TrendlineName, OBJPROP_PRICE, 1);
   if(_LastError!=0)
     {
      Print("Error reading trendline price 2: ", _LastError);
      return;
     }

   // Calculate trendline price at current time
   datetime currTime = TimeCurrent();
   double priceOnLine = p1 + (p2 - p1) * (double)(currTime - t1) / (double)(t2 - t1);

   // Detect crossing with gap check using min/max
   bool doTrade=false;
   if(TradeType==ORDER_TYPE_BUY)
     {
      double minPrice=MathMin(lastAsk,currAsk);
      double maxPrice=MathMax(lastAsk,currAsk);
      if(priceOnLine>=minPrice && priceOnLine<=maxPrice)
         doTrade=true;
     }
   else
     {
      double minPrice=MathMin(lastBid,currBid);
      double maxPrice=MathMax(lastBid,currBid);
      if(priceOnLine>=minPrice && priceOnLine<=maxPrice)
         doTrade=true;
     }

   lastAsk = currAsk;
   lastBid = currBid;

   if(!doTrade)
      return;

   // Calculate SL, TP, and volume
   double entryPrice = (TradeType==ORDER_TYPE_BUY) ? currAsk : currBid;
   double slPoints = UseATRStop ? CalcATRPoints() : StopLossPoints;
   double stopPrice = (TradeType == ORDER_TYPE_BUY)
                       ? entryPrice - slPoints * _Point
                       : entryPrice + slPoints * _Point;

   double accountBal = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = (RiskMode == RISK_FIXED_PERCENT)
                    ? accountBal * RiskPercent / 100.0
                    : FixedRiskAUD;
   double tpAmt = (TargetMode == TARGET_FIXED_PERCENT)
                  ? accountBal * TargetFixedAUD / 100.0
                  : TargetFixedAUD;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double oneLotValue = tickValue * contractSize;

   double slValue  = slPoints * oneLotValue;
   double rawVolume = riskAmt / slValue;
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double volume = MathRound(rawVolume/stepVol) * stepVol;
   if(volume < minVol) volume = minVol;
   if(volume > maxVol) volume = maxVol;

   double tpPoints = tpAmt / oneLotValue;
   double takeProfit = (TradeType == ORDER_TYPE_BUY)
                       ? entryPrice + tpPoints * _Point
                       : entryPrice - tpPoints * _Point;

   PrintFormat("Entry=%.5f SL=%.5f TP=%.5f Vol=%.2f", entryPrice, stopPrice, takeProfit, volume);

   bool result;
   if(TradeType == ORDER_TYPE_BUY)
      result = trade.Buy(volume, _Symbol, entryPrice, stopPrice, takeProfit);
   else
      result = trade.Sell(volume, _Symbol, entryPrice, stopPrice, takeProfit);

   if(!result)
     {
      uint code = trade.ResultRetcode();
      string msg = trade.ResultRetcodeDescription();
      if(code == 10027 && !warnedAuto)
        {
         warnedAuto = true;
         Print("AutoTrading disabled: please enable for execution.");
         Comment("AutoTrading disabled! Enable to trade.");
        }
      else
         Print(__FILE__, " trade failed code=", code, " desc=", msg);
     }
   else
     {
      detected=false; // re-arm for next trade
     }
  }
//+------------------------------------------------------------------+

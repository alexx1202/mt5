//+------------------------------------------------------------------+
//| Backtester                                                      |
//| Places trades with limit orders at the next candle's open.       |
//| Buys after a bearish candle and sells after a bullish one.       |
//| EA always trades; no manual trade/wait toggle.                   |
//| Risk is based on a percent of equity or a fixed amount with      |
//| an ATR stop and 2R target.                                       |
//+------------------------------------------------------------------+
#property copyright "2024"
#property version   "1.0"
#property strict

#include <Trade/Trade.mqh>
#include <Indicators/Trend.mqh>

input double RiskPercent   = 1.0;  // percent of equity to risk (1%)
input double FixedRisk     = 0.0;  // fixed risk amount (0 = use percent)
input double RiskTolerance = 0.01; // allowed risk deviation (%)
input int    ATRPeriod     = 14;   // ATR period for stop
input double ATRStopMult   = 1.0;  // ATR stop-loss multiplier
input int    FastEMA       = 9;    // fast EMA period
input int    SlowEMA       = 20;   // slow EMA period
input double NearPct       = 0.5;  // allowed distance from EMA (%)

CTrade trade;                     // trading object
bool   allowTrading = true;       // switch off when equity too low
int    wins=0, losses=0;          // trade statistics
double sumWin=0, sumLoss=0;       // win/loss totals

CiMA   maFast;
CiMA   maSlow;

datetime lastBarTime = 0;        // track new bar
int fileHandle = INVALID_HANDLE;  // csv file handle
int errHandle  = INVALID_HANDLE;  // log file handle
double initialBalance = 0;       // for risk of ruin
bool   skipFirst    = true;      // skip first trade signal
ulong  pendingTicket = 0;        // ticket of pending order

datetime newsTimes[] = {
   D'2020.01.03 23:30',
   D'2020.01.23 23:15',
   D'2020.01.30 05:00',
   D'2020.02.04 13:30',
   D'2020.02.07 23:30',
   D'2020.02.13 22:00',
   D'2020.03.03 13:30',
   D'2020.03.06 23:30',
   D'2020.03.12 22:00',
   D'2020.03.12 23:15',
   D'2020.03.16 04:00',
   D'2020.04.03 22:30',
   D'2020.04.07 14:30',
   D'2020.04.30 04:00',
   D'2020.04.30 22:15',
   D'2020.05.01 22:30',
   D'2020.05.05 14:30',
   D'2020.05.14 21:00',
   D'2020.06.02 14:30',
   D'2020.06.04 22:15',
   D'2020.06.05 22:30',
   D'2020.06.11 04:00',
   D'2020.06.11 21:00',
   D'2020.07.03 22:30',
   D'2020.07.07 14:30',
   D'2020.07.16 22:15',
   D'2020.07.30 04:00',
   D'2020.08.04 14:30',
   D'2020.08.07 22:30',
   D'2020.08.13 21:00',
   D'2020.09.01 14:30',
   D'2020.09.04 22:30',
   D'2020.09.10 21:00',
   D'2020.09.10 22:15',
   D'2020.09.17 04:00',
   D'2020.10.02 22:30',
   D'2020.10.06 13:30',
   D'2020.10.29 23:15',
   D'2020.11.03 13:30',
   D'2020.11.06 05:00',
   D'2020.11.06 23:30',
   D'2020.11.12 22:00',
   D'2020.12.01 13:30',
   D'2020.12.04 23:30',
   D'2020.12.10 22:00',
   D'2020.12.10 23:15',
   D'2020.12.17 05:00',
   D'2021.01.01 23:30',
   D'2021.01.21 23:15',
   D'2021.01.28 05:00',
   D'2021.02.02 13:30',
   D'2021.02.05 23:30',
   D'2021.02.11 22:00',
   D'2021.03.02 13:30',
   D'2021.03.05 23:30',
   D'2021.03.11 22:00',
   D'2021.03.11 23:15',
   D'2021.03.18 04:00',
   D'2021.04.02 22:30',
   D'2021.04.06 14:30',
   D'2021.04.22 22:15',
   D'2021.04.29 04:00',
   D'2021.05.04 14:30',
   D'2021.05.07 22:30',
   D'2021.05.13 21:00',
   D'2021.06.01 14:30',
   D'2021.06.04 22:30',
   D'2021.06.10 21:00',
   D'2021.06.10 22:15',
   D'2021.06.17 04:00',
   D'2021.07.02 22:30',
   D'2021.07.06 14:30',
   D'2021.07.22 22:15',
   D'2021.07.29 04:00',
   D'2021.08.03 14:30',
   D'2021.08.06 22:30',
   D'2021.08.12 21:00',
   D'2021.09.03 22:30',
   D'2021.09.07 14:30',
   D'2021.09.09 21:00',
   D'2021.09.09 22:15',
   D'2021.09.23 04:00',
   D'2021.10.01 22:30',
   D'2021.10.05 13:30',
   D'2021.10.28 22:15',
   D'2021.11.02 13:30',
   D'2021.11.04 04:00',
   D'2021.11.05 22:30',
   D'2021.11.11 22:00',
   D'2021.12.03 23:30',
   D'2021.12.07 13:30',
   D'2021.12.09 22:00',
   D'2021.12.16 05:00',
   D'2021.12.16 23:15',
   D'2022.01.07 23:30',
   D'2022.01.27 05:00',
   D'2022.02.01 13:30',
   D'2022.02.03 23:15',
   D'2022.02.04 23:30',
   D'2022.02.10 22:00',
   D'2022.03.01 13:30',
   D'2022.03.04 23:30',
   D'2022.03.10 22:00',
   D'2022.03.10 23:15',
   D'2022.03.17 04:00',
   D'2022.04.01 22:30',
   D'2022.04.05 14:30',
   D'2022.04.14 22:15',
   D'2022.05.03 14:30',
   D'2022.05.05 04:00',
   D'2022.05.06 22:30',
   D'2022.05.12 21:00',
   D'2022.06.03 22:30',
   D'2022.06.07 14:30',
   D'2022.06.09 21:00',
   D'2022.06.09 22:15',
   D'2022.06.16 04:00',
   D'2022.07.01 22:30',
   D'2022.07.05 14:30',
   D'2022.07.21 22:15',
   D'2022.07.28 04:00',
   D'2022.08.02 14:30',
   D'2022.08.05 22:30',
   D'2022.08.11 21:00',
   D'2022.09.02 22:30',
   D'2022.09.06 14:30',
   D'2022.09.08 21:00',
   D'2022.09.08 22:15',
   D'2022.09.22 04:00',
   D'2022.10.04 13:30',
   D'2022.10.07 22:30',
   D'2022.10.27 22:15',
   D'2022.11.01 13:30',
   D'2022.11.03 04:00',
   D'2022.11.04 22:30',
   D'2022.11.10 22:00',
   D'2022.12.02 23:30',
   D'2022.12.06 13:30',
   D'2022.12.08 22:00',
   D'2022.12.15 05:00',
   D'2022.12.15 23:15',
   D'2023.01.06 23:30',
   D'2023.02.02 05:00',
   D'2023.02.02 23:15',
   D'2023.02.03 23:30',
   D'2023.02.07 13:30',
   D'2023.02.09 22:00',
   D'2023.03.03 23:30',
   D'2023.03.07 13:30',
   D'2023.03.09 22:00',
   D'2023.03.16 23:15',
   D'2023.03.23 04:00',
   D'2023.04.04 14:30',
   D'2023.04.07 22:30',
   D'2023.05.02 14:30',
   D'2023.05.04 04:00',
   D'2023.05.04 22:15',
   D'2023.05.05 22:30',
   D'2023.05.11 21:00',
   D'2023.06.02 22:30',
   D'2023.06.06 14:30',
   D'2023.06.08 21:00',
   D'2023.06.15 04:00',
   D'2023.06.15 22:15',
   D'2023.07.04 14:30',
   D'2023.07.07 22:30',
   D'2023.07.27 04:00',
   D'2023.07.27 22:15',
   D'2023.08.01 14:30',
   D'2023.08.04 22:30',
   D'2023.08.10 21:00',
   D'2023.09.01 22:30',
   D'2023.09.05 14:30',
   D'2023.09.14 21:00',
   D'2023.09.14 22:15',
   D'2023.09.21 04:00',
   D'2023.10.03 13:30',
   D'2023.10.06 22:30',
   D'2023.10.26 22:15',
   D'2023.11.02 04:00',
   D'2023.11.03 22:30',
   D'2023.11.07 13:30',
   D'2023.11.09 22:00',
   D'2023.12.01 23:30',
   D'2023.12.05 13:30',
   D'2023.12.14 05:00',
   D'2023.12.14 22:00',
   D'2023.12.14 23:15',
   D'2024.01.05 23:30',
   D'2024.01.25 23:15',
   D'2024.02.01 05:00',
   D'2024.02.02 23:30',
   D'2024.02.06 13:30',
   D'2024.02.08 22:00',
   D'2024.03.01 23:30',
   D'2024.03.05 13:30',
   D'2024.03.07 23:15',
   D'2024.03.14 22:00',
   D'2024.03.21 04:00',
   D'2024.04.02 13:30',
   D'2024.04.05 22:30',
   D'2024.04.11 22:15',
   D'2024.05.02 04:00',
   D'2024.05.03 22:30',
   D'2024.05.07 14:30',
   D'2024.05.09 21:00',
   D'2024.06.04 14:30',
   D'2024.06.06 22:15',
   D'2024.06.07 22:30',
   D'2024.06.13 04:00',
   D'2024.06.13 21:00',
   D'2024.07.02 14:30',
   D'2024.07.05 22:30',
   D'2024.07.18 22:15',
   D'2024.08.01 04:00',
   D'2024.08.02 22:30',
   D'2024.08.06 14:30',
   D'2024.08.08 21:00',
   D'2024.09.03 14:30',
   D'2024.09.06 22:30',
   D'2024.09.12 21:00',
   D'2024.09.12 22:15',
   D'2024.09.19 04:00',
   D'2024.10.01 14:30',
   D'2024.10.04 22:30',
   D'2024.10.24 22:15',
   D'2024.11.01 22:30',
   D'2024.11.05 13:30',
   D'2024.11.08 05:00',
   D'2024.11.14 22:00',
   D'2024.12.03 13:30',
   D'2024.12.06 23:30',
   D'2024.12.12 22:00',
   D'2024.12.12 23:15',
   D'2024.12.19 05:00',
   D'2025.01.03 23:30',
   D'2025.01.23 23:15',
   D'2025.01.30 05:00',
   D'2025.02.04 13:30',
   D'2025.02.07 23:30',
   D'2025.02.13 22:00',
   D'2025.03.04 13:30',
   D'2025.03.07 23:30',
   D'2025.03.13 22:00',
   D'2025.03.13 23:15',
   D'2025.03.20 04:00',
   D'2025.04.01 13:30',
   D'2025.04.04 22:30',
   D'2025.04.10 22:15',
   D'2025.05.01 04:00',
   D'2025.05.02 22:30',
   D'2025.05.06 14:30',
   D'2025.05.08 21:00',
   D'2025.06.03 14:30',
   D'2025.06.05 22:15',
   D'2025.06.06 22:30',
   D'2025.06.12 04:00',
   D'2025.06.12 21:00',
   D'2025.07.01 14:30',
   D'2025.07.04 22:30',
   D'2025.07.17 22:15',
   D'2025.07.31 04:00',
   D'2025.08.01 22:30',
   D'2025.08.05 14:30',
   D'2025.08.14 21:00',
   D'2025.09.02 14:30',
   D'2025.09.05 22:30',
   D'2025.09.11 21:00',
   D'2025.09.11 22:15',
   D'2025.09.18 04:00',
   D'2025.10.03 22:30',
   D'2025.10.07 13:30',
   D'2025.10.23 22:15',
   D'2025.11.04 13:30',
   D'2025.11.06 05:00',
   D'2025.11.07 23:30',
   D'2025.11.13 22:00',
   D'2025.12.02 13:30',
   D'2025.12.05 23:30',
   D'2025.12.11 22:00',
   D'2025.12.11 23:15',
   D'2025.12.18 05:00'
};


// write message to console and error log
void LogError(string msg)
  {
   string line = TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+" "+msg;
   Print(line);
   if(errHandle!=INVALID_HANDLE)
      FileWrite(errHandle,line);
  }

// helper to get ATR value of a given shift
double GetATR(int period,int shift)
  {
   double buf[];
   int handle=iATR(_Symbol,_Period,period);
   if(handle==INVALID_HANDLE)
      return 0.0;
   if(CopyBuffer(handle,0,shift,1,buf)<=0)
     {
      IndicatorRelease(handle);
      return 0.0;
     }
   double value=buf[0];
   IndicatorRelease(handle);
   return value;
  }

// determine if US Daylight Saving Time is active for a given local time
bool IsUSDST(datetime local)
  {
   datetime utc = local - 10*3600; // Brisbane is UTC+10
   MqlDateTime dt;
   TimeToStruct(utc,dt);

   MqlDateTime march={0};
   march.year=dt.year; march.mon=3; march.day=1; march.hour=7; // 07:00 UTC
   datetime start=StructToTime(march);
   MqlDateTime tmp;
   TimeToStruct(start,tmp);
   int wday=tmp.day_of_week;
   start+=((7-wday)%7)*86400; // first Sunday
   start+=7*86400;            // second Sunday

   MqlDateTime nov={0};
   nov.year=dt.year; nov.mon=11; nov.day=1; nov.hour=6; // 06:00 UTC
   datetime end=StructToTime(nov);
   TimeToStruct(end,tmp);
   wday=tmp.day_of_week;
   end+=((7-wday)%7)*86400;   // first Sunday

   return (utc>=start && utc<end);
  }

// check if current local time is within allowed trading hours
bool TradingHourAllowed(datetime local)
  {
   MqlDateTime lt;
   TimeToStruct(local,lt);
   bool usdst=IsUSDST(local);
   int startBlock=usdst?5:6;
   int endBlock=usdst?9:10;
   if(lt.hour>=startBlock && lt.hour<endBlock)
      return false;
   return true;
  }

// check if time is within 15 minutes of a news event
bool IsNewsTime(datetime local)
  {
   for(int i=0;i<ArraySize(newsTimes);i++)
     {
      datetime t=newsTimes[i];
      if(local>=t-15*60 && local<=t+15*60)
         return true;
     }
   return false;
  }

// close any open positions
void CloseAllPositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && !trade.PositionClose(ticket))
         LogError(StringFormat("Failed to close position %I64u",ticket));
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetDeviationInPoints(10); // 1 pip slippage
   lastBarTime    = iTime(_Symbol,_Period,0);
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(FastEMA<=0 || SlowEMA<=0)
     {
      LogError("EMA periods must be positive");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(!maFast.Create(_Symbol,_Period,FastEMA,0,MODE_EMA,PRICE_CLOSE))
     {
      LogError("Failed to create fast EMA");
      return(INIT_FAILED);
     }
   if(!maSlow.Create(_Symbol,_Period,SlowEMA,0,MODE_EMA,PRICE_CLOSE))
     {
      LogError("Failed to create slow EMA");
      return(INIT_FAILED);
     }

   maFast.Refresh();
   maSlow.Refresh();

   // open error log file
  errHandle = FileOpen("BacktesterErrors.log",FILE_READ|FILE_WRITE|FILE_ANSI|FILE_TXT|FILE_COMMON);
  if(errHandle!=INVALID_HANDLE)
     FileSeek(errHandle,0,SEEK_END);
  else
     Print("Cannot open error log file");

   // open CSV file and write header if new
  fileHandle = FileOpen("BacktesterTrades.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON);
  if(fileHandle!=INVALID_HANDLE)
    {
     FileSeek(fileHandle,0,SEEK_END);
     if(FileTell(fileHandle)==0)
        FileWrite(fileHandle,"Time","Type","Volume","Entry","SL","TP","Stop%","Target%");
    }
  else
     LogError("Cannot open CSV file");

  return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(fileHandle!=INVALID_HANDLE)
      FileClose(fileHandle);
   if(errHandle!=INVALID_HANDLE)
      FileClose(errHandle);

   int total=wins+losses;
   if(total>0)
     {
      double p=(double)wins/total;
      double q=1.0-p;
      double avgLoss=(losses>0)?(sumLoss/losses):0.0;
      double riskOfRuin=0.0;
      if(p>0 && avgLoss>0)
        {
         riskOfRuin = MathPow(q/p, initialBalance/avgLoss);
        }
      PrintFormat("Risk of Ruin: %.2f%%", riskOfRuin*100.0);
     }
   else
      Print("No trades taken - risk of ruin not calculated");
  }

//+------------------------------------------------------------------+
//| Capture closed trades to update stats                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
     {
      long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT)
        {
         double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
         if(profit>=0){wins++; sumWin+=profit;} else {losses++; sumLoss+=-profit;}
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now=TimeLocal();

   if(IsNewsTime(now))
     {
      CloseAllPositions();
      return;
     }

   // close any open trade if floating loss exceeds configured risk
   if(PositionsTotal()>0)
     {
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmt=(FixedRisk>0 ? FixedRisk : equity*RiskPercent/100.0);
      if(PositionSelect(_Symbol))
        {
         double profit=PositionGetDouble(POSITION_PROFIT);
         if(profit<-riskAmt)
            trade.PositionClose(_Symbol);
        }
      return; // do nothing else this tick when a trade exists
     }

   if(!allowTrading) return;

   datetime cur=iTime(_Symbol,_Period,0);
   if(cur==lastBarTime) return;   // wait for new bar
   lastBarTime=cur;

   // cancel leftover pending order if not filled on prior bar
   if(pendingTicket!=0)
     {
      if(OrderSelect(pendingTicket))
         trade.OrderDelete(pendingTicket);
      pendingTicket=0;
     }

   if(!TradingHourAllowed(now))
      return;

  double open1=iOpen(_Symbol,_Period,1);
  double close1=iClose(_Symbol,_Period,1);
  double price=iOpen(_Symbol,_Period,0); // next candle open

  if(pendingTicket!=0) return;            // waiting for pending order

  if(close1==open1) return;               // ignore doji

  maFast.Refresh();
  maSlow.Refresh();
  double fast = maFast.Main(0);
  double slow = maSlow.Main(0);
  if(fast<=0 || slow<=0 || fast==DBL_MAX || slow==DBL_MAX)
     return;

  double threshold = fast * (NearPct/100.0);
  double prevEMA   = maFast.Main(1);

  bool isBuy  = (close1<open1) && fast>slow && price>=fast && price<=fast+threshold && close1>prevEMA;
  bool isSell = (close1>open1) && fast<slow && price<=fast && price>=fast-threshold && close1<prevEMA;
  if(!isBuy && !isSell)
     return;

  if(skipFirst)
    {
     skipFirst=false;
     return; // ignore first trade opportunity
     }

   double atr=GetATR(ATRPeriod,1);
   if(atr<=0)
     {
      LogError("ATR calculation failed");
      return;
     }

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt  = (FixedRisk>0 ? FixedRisk : equity*RiskPercent/100.0);
   double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double minLot   = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double lotStep  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   double riskPerLot = atr*ATRStopMult/tickSize*tickVal;
   double idealLots  = riskAmt/riskPerLot;

   if(idealLots<minLot)
     {
      LogError("Equity too low for minimum lot with specified risk. Trading stopped.");
      allowTrading=false;
      return;
     }

   // round down so the calculated risk never exceeds the requested risk
   double lots = MathFloor(idealLots/lotStep)*lotStep;
   double actualRisk=riskPerLot*lots;
   double riskPct=actualRisk/equity*100.0;

   // reduce lot size further if rounding still exceeds the risk limit
   if(FixedRisk>0)
     {
      while(actualRisk>riskAmt && lots-lotStep>=minLot)
        {
         lots-=lotStep;
         actualRisk=riskPerLot*lots;
         riskPct=actualRisk/equity*100.0;
        }
     }
   else
     {
      while(riskPct>RiskPercent && lots-lotStep>=minLot)
        {
         lots-=lotStep;
         actualRisk=riskPerLot*lots;
         riskPct=actualRisk/equity*100.0;
        }
     }

  // skip trades that fall outside the allowed risk range
  if(FixedRisk>0)
    {
     if(MathAbs(actualRisk - riskAmt) > riskAmt*RiskTolerance/100.0)
       {
        LogError("Cannot size position within risk tolerance. Trade skipped.");
        return;
       }
    }
  else
    {
     if(MathAbs(riskPct - RiskPercent) > RiskTolerance)
       {
        LogError("Cannot size position within risk tolerance. Trade skipped.");
        return;
       }
    }

  double sl,tp;
  if(isBuy){sl=price-atr*ATRStopMult; tp=price+atr*ATRStopMult*2.0;}
  else     {sl=price+atr*ATRStopMult; tp=price-atr*ATRStopMult*2.0;}

   double margin;
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   if(!OrderCalcMargin(orderType,_Symbol,lots,price,margin))
     {
      LogError("OrderCalcMargin failed");
      return;
     }
   if(margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      LogError("Not enough free margin for trade");
      return;
     }

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action=TRADE_ACTION_PENDING;
   req.symbol=_Symbol;
   req.volume=lots;
   req.type=orderType;
   req.price=price;
   req.sl=sl;
   req.tp=tp;
   req.type_time=ORDER_TIME_GTC;
   req.comment="Backtester";

   if(!OrderSend(req,res) || res.retcode!=TRADE_RETCODE_DONE)
     {
      LogError(StringFormat("Order failed: retcode=%d comment=%s",res.retcode,res.comment));
      return;
     }
   else
      pendingTicket=res.order;

   double stopPct = MathAbs(price-sl)/price*100.0;
   double targPct = MathAbs(tp-price)/price*100.0;
   if(fileHandle!=INVALID_HANDLE)
      FileWrite(fileHandle,
                TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
                (isBuy?"BUY":"SELL"),
                DoubleToString(lots,2),
                DoubleToString(price,_Digits),
                DoubleToString(sl,_Digits),
                DoubleToString(tp,_Digits),
                DoubleToString(stopPct,2),
                DoubleToString(targPct,2));

   PrintFormat("%s %s %.2f lots @%.5f SL %.5f TP %.5f Risk %.2f%% (%.2f %s)",
               TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
               (isBuy?"BUY":"SELL"),lots,price,sl,tp,riskPct,actualRisk,
               AccountInfoString(ACCOUNT_CURRENCY));
  }
//+------------------------------------------------------------------+

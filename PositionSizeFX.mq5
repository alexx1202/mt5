//+------------------------------------------------------------------+
//|                                                PositionSizeFX.mq5|
//|   Calculates position size, stop loss and take profit levels     |
//|   with a few options for different brokers.                      |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#import "shell32.dll"
   int ShellExecuteW(int hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);
#import

enum ENUM_RISK_MODE
{
   RISK_FIXED_PERCENT = 0,
   RISK_FIXED_AUD     = 1
};

enum ENUM_BROKER_MODE
{
   BROKER_PEPPERSTONE = 0,
   BROKER_OANDA       = 1
};

enum ENUM_ORDER_SIDE
{
   ORDER_BUY  = 0,
   ORDER_SELL = 1
};

enum ENUM_BALANCE_MODE
{
   BALANCE_PEPPERSTONE = 0,
   BALANCE_OANDA       = 1
};

//--- Inputs
input ENUM_RISK_MODE   RiskMode           = RISK_FIXED_PERCENT;
input double           FixedRiskAmountAUD = 100.0;
input double           RiskPercentage     = 1.0;
input double           StopLossPips       = 20.0;
input ENUM_BROKER_MODE BrokerMode         = BROKER_PEPPERSTONE;
input ENUM_BALANCE_MODE BalanceMode       = BALANCE_PEPPERSTONE;
input double           RewardRiskRatio    = 2.0;
input ENUM_ORDER_SIDE  OrderSide          = ORDER_BUY;

input string           OandaAccountID     = "001-011-7821430-001"; // ID used to query OANDA balance
input string           OandaApiToken      = "25becd000966ef6caa04a753972898fb-fb183afa2b32a7de59b2acdcee7f9b81"; // API token for OANDA REST requests

//--- Extra adjustable parameters
input double           CommissionPerLot   = 7.0;     // Commission for 1 lot (AUD)
input double           VolumeStep         = 0.01;    // Minimum lot step (auto-adjusts by broker)
input double           MinNetProfitAUD    = 20.0;    // Minimum net profit at TP (AUD)

//--- Determine leverage tier for Pepperstone symbols
double GetPepperstoneLeverage(string symbol)
  {
     string sym = symbol;      // copy symbol so we can modify it
     StringToUpper(sym);       // converts sym to uppercase

     // major currency pairs 30:1
     if(StringFind(sym,"USD")>=0 &&
        (StringFind(sym,"EUR")>=0 || StringFind(sym,"GBP")>=0 ||
         StringFind(sym,"AUD")>=0 || StringFind(sym,"NZD")>=0 ||
         StringFind(sym,"CAD")>=0 || StringFind(sym,"CHF")>=0 ||
         StringFind(sym,"JPY")>=0))
        return 30.0;

     // other FX pairs 20:1
     bool isFxPair = (StringLen(sym)==6 || StringLen(sym)==7);
     if(isFxPair)
        return 20.0;

     // gold or major indices 20:1
     if(StringFind(sym,"XAU")>=0 || StringFind(sym,"US500")>=0 ||
        StringFind(sym,"NAS")>=0 || StringFind(sym,"UK")>=0 ||
        StringFind(sym,"GER")>=0)
        return 20.0;

     // commodities excluding gold or minor indices 10:1
     if(StringFind(sym,"XAG")>=0 || StringFind(sym,"WTI")>=0 ||
        StringFind(sym,"BRENT")>=0)
        return 10.0;

     // cryptocurrency assets 2:1
     if(StringFind(sym,"BTC")>=0 || StringFind(sym,"ETH")>=0 ||
        StringFind(sym,"LTC")>=0 || StringFind(sym,"XRP")>=0)
        return 2.0;

     // shares or other assets 5:1
     return 5.0;
  }

//+------------------------------------------------------------------+
//| Script entry point                                               |
//+------------------------------------------------------------------+
void OnStart()
{
   string symbol   = _Symbol;
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   if(BalanceMode == BALANCE_OANDA)
   {
      bool fetched=false;
      if(StringLen(OandaAccountID)>0 && StringLen(OandaApiToken)>0)
      {
         string url=StringFormat("https://api-fxtrade.oanda.com/v3/accounts/%s/summary",OandaAccountID);
         char  result[];
         string headers="Authorization: Bearer "+OandaApiToken+"\r\n";
         string res_headers;
         char  data[];
         int code=WebRequest("GET",url,headers,5000,data,result,res_headers);
         if(code==200)
         {
            string js=CharArrayToString(result);
            int p=StringFind(js,"\"balance\":");
            if(p>=0)
            {
               p+=10;
               string tmp=StringSubstr(js,p);
               int end=StringFind(tmp,"\"",0);
               if(end>0)
                  tmp=StringSubstr(tmp,0,end);
               double bal=StringToDouble(tmp);
               if(bal>0)
               {
                  balance=bal;
                  fetched=true;
               }
            }
         }
      }
      if(!fetched)
      {
         Print("Error: failed to retrieve OANDA balance");
         return;
      }
   }
   // for Pepperstone we rely solely on the platform balance
   if(balance <= 0)
   {
      Print("Error: invalid account balance");
      return;
   }

   double price    = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(price <= 0)
   {
      Print("Error: failed to get price for symbol ", symbol);
      return;
   }

   bool isBuy = (OrderSide == ORDER_BUY);

   //--- pip size and value
   int digits      = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double pipSize  = MathPow(10.0, -digits + 1);           // distance of 1 pip
   double tickVal  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double pipValue = tickVal * pipSize / tickSize;         // monetary value of 1 pip per lot

   //--- choose commission and minimum lot step based on broker
   double commissionPerLot = CommissionPerLot;
   double volumeStepLocal;
   if(BrokerMode == BROKER_OANDA)
   {
      // OANDA charges no commission by default and allows trading single units
      if(commissionPerLot == 7.0) commissionPerLot = 0.0;
      volumeStepLocal = 0.00001;        // minimum step of 1 unit
   }
   else
   {
      // Pepperstone uses a minimum step of 0.01 lots (1,000 units)
      volumeStepLocal = 0.01;
   }

   //--- calculate risk amount
   double riskAmount = (RiskMode == RISK_FIXED_AUD)
                       ? FixedRiskAmountAUD
                       : balance * RiskPercentage / 100.0;
   if(riskAmount <= 0)
   {
      Print("Error: invalid risk amount");
      return;
   }

   //--- lot size using direct formula
   double lotSizeRaw = riskAmount / (StopLossPips * pipValue + commissionPerLot);
   double lotSize    = MathCeil(lotSizeRaw / volumeStepLocal) * volumeStepLocal;

   //--- round precision
   int lotPrec = (int)MathRound(MathLog10(1.0 / volumeStepLocal));
   lotSize = NormalizeDouble(lotSize, lotPrec);

   //--- commission
   double commission = lotSize * commissionPerLot;

   //--- check margin requirement
   double marginNeeded = 0.0;
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, symbol, lotSize, price, marginNeeded))
   {
      Print("Error: OrderCalcMargin failed with code ", GetLastError());
      return;
   }
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(marginNeeded > freeMargin)
   {
      PrintFormat("Warning: not enough free margin (needed %.2f, available %.2f)", marginNeeded, freeMargin);
   }

   //--- confirm using Pepperstone leverage tiers
   double leverage         = GetPepperstoneLeverage(symbol);
   double contractSize     = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double notionalValue    = lotSize * contractSize * price;
   double marginByLeverage = notionalValue / leverage;
   if(marginByLeverage > freeMargin)
   {
      PrintFormat("Warning: Pepperstone leverage 1:%.0f requires %.2f margin but only %.2f is available", leverage, marginByLeverage, freeMargin);
   }

   //--- TP calculation
   double tpPips          = StopLossPips * RewardRiskRatio;
   double requiredProfit  = MathMax(riskAmount * RewardRiskRatio, MinNetProfitAUD);
   double netReward       = tpPips * pipValue * lotSize - commission;
   while(netReward < requiredProfit)
   {
      tpPips += 0.5;
      netReward = tpPips * pipValue * lotSize - commission;
   }

   //--- prices
   double slPrice  = isBuy ? price - StopLossPips * pipSize : price + StopLossPips * pipSize;
   double tpPrice  = isBuy ? price + tpPips * pipSize       : price - tpPips * pipSize;

   //--- build output
   string timeStamp   = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   //--- sanitize timestamp for file name
   StringReplace(timeStamp, ":", "-");
   StringReplace(timeStamp, " ", "_");
   string fileName    = StringFormat("PositionSizeOutput-%s.txt", timeStamp);

   string out = "=== Position Size Calculation ===\n";
   out += StringFormat("Symbol: %s\n", symbol);
   out += StringFormat("Trade Side: %s\n", isBuy ? "Buy" : "Sell");
   out += StringFormat("Account Balance: AUD%.2f\n", balance);
   out += StringFormat("Risk Amount: AUD%.2f\n", riskAmount);
   out += StringFormat("Lot Size: %.5f\n", lotSize);
   out += StringFormat("Commission: AUD%.2f\n", commission);
   out += StringFormat("Net Risk: AUD%.2f\n", StopLossPips * pipValue * lotSize + commission);
   out += StringFormat("Stop Loss Price: %.5f (%.1f pips)\n", slPrice, StopLossPips);
   out += StringFormat("Take Profit Price: %.5f (%.1f pips | RR=1:%.2f)\n", tpPrice, tpPips, RewardRiskRatio);
   out += StringFormat("Expected Net Profit at TP: AUD%.2f\n", netReward);
   out += StringFormat("Minimum Net Profit Target: AUD%.2f\n", MinNetProfitAUD);
   out += StringFormat("Margin Needed: %.2f\n", marginNeeded);
   out += StringFormat("Margin by Pepperstone 1:%.0f: %.2f\n", leverage, marginByLeverage);

   int h = FileOpen(fileName, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      Print("Error: could not open file for writing", GetLastError());
      return;
   }
   FileWrite(h, out);
   FileClose(h);

   string folderPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files";
   int res = ShellExecuteW(0, "open", folderPath, NULL, NULL, 1);
   if(res <= 32)
      Print("Note: output written to ", folderPath, " but folder could not be opened.");

   //--- OANDA webhook JSON (only if OANDA)
   if(BrokerMode == BROKER_OANDA)
   {
      string action = isBuy ? "buy" : "sell";
      int qty       = (int)MathRound(lotSize * 100000.0);
      string json   = "{\n";
      json += " \"symbol\": \"{{ticker}}\",\n";
      json += StringFormat(" \"action\": \"%s\",\n", action);
      json += StringFormat(" \"quantity\": %d,\n", qty);
      json += StringFormat(" \"take_profit_price\": \"{{close}} %s %.3f\",\n", isBuy?"+":"-", tpPips * pipSize);
      json += StringFormat(" \"stop_loss_price\": \"{{close}} %s %.3f\"\n", isBuy?"-":"+", StopLossPips * pipSize);
      json += "}\n\nWEBHOOK (OANDA):\nhttps://app.signalstack.com/hook/iodL7zcSTfiCDnMPwfmF2P\n";
      int oh = FileOpen("OANDA_Swing.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(oh != INVALID_HANDLE)
      {
         FileWrite(oh, json);
         FileClose(oh);
      }
   }
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                PositionSizeFX.mq5|
//|   Calculates position size, stop loss and take profit levels     |
//|   with a single BrokerMode option to switch between              |
//|   Pepperstone and OANDA compatibility.                           |
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

// choose whether stop loss is entered in pips or in broker points
enum ENUM_SL_UNIT
{
   SL_PIPS   = 0,
   SL_POINTS = 1
};

// asset class categories for Pepperstone symbols
enum ENUM_PS_ASSET_CLASS
{
   PS_ASSET_FX = 0,
   PS_ASSET_COMMODITY,
   PS_ASSET_INDEX,
   PS_ASSET_CRYPTO,
   PS_ASSET_SHARE,
   PS_ASSET_OTHER
};


//--- Inputs
input ENUM_RISK_MODE   RiskMode           = RISK_FIXED_PERCENT;
input double           FixedRiskAmountAUD = 100.0;
input double           RiskPercentage     = 1.0;
input ENUM_SL_UNIT     StopLossUnit       = SL_PIPS;   // dropdown for SL units
input double           StopLossValue      = 20.0;      // stop loss amount
input ENUM_BROKER_MODE BrokerMode         = BROKER_PEPPERSTONE;
input double           RewardRiskRatio    = 2.0;
input ENUM_ORDER_SIDE  OrderSide          = ORDER_BUY;

input double           OandaBalance       = 0.0; // manually entered OANDA balance

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

// determine if a symbol is a Pepperstone commodity (no commission on Razor)
bool IsPepperstoneCommodity(string symbol)
  {
     string sym = symbol;
     StringToUpper(sym);
     if(StringFind(sym,"XAU")>=0 || StringFind(sym,"XAG")>=0 ||
        StringFind(sym,"XPT")>=0 || StringFind(sym,"XPD")>=0 ||
        StringFind(sym,"BRENT")>=0 || StringFind(sym,"WTI")>=0 ||
        StringFind(sym,"OIL")>=0 || StringFind(sym,"NGAS")>=0 ||
        StringFind(sym,"COFFEE")>=0 || StringFind(sym,"COCOA")>=0 ||
        StringFind(sym,"COTTON")>=0 || StringFind(sym,"SUGAR")>=0)
        return true;
     return false;
  }

// categorize Pepperstone symbols into major asset classes
ENUM_PS_ASSET_CLASS GetPepperstoneAssetClass(string symbol)
  {
     string sym = symbol;
     StringToUpper(sym);

     if(IsPepperstoneCommodity(sym))
        return PS_ASSET_COMMODITY;

     if(StringFind(sym,"US500")>=0 || StringFind(sym,"NAS")>=0 ||
        StringFind(sym,"UK")>=0   || StringFind(sym,"GER")>=0 ||
        StringFind(sym,"JP")>=0   || StringFind(sym,"HK")>=0)
        return PS_ASSET_INDEX;

     if(StringFind(sym,"BTC")>=0 || StringFind(sym,"ETH")>=0 ||
        StringFind(sym,"LTC")>=0 || StringFind(sym,"XRP")>=0)
        return PS_ASSET_CRYPTO;

     bool isFxPair = (StringLen(sym)==6 || StringLen(sym)==7);
     if(isFxPair)
        return PS_ASSET_FX;

     return PS_ASSET_SHARE;
  }

//+------------------------------------------------------------------+
//| Script entry point                                               |
//+------------------------------------------------------------------+
void OnStart()
{
   string symbol   = _Symbol;
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   if(BrokerMode == BROKER_OANDA && OandaBalance > 0)
   {
      balance = OandaBalance;   // use manually entered balance for OANDA
   }
   // otherwise Pepperstone uses the balance reported by the platform
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
   double pointSize = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickVal  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double pipValue = tickVal * pipSize / tickSize;         // monetary value of 1 pip per lot

   // convert stop loss input into pips
   double StopLossPips = (StopLossUnit == SL_PIPS)
                         ? StopLossValue
                         : StopLossValue * pointSize / pipSize;

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
      // non-FX assets have no commission on Pepperstone Razor accounts
      ENUM_PS_ASSET_CLASS asset = GetPepperstoneAssetClass(symbol);
      if(asset != PS_ASSET_FX && commissionPerLot == 7.0)
         commissionPerLot = 0.0;
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

  string leverageCheckMsg;
  if(marginByLeverage <= freeMargin)
     leverageCheckMsg = StringFormat("PASS: margin requirement %.2f is within free margin %.2f for leverage 1:%.0f", marginByLeverage, freeMargin, leverage);
  else
     leverageCheckMsg = StringFormat("FAIL: margin requirement %.2f exceeds free margin %.2f for leverage 1:%.0f", marginByLeverage, freeMargin, leverage);
  Print(leverageCheckMsg);

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

   string slUnitsText = (StopLossUnit == SL_PIPS) ? "pips" : "points";
   string out = "=== Position Size Calculation ===\n";
   out += StringFormat("Symbol: %s\n", symbol);
   out += StringFormat("Trade Side: %s\n", isBuy ? "Buy" : "Sell");
   out += StringFormat("Account Balance: AUD%.2f\n", balance);
   out += StringFormat("Risk Amount: AUD%.2f\n", riskAmount);
   out += StringFormat("Lot Size: %.5f\n", lotSize);
   out += StringFormat("Commission: AUD%.2f\n", commission);
   out += StringFormat("Net Risk: AUD%.2f\n", StopLossPips * pipValue * lotSize + commission);
   out += StringFormat("Stop Loss Price: %.5f (%.1f %s)\n", slPrice, StopLossValue, slUnitsText);
   out += StringFormat("Take Profit Price: %.5f (%.1f pips | RR=1:%.2f)\n", tpPrice, tpPips, RewardRiskRatio);
   out += StringFormat("Expected Net Profit at TP: AUD%.2f\n", netReward);
   out += StringFormat("Minimum Net Profit Target: AUD%.2f\n", MinNetProfitAUD);
  out += StringFormat("Margin Needed: %.2f\n", marginNeeded);
  out += StringFormat("Margin by Pepperstone 1:%.0f: %.2f\n", leverage, marginByLeverage);
  out += leverageCheckMsg + "\n";

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

//+------------------------------------------------------------------+
//| Crypto Risk Calculator Script for MT5 (Calculator Only)         |
//| This script does NOT place any trades. It only outputs trade    |
//| details to a text file for review.                              |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

//--- Import for opening text file after creation
#import "shell32.dll"
   int ShellExecuteW(int hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);
#import

//--- Enumerations for direction and order type
enum EDirection { DIRECTION_LONG=0, DIRECTION_SHORT=1 };
enum EOrderKind { ORDER_KIND_MARKET=0, ORDER_KIND_LIMIT=1 };

//--- Script inputs
input EDirection   TradeDirection   = DIRECTION_LONG;    // 0=Long, 1=Short
input double       RiskPercent      = 0.5;              // % of account balance to risk
input double       FixedRiskAmount  = 0.0;              // Fixed amount to risk; if >0 overrides RiskPercent
input double       RR_Ratio         = 2.0;              // Reward-to-risk ratio
input EOrderKind   EntryOrderType   = ORDER_KIND_MARKET; // Market or Limit (calc only)
input int          StopLossPoints   = 100;              // Stop-loss in points (100 = 100 × _Point)
input int          Slippage         = 10;               // Slippage in points (for reference)
input string       SymbolToTrade    = "";              // Symbol; if empty, uses chart symbol

void OnStart()
{
   //--- Determine symbol
   string symbol = StringLen(SymbolToTrade) > 0 ? SymbolToTrade : _Symbol;

   //--- Account balance
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0)
   {
      Print("Error: Account balance is invalid or zero.");
      return;
   }

   //--- Input validation
   if(FixedRiskAmount <= 0)
   {
      if(RiskPercent <= 0 || RiskPercent > 100)
      {
         Print("Error: RiskPercent must be between 0 and 100.");
         return;
      }
   }
   if(StopLossPoints <= 0)
   {
      Print("Error: StopLossPoints must be greater than zero.");
      return;
   }

   //--- Calculate risk amount
   double riskAmount = FixedRiskAmount > 0 ? FixedRiskAmount : balance * (RiskPercent / 100.0);
   if(riskAmount <= 0)
   {
      Print("Error: Risk amount must be greater than zero.");
      return;
   }

   //--- Fetch entry price
   double price = TradeDirection == DIRECTION_LONG 
                  ? SymbolInfoDouble(symbol, SYMBOL_ASK) 
                  : SymbolInfoDouble(symbol, SYMBOL_BID);
   if(price <= 0)
   {
      PrintFormat("Error: Unable to fetch price for %s.", symbol);
      return;
   }

   //--- Stop-loss and take-profit levels
   double stopPrice   = TradeDirection == DIRECTION_LONG 
                        ? price - StopLossPoints * _Point
                        : price + StopLossPoints * _Point;
   double targetPrice = TradeDirection == DIRECTION_LONG 
                        ? price + StopLossPoints * RR_Ratio * _Point
                        : price - StopLossPoints * RR_Ratio * _Point;

   //--- Volume calculation
   double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double stopDistance = MathAbs(price - stopPrice);
   double riskPerLot   = stopDistance * contractSize;
   if(riskPerLot <= 0)
   {
      Print("Error: Invalid stop distance or contract size.");
      return;
   }
   double rawVolume = riskAmount / riskPerLot;
   double step      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minVol    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volume    = MathMax(step * MathFloor(rawVolume / step), minVol);
   if(volume < minVol)
   {
      PrintFormat("Warning: Calculated volume is below minimum. Using minimum volume %.2f", minVol);
      volume = minVol;
   }

   //--- File names (include date-time stamp)
   string timeStamp   = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string fileNameOnly= StringFormat("CryptoCalcOutput-%s.txt", timeStamp);

   //--- Build result text
   string text = "Symbol: " + symbol + "\n";
   text += "Direction: " + (TradeDirection == DIRECTION_LONG ? "LONG" : "SHORT") + "\n";
   text += StringFormat("Entry Price: %.8f\n", price);
   text += StringFormat("Stop Loss Price: %.8f (%d points)\n", stopPrice, StopLossPoints);
   text += StringFormat("Take Profit Price: %.8f (RR=%.2f)\n", targetPrice, RR_Ratio);
   text += StringFormat("Calculated Volume: %.2f\n", volume);
   text += StringFormat("Risk Amount: %.2f %s\n", riskAmount, AccountInfoString(ACCOUNT_CURRENCY));
   text += StringFormat("Balance: %.2f %s\n", balance, AccountInfoString(ACCOUNT_CURRENCY));
   text += StringFormat("Order Type (calc only): %s\n", EntryOrderType == ORDER_KIND_MARKET ? "Market" : "Limit");

   //--- Write results to file (relative path to MQL5/Files)
   int fileHandle = FileOpen(fileNameOnly, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fileHandle < 0)
   {
      Print("Error: Could not open file for writing: " + fileNameOnly);
      return;
   }
   FileWriteString(fileHandle, text);
   FileClose(fileHandle);

   //--- Launch the output file using full path
   string fullPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + fileNameOnly;
   int result = ShellExecuteW(0, "open", fullPath, NULL, NULL, 1);
   if(result <= 32)
      PrintFormat("Warning: Could not open output file. Error code %d", result);

   PrintFormat("Calculation complete. Output written to %s", fullPath);
}

//+------------------------------------------------------------------+
//|                                                FXScanner.mq5    |
//|           Integrated FX Scanner with Spread Calculation         |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include <Arrays/ArrayString.mqh>
#import "shell32.dll"
   int ShellExecuteW(int hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);
#import
#import "user32.dll"
   int MessageBoxW(int hWnd, string lpText, string lpCaption, int uType);
#import

// Script inputs provide flexibility to end users.
input string FilePrefix        = "FX_Data_";   // Prefix for generated CSV files
input string usdxSymbol        = "USDX.a";     // Symbol used to compare correlation
input bool   ShowDebugMessages = true;         // Print progress information
input int    ScanIntervalMinutes = 30;         // Interval between scans

string g_outputFolder = "";                    // Folder where files are saved

// Timeframes for analysis can be adjusted as needed.
ENUM_TIMEFRAMES timeframes[] =
{
    PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30,
    PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1
};

//+------------------------------------------------------------------+
//| Create a new folder with timestamp                               |
//+------------------------------------------------------------------+
string CreateTimestampedFolder()
{
    string stamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    StringReplace(stamp, ":", "-");
    StringReplace(stamp, ".", "-");
    StringReplace(stamp, " ", "_");
    string base = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\FXScan_" + stamp;
    if(!FolderCreate(base))
        Print("Failed to create folder ", base, ". Error: ", GetLastError());
    return base + "\\";
}

//+------------------------------------------------------------------+
//| Script entry point                                               |
//+------------------------------------------------------------------+
void OnStart()
{
    if(ShowDebugMessages)
        Print("Starting FX Scanner Script v1.35 (All Tick-Based + USDX Correlation + Integrated Spread)");

    while(!IsStopped())
    {
        g_outputFolder = CreateTimestampedFolder();
        if(ShowDebugMessages)
            Print("Saving reports to ", g_outputFolder);

        PerformScan(g_outputFolder);

        if(IsStopped())
            break;

        if(ShowDebugMessages)
            Print("Waiting ", ScanIntervalMinutes, " minutes for next scan...");
        Sleep((ulong)ScanIntervalMinutes * 60 * 1000);
    }
}

//+------------------------------------------------------------------+
//| Main scanning function                                           |
//+------------------------------------------------------------------+
void PerformScan(const string folderPath)
{
    CArrayString symbols;
    int symbolCount = GetWatchlistSymbols(symbols);
    if(symbolCount == 0)
    {
        if(ShowDebugMessages) Print("No symbols in Market Watch to scan");
        return;
    }

    // Open all required CSV files
    int swapHandle   = FileOpen(folderPath + FilePrefix + "Swap.csv", FILE_WRITE | FILE_ANSI | FILE_CSV | FILE_TXT);
    int rangeHandle  = FileOpen(folderPath + FilePrefix + "Range.csv", FILE_WRITE | FILE_ANSI | FILE_CSV | FILE_TXT);
    int changeHandle = FileOpen(folderPath + FilePrefix + "Change.csv", FILE_WRITE | FILE_ANSI | FILE_CSV | FILE_TXT);
    int corrHandle   = FileOpen(folderPath + FilePrefix + "USDXCorrelation.csv", FILE_WRITE | FILE_ANSI | FILE_CSV | FILE_TXT);
    if(swapHandle < 0 || rangeHandle < 0 || changeHandle < 0 || corrHandle < 0)
    {
        Print("Failed to open output files. Error: ", GetLastError());
        if(swapHandle   >= 0) FileClose(swapHandle);
        if(rangeHandle  >= 0) FileClose(rangeHandle);
        if(changeHandle >= 0) FileClose(changeHandle);
        if(corrHandle   >= 0) FileClose(corrHandle);
        return;
    }

    // Write headers
    FileWriteString(swapHandle,  "Symbol,SwapLong,SwapShort\r\n");
    FileWriteString(rangeHandle, "Symbol,");
    FileWriteString(changeHandle,"Symbol,");
    FileWriteString(corrHandle,  "Symbol,");
    for(int j = 0; j < ArraySize(timeframes); j++)
    {
        string tfStr = EnumToString(timeframes[j]);
        FileWriteString(rangeHandle,  tfStr + ",");
        FileWriteString(changeHandle, tfStr + ",");
        FileWriteString(corrHandle,   tfStr + ",");
    }
    FileWriteString(rangeHandle,  "\r\n");
    FileWriteString(changeHandle, "\r\n");
    FileWriteString(corrHandle,   "\r\n");

    // Process each symbol
    for(int i = 0; i < symbols.Total(); i++)
    {
        string symbol = symbols.At(i);
        int progress  = (int)MathRound((double)(i+1) / symbols.Total() * 100);
        if(ShowDebugMessages)
            PrintFormat("[%3d%%] Processing symbol (%d/%d): %s", progress, i+1, symbols.Total(), symbol);

        // --- Swap information ---
        double swapLong, swapShort;
        if(!SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG, swapLong) ||
           !SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT, swapShort))
        {
            Print("Failed to read swap for ", symbol);
            swapLong = 0.0;
            swapShort = 0.0;
        }
        FileWriteString(swapHandle, StringFormat("%s,%.4f,%.4f\r\n", symbol,
                                                NormalizeDouble(swapLong,4),
                                                NormalizeDouble(swapShort,4)));

        // Current price used for range calculations
        double bidPrice;
        if(!SymbolInfoDouble(symbol, SYMBOL_BID, bidPrice) || bidPrice <= 0.0)
        {
            Print("Invalid price for ", symbol);
            bidPrice = 1.0; // Avoid division by zero
        }

        // Prepare lines for Range and Change CSVs
        FileWriteString(rangeHandle,  symbol + ",");
        FileWriteString(changeHandle, symbol + ",");

        // --- Range, Change and Correlation ---
        FileWriteString(corrHandle, symbol + ",");
        for(int j = 0; j < ArraySize(timeframes); j++)
        {
            // Load ticks for this timeframe only once
            datetime endTime   = TimeCurrent();
            datetime startTime = endTime - PeriodSeconds(timeframes[j]);
            MqlTick ticks[];
            int tickCount = CopyTicksRange(symbol, ticks, COPY_TICKS_ALL, startTime * 1000, endTime * 1000);
            if(tickCount <= 0)
            {
                Print("No ticks for ", symbol, " on ", EnumToString(timeframes[j]));
            }

            // Range calculation
            double high = -DBL_MAX, low = DBL_MAX;
            for(int k = 0; k < tickCount; k++)
            {
                double mid = (ticks[k].ask + ticks[k].bid) / 2.0;
                if(mid > high) high = mid;
                if(mid < low)  low  = mid;
            }
            double rangePercent = 0.0;
            if(low < DBL_MAX && high > -DBL_MAX && bidPrice > 0.0)
                rangePercent = (high - low) / bidPrice * 100.0;
            FileWriteString(rangeHandle, StringFormat("%.4f%%,", NormalizeDouble(rangePercent,4)));

            // Change calculation
            double startPrice = 0.0, endPrice = 0.0;
            if(tickCount >= 2)
            {
                startPrice = (ticks[0].ask + ticks[0].bid) / 2.0;
                endPrice   = (ticks[tickCount - 1].ask + ticks[tickCount - 1].bid) / 2.0;
            }
            double change = 0.0;
            if(startPrice > 0.0)
                change = (endPrice - startPrice) / startPrice * 100.0;
            FileWriteString(changeHandle, StringFormat("%.4f%%,", NormalizeDouble(change,4)));

            // Correlation with USDX symbol
            double correlation = NormalizeDouble(
                CalculateTickCorrelation(symbol, usdxSymbol, timeframes[j]), 4);
            FileWriteString(corrHandle, StringFormat("%.4f,", correlation));
        }
        FileWriteString(rangeHandle,  "\r\n");
        FileWriteString(changeHandle, "\r\n");
        FileWriteString(corrHandle,   "\r\n");
    }

    // Close files
    FileClose(swapHandle);
    FileClose(rangeHandle);
    FileClose(changeHandle);
    FileClose(corrHandle);

    // Spread report uses a separate file
    WriteSpreadReport(symbols, folderPath);

    if(ShowDebugMessages)
    {
        Print("All files saved.");
        Print("Scan complete. Total symbols processed: ", symbols.Total());
    }

    //--- Open folder containing CSV files
    int openRes = ShellExecuteW(0, "open", folderPath, NULL, NULL, 1);
    if(openRes <= 32)
        Print("Note: output written to ", folderPath, " but folder could not be opened.");

    //--- Simple Windows push notification
    MessageBoxW(0, "FX Scanner complete!", "FXScanner", 0);
}

//+------------------------------------------------------------------+
//| Retrieve symbols in Market Watch                                 |
//+------------------------------------------------------------------+
int GetWatchlistSymbols(CArrayString &symbols)
{
    int total = SymbolsTotal(true);
    for(int i = 0; i < total; i++)
        symbols.Add(SymbolName(i, true));
    return total;
}

//+------------------------------------------------------------------+
//| Calculate tick-based correlation between two symbols             |
//+------------------------------------------------------------------+
double CalculateTickCorrelation(const string symbolA, const string symbolB, const ENUM_TIMEFRAMES tf)
{
    datetime endTime   = TimeCurrent();
    datetime startTime = endTime - PeriodSeconds(tf);
    MqlTick ticksA[], ticksB[];
    int countA = CopyTicksRange(symbolA, ticksA, COPY_TICKS_ALL, startTime * 1000, endTime * 1000);
    int countB = CopyTicksRange(symbolB, ticksB, COPY_TICKS_ALL, startTime * 1000, endTime * 1000);
    int minCount = MathMin(countA, countB);
    if(minCount < 10)
        return 0.0;

    double sumX=0, sumY=0, sumX2=0, sumY2=0, sumXY=0;
    for(int i = 0; i < minCount; i++)
    {
        double x = (ticksA[i].ask + ticksA[i].bid) / 2.0;
        double y = (ticksB[i].ask + ticksB[i].bid) / 2.0;
        sumX  += x;
        sumY  += y;
        sumX2 += x * x;
        sumY2 += y * y;
        sumXY += x * y;
    }

    double num = minCount * sumXY - sumX * sumY;
    double den = MathSqrt((minCount * sumX2 - sumX * sumX) * (minCount * sumY2 - sumY * sumY));
    return (den != 0.0) ? num / den : 0.0;
}

//+------------------------------------------------------------------+
//| Get number of significant decimals                              |
//+------------------------------------------------------------------+
int GetSignificantDecimals(double val)
{
    string s = DoubleToString(val, 10);
    int dotPos = StringFind(s, ".");
    if(dotPos < 0) return 0;
    int len = StringLen(s) - dotPos - 1;
    while(len > 0 && StringGetCharacter(s, StringLen(s) - 1) == '0')
    {
        s   = StringSubstr(s, 0, StringLen(s) - 1);
        len--;
    }
    return len;
}

//+------------------------------------------------------------------+
//| Write Spread Report                                              |
//+------------------------------------------------------------------+
void WriteSpreadReport(const CArrayString &symbols, const string folderPath)
{
    string syms[];
    double spreads[];
    int total = symbols.Total();
    ArrayResize(syms, total);
    ArrayResize(spreads, total);

    // Collect spread information
    for(int i = 0; i < total; i++)
    {
        syms[i] = symbols.At(i);
        double bid, ask, point;
        if(!SymbolInfoDouble(syms[i], SYMBOL_BID, bid) ||
           !SymbolInfoDouble(syms[i], SYMBOL_ASK, ask) ||
           !SymbolInfoDouble(syms[i], SYMBOL_POINT, point))
        {
            Print("Failed to read spread info for ", syms[i]);
            spreads[i] = 0.0;
            continue;
        }
        double rawSpread = ask - bid;
        double spread    = rawSpread > 0.0 ? rawSpread : point;  // avoid zero
        spreads[i]       = (spread / bid) * 100.0;                // percent of bid
    }

    // Sort spreads in ascending order
    int n = ArraySize(syms);
    for(int i = 0; i < n - 1; i++)
        for(int j = 0; j < n - i - 1; j++)
            if(spreads[j] > spreads[j + 1])
            {
                double tmpD = spreads[j]; spreads[j] = spreads[j + 1]; spreads[j + 1] = tmpD;
                string tmpS = syms[j];    syms[j] = syms[j + 1];       syms[j + 1] = tmpS;
            }

    // Write to CSV
    int handle = FileOpen(folderPath + FilePrefix + "Spread.csv", FILE_WRITE | FILE_ANSI | FILE_CSV | FILE_TXT);
    if(handle < 0)
    {
        Print("Failed opening file: ", folderPath + FilePrefix + "Spread.csv");
        return;
    }
    FileWriteString(handle, "Symbol,SpreadPercent (%)\r\n");
    for(int i = 0; i < n; i++)
    {
        int decs = GetSignificantDecimals(spreads[i]);
        if(decs < 1) decs = 1;
        FileWriteString(handle, syms[i] + "," + DoubleToString(spreads[i], decs) + "\r\n");
    }
    FileClose(handle);
    Print("Spread report written to ", folderPath + FilePrefix + "Spread.csv");
}

//+------------------------------------------------------------------+

// (Python helper script removed)

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                CorrelationMatrixEA.mq5 |
//|   Shows a live correlation matrix in a dialog window               |
//+------------------------------------------------------------------+
#property copyright "2024"
#property version   "1.00"
#property strict
#property script_show_inputs

#include <Arrays/ArrayString.mqh>

#import "user32.dll"
int MessageBoxW(int hWnd,string text,string caption,int type);
#import

// use built in alignment constants like ALIGN_LEFT and ALIGN_CENTER

// basic color definitions
#define clrDarkSlateGray C'47,79,79'
#define clrGray          C'128,128,128'
#define clrLime          C'0,255,0'
#define clrTomato        C'255,99,71'
#define clrSilver        C'192,192,192'

// Removed dialog window and label grid from chart display
CArrayString symbols;                // list of symbols to display
input int   RefreshSeconds = 60;     // update interval
input bool  ShowPopup      = true;   // show popup window

// Restrict selectable timeframes to commonly used periods
enum CorrelPeriod
  {
   TF_M5   = PERIOD_M5,
   TF_M15  = PERIOD_M15,
   TF_M30  = PERIOD_M30,
   TF_H1   = PERIOD_H1,
   TF_H4   = PERIOD_H4,
   TF_D1   = PERIOD_D1,
   TF_W1   = PERIOD_W1,
   TF_MN1  = PERIOD_MN1
  };

input CorrelPeriod CalcPeriod = TF_M5; // timeframe for correlations

// width of each cell in the ASCII table
#define CELL_WIDTH 8

int rows, cols;                      // matrix dimensions
datetime nextUpdate = 0;    // time for the next matrix update

//+------------------------------------------------------------------+
int OnInit()
  {
   GetWatchlistSymbols(symbols);
   rows = symbols.Total();
   cols = rows;
   if(rows==0)
     {
      Print("No symbols in Market Watch.");
      return(INIT_FAILED);
     }

   // old chart-based dialog removed
   nextUpdate = TimeCurrent()+RefreshSeconds;
   if(ShowPopup)
      ShowPopup();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // nothing to clean up since dialog is removed
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   // no dialog events to handle
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(TimeCurrent()>=nextUpdate)
     {
      if(ShowPopup)
         ShowPopup();
      nextUpdate = TimeCurrent()+RefreshSeconds;
     }
  }


//+------------------------------------------------------------------+
int GetWatchlistSymbols(CArrayString &list)
  {
   int total=SymbolsTotal(true);
   for(int i=0;i<total;i++)
      list.Add(SymbolName(i,true));
   return total;
  }

//+------------------------------------------------------------------+
double CalculateCorrelation(const string a,const string b)
  {
   datetime end=TimeCurrent();
   const int bars=30;
   datetime start=end-PeriodSeconds((ENUM_TIMEFRAMES)CalcPeriod)*bars;
   MqlRates ra[], rb[];
   int na=CopyRates(a,(ENUM_TIMEFRAMES)CalcPeriod,start,end,ra);
   int nb=CopyRates(b,(ENUM_TIMEFRAMES)CalcPeriod,start,end,rb);
   int n=MathMin(na,nb);
   if(n<2) return 0.0;
   int use=MathMin(n,bars);
   double sx=0,sy=0,sx2=0,sy2=0,sxy=0;
   for(int i=0;i<use;i++)
     {
      double x=ra[i].close;
      double y=rb[i].close;
      sx+=x; sy+=y; sx2+=x*x; sy2+=y*y; sxy+=x*y;
     }
   double num=use*sxy-sx*sy;
  double den=MathSqrt((use*sx2-sx*sx)*(use*sy2-sy*sy));
  return(den!=0.0)?num/den:0.0;
 }

//+------------------------------------------------------------------+
//| Repeat a substring multiple times                                 |
//+------------------------------------------------------------------+
string Repeat(string s,int n)
  {
   string r="";
   for(int i=0;i<n;i++)
      r+=s;
   return r;
  }

//+------------------------------------------------------------------+
//| Pad string with spaces                                           |
//+------------------------------------------------------------------+
string Pad(string s,int width)
  {
   while(StringLen(s)<width)
      s+=" ";
   return s;
  }

// Pad string on the left with spaces
string PadLeft(string s,int width)
  {
   while(StringLen(s)<width)
      s=" "+s;
   return s;
  }

//+------------------------------------------------------------------+
//| Build a simple ASCII table of correlations                         |
//+------------------------------------------------------------------+
string HorizontalLine()
  {
   string line="+";
   line+=Repeat("-",CELL_WIDTH)+"+";
   for(int c=0;c<cols;c++)
      line+=Repeat("-",CELL_WIDTH)+"+";
   return line;
  }

string BuildMatrixText()
  {
   string txt=HorizontalLine()+"\n";
  txt+="|"+Pad("",CELL_WIDTH)+"|";
  for(int c=0;c<cols;c++)
     txt+=Pad(symbols.At(c),CELL_WIDTH)+"|";
  txt+="\n"+HorizontalLine()+"\n";
  for(int r=0;r<rows;r++)
    {
     txt+="|"+Pad(symbols.At(r),CELL_WIDTH)+"|";
     for(int c=0;c<cols;c++)
        txt+=PadLeft(StringFormat("%0.2f",(r==c)?1.0:CalculateCorrelation(symbols.At(r),symbols.At(c))),CELL_WIDTH)+"|";
     txt+="\n"+HorizontalLine()+"\n";
    }
  return txt;
 }

//+------------------------------------------------------------------+
//| Show matrix in a message box                                      |
//+------------------------------------------------------------------+
void ShowPopup()
  {
   string msg=BuildMatrixText();
   MessageBoxW(0,msg,"Correlation Matrix",0);
  }

//+------------------------------------------------------------------+

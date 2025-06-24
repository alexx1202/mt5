//+------------------------------------------------------------------+
//|                                                CorrelationMatrixEA.mq5 |
//|   Shows a live correlation matrix in a dialog window               |
//+------------------------------------------------------------------+
#property copyright "2024"
#property version   "1.00"
#property strict
#property script_show_inputs

#include <Arrays/ArrayString.mqh>
#include <Controls/Dialog.mqh>
#include <Controls/Label.mqh>

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

CAppDialog  dlg;                     // main dialog window
CArrayObj   labelGrid;               // holds label objects
CArrayString symbols;                // list of symbols to display
input int   RefreshSeconds = 60;     // update interval
input bool  ShowPopup      = true;   // show popup window

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

   // create dialog window (chart id=0 means current chart, subwindow=0)
   dlg.Create(0, "Correlation Matrix", 0, 0, 0, 500, 20+20*rows);
   CreateGrid();
   dlg.Run();
   nextUpdate = TimeCurrent()+RefreshSeconds;
   UpdateMatrix();
   if(ShowPopup)
      ShowPopup();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   dlg.Destroy(reason);
   labelGrid.Clear();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   dlg.OnEvent(id,lparam,dparam,sparam);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(TimeCurrent()>=nextUpdate)
     {
      UpdateMatrix();
      nextUpdate = TimeCurrent()+RefreshSeconds;
     }
  }

//+------------------------------------------------------------------+
void CreateGrid()
  {
   labelGrid.Clear();
   int left=10, top=10;
   int cellW=80, cellH=20;
   for(int r=0; r<rows+1; r++)
     {
      for(int c=0; c<cols+1; c++)
        {
         CLabel *lab=new CLabel;
         labelGrid.Add(lab);
         // create label as a child of the dialog
         lab.Create(0, "", 0, left+c*cellW, top+r*cellH, cellW, cellH);
         dlg.Add(lab);
         // set label appearance
         // center the label text and set basic colors
         // center the label text and use a neutral background
         // Align the label text in the center; zero offsets keep it stationary
         lab.Alignment(ALIGN_CENTER,0,0,0,0);
         lab.Color(clrWhite);
         lab.ColorBackground((r==0||c==0)?clrDarkSlateGray:clrGray);
         if(r==0 && c>0) lab.Text(symbols.At(c-1));
         if(c==0 && r>0) lab.Text(symbols.At(r-1));
       }
     }
  }

//+------------------------------------------------------------------+
void UpdateMatrix()
  {
   int idx=0;
   for(int r=0; r<rows; r++)
     {
      for(int c=0; c<cols; c++)
        {
         idx = (r+1)*(cols+1)+(c+1);
         CLabel *lab=(CLabel*)labelGrid.At(idx);
         double corr = (r==c)?1.0:CalculateCorrelation(symbols.At(r), symbols.At(c));
         string txt=DoubleToString(corr,2);
         lab.Text(txt);
         if(corr>0.8)        // strong positive correlation
            lab.ColorBackground(clrLime);
         else if(corr<-0.8) // strong negative correlation
            lab.ColorBackground(clrTomato);
         else               // weak correlation
            lab.ColorBackground(clrSilver);
        }
     }
   ChartRedraw(0);
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
   datetime start=end-PeriodSeconds(PERIOD_M1)*bars;
   MqlRates ra[], rb[];
   int na=CopyRates(a,PERIOD_M1,start,end,ra);
   int nb=CopyRates(b,PERIOD_M1,start,end,rb);
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
//| Create tab separated string of matrix values                      |
//+------------------------------------------------------------------+
string BuildMatrixText()
  {
   string txt="\t";
   for(int c=0;c<cols;c++)
      txt+=symbols.At(c)+"\t";
   txt+="\n";
   for(int r=0;r<rows;r++)
     {
      txt+=symbols.At(r)+"\t";
      for(int c=0;c<cols;c++)
        txt+=DoubleToString((r==c)?1.0:CalculateCorrelation(symbols.At(r),symbols.At(c)),2)+"\t";
      txt+="\n";
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

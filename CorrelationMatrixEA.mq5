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

CAppDialog  dlg;                     // main dialog window
CArrayObj   labelGrid;               // holds label objects
CArrayString symbols;                // list of symbols to display
input int   RefreshSeconds = 60;     // update interval

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
   dlg.Run();
   CreateGrid();
   nextUpdate = TimeCurrent()+RefreshSeconds;
   UpdateMatrix();
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
         lab->Create(0, "", 0, left+c*cellW, top+r*cellH, cellW, cellH);
         dlg.Add(lab);
         lab->TextAlign(ALIGN_CENTER);
         lab->Color(clrWhite);
         lab->BackColor((r==0||c==0)?clrDarkSlateGray:clrGray);
         if(r==0 && c>0) lab->Text(symbols.At(c-1));
         if(c==0 && r>0) lab->Text(symbols.At(r-1));
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
         lab->Text(txt);
         if(corr>0.8) lab->BackColor(clrLime);
         else if(corr<-0.8) lab->BackColor(clrTomato);
         else lab->BackColor(clrSilver);
        }
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

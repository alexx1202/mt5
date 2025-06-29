//+------------------------------------------------------------------+
//|                                                    ScannerEA.mq5 |
//|   Shows a live correlation matrix in a scrollable HTML table       |
//+------------------------------------------------------------------+
#property copyright "2024"
#property version   "1.00"
#property strict
#property script_show_inputs

#include <Arrays/ArrayString.mqh>

#import "shell32.dll"
int ShellExecuteW(int hwnd,string lpOperation,string lpFile,string lpParameters,string lpDirectory,int nShowCmd);
#import
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

// names and values for available timeframes
string TFNames[] = {"M5","M15","M30","H1","H4","D1","W1","MN1"};
int    TFValues[] = {PERIOD_M5,PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H4,PERIOD_D1,PERIOD_W1,PERIOD_MN1};

// locate index of a timeframe value in the TFValues array
int FindTFIndex(int tf)
  {
   for(int i=0;i<ArraySize(TFValues);i++)
      if(TFValues[i]==tf)
         return i;
   return 0;
  }


// width of each cell in the ASCII table
#define CELL_WIDTH 8

int rows, cols;                      // matrix dimensions
datetime nextUpdate = 0;    // time for the next matrix update
bool     pageOpened = false;         // track if browser already opened

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
double CalculateCorrelation(const string a,const string b,ENUM_TIMEFRAMES tf)
  {
   datetime end=TimeCurrent();
   const int bars=30;
   datetime start=end-PeriodSeconds(tf)*bars;
   MqlRates ra[], rb[];
   int na=CopyRates(a,tf,start,end,ra);
   int nb=CopyRates(b,tf,start,end,rb);
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

string BuildMatrixText(ENUM_TIMEFRAMES tf)
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
        txt+=PadLeft(StringFormat("%0.2f",(r==c)?1.0:CalculateCorrelation(symbols.At(r),symbols.At(c),tf)),CELL_WIDTH)+"|";
      txt+="\n"+HorizontalLine()+"\n";
     }
   return txt;
  }

//+------------------------------------------------------------------+
//| Build a correlation table for a single timeframe                  |
//+------------------------------------------------------------------+
string BuildMatrixTable(ENUM_TIMEFRAMES tf)
  {
   string html="<table><thead>";
   html+=StringFormat("<tr class='tf-row'><th colspan='%d'>",cols+1);
   for(int i=0;i<ArraySize(TFValues);i++)
     {
      html+=StringFormat("<button onclick=\"showTF('%s')\">%s</button>",TFNames[i],TFNames[i]);
      if(i<ArraySize(TFValues)-1) html+="&nbsp;";
     }
   html+="</th></tr>";
   html+="<tr class='head-row'><th></th>";
   for(int c=0;c<cols;c++)
      html+=StringFormat("<th>%s</th>",symbols.At(c));
   html+="</tr></thead><tbody>";
   for(int r=0;r<rows;r++)
     {
      html+=StringFormat("<tr><th class='sym'>%s</th>",symbols.At(r));
      for(int c=0;c<cols;c++)
        {
         double val=(r==c)?1.0:CalculateCorrelation(symbols.At(r),symbols.At(c),tf);
         string col=(val>=0)?"green":"red";
         html+=StringFormat("<td style='color:%s'>%0.2f</td>",col,val);
        }
      html+="</tr>";
     }
   html+="</tbody></table>";
   return html;
  }

//+------------------------------------------------------------------+
//| Build the HTML page with all timeframe tables                     |
//+------------------------------------------------------------------+
string BuildMatrixHtml(int defaultIndex)
  {
   string html="<html><head><meta charset='UTF-8'>";
   html+=StringFormat("<meta http-equiv='refresh' content='%d'>",RefreshSeconds);
   html+="<style>";
   html+="body{font-family:monospace;background:black;color:white;margin:0;}";
  // Removed extra top scroll bar to free up space
  html+="div.table-container{overflow:auto;height:100vh;}";
  html+="table{border-collapse:collapse;}";
  html+="th,td{border:1px solid white;padding:4px;text-align:right;color:white;}";
  html+="th:first-child{text-align:left;}";
  html+="th:first-child,td:first-child{position:sticky;left:0;background:black;z-index:2;}";
  // Shift timeframe and header rows up since there is no top scroll bar
  html+="tr.tf-row th{position:sticky;top:0;text-align:left;background:black;z-index:2;}";
  html+="tr.head-row th{position:sticky;top:2em;background:black;z-index:1;}";
   html+="</style>";
   html+="<script>function showTF(tf){var tfs=['";
   for(int i=0;i<ArraySize(TFNames);i++)
     {
      if(i>0) html+="','";
      html+=TFNames[i];
     }
   html+="'];for(var i=0;i<tfs.length;i++){var e=document.getElementById('tf_'+tfs[i]);if(e) e.style.display=(tfs[i]==tf)?'block':'none';}location.hash=tf;}window.onload=function(){var h=location.hash.substring(1);if(h=='')h='"+TFNames[defaultIndex]+"';showTF(h);};</script>";
   html+="</head><body><div id='table-container' class='table-container'>";
   for(int i=0;i<ArraySize(TFValues);i++)
     {
      html+=StringFormat("<div id='tf_%s' style='display:none;'>",TFNames[i]);
      html+=BuildMatrixTable((ENUM_TIMEFRAMES)TFValues[i]);
      html+="</div>";
     }
   html+="</div></body></html>";
   return html;
  }

//+------------------------------------------------------------------+
//| Build HTML table for spread percentages                           |
//+------------------------------------------------------------------+
string BuildSpreadHtml()
  {
   int total=symbols.Total();
   string syms[];
   double spreads[];
   ArrayResize(syms,total);
   ArrayResize(spreads,total);
   for(int i=0;i<total;i++)
     {
      syms[i]=symbols.At(i);
      double bid,ask,point;
      if(!SymbolInfoDouble(syms[i],SYMBOL_BID,bid) ||
         !SymbolInfoDouble(syms[i],SYMBOL_ASK,ask) ||
         !SymbolInfoDouble(syms[i],SYMBOL_POINT,point))
        {
         spreads[i]=0.0;
         continue;
        }
      double raw=ask-bid;
      double sprd=(raw>0)?raw:point;
      spreads[i]=(sprd/bid)*100.0;
     }

   for(int i=0;i<total-1;i++)
      for(int j=0;j<total-1-i;j++)
         if(spreads[j]>spreads[j+1])
           {
            double td=spreads[j]; spreads[j]=spreads[j+1]; spreads[j+1]=td;
            string ts=syms[j];    syms[j]=syms[j+1];    syms[j+1]=ts;
           }

   string html="<html><head><meta charset='UTF-8'>";
   html+=StringFormat("<meta http-equiv='refresh' content='%d'>",RefreshSeconds);
   html+="<style>";
   html+="body{font-family:monospace;background:black;color:white;}";
   html+="div.table-container{overflow-x:auto;}";
   html+="table{border-collapse:collapse;}";
   html+="th,td{border:1px solid white;padding:4px;text-align:right;color:white;}";
   html+="th:first-child{text-align:left;}";
   html+="</style></head><body><div class='table-container'><table>";
   html+="<tr><th>Symbol</th><th>Spread %</th></tr>";
   for(int i=0;i<total;i++)
     html+=StringFormat("<tr><td>%s</td><td>%0.10f</td></tr>",syms[i],spreads[i]);
   html+="</table></div></body></html>";
   return html;
  }

//+------------------------------------------------------------------+
//| Build HTML table for swap information                             |
//+------------------------------------------------------------------+
string BuildSwapHtml()
  {
   int total=symbols.Total();
   string html="<html><head><meta charset='UTF-8'>";
   html+=StringFormat("<meta http-equiv='refresh' content='%d'>",RefreshSeconds);
   html+="<style>";
   html+="body{font-family:monospace;background:black;color:white;}";
   html+="div.table-container{overflow-x:auto;}";
   html+="table{border-collapse:collapse;}";
   html+="th,td{border:1px solid white;padding:4px;text-align:right;color:white;}";
   html+="th:first-child{text-align:left;}";
   html+="</style></head><body><div class='table-container'><table>";
   html+="<tr><th>Symbol</th><th>Swap Long</th><th>Swap Short</th></tr>";
   for(int i=0;i<total;i++)
     {
      string sym=symbols.At(i);
      double swapLong,swapShort;
      if(!SymbolInfoDouble(sym,SYMBOL_SWAP_LONG,swapLong) ||
         !SymbolInfoDouble(sym,SYMBOL_SWAP_SHORT,swapShort))
        { swapLong=0.0; swapShort=0.0; }

      string colLong  = (swapLong<0)?"red":"green";
      string colShort = (swapShort<0)?"red":"green";
      html+=StringFormat("<tr><td>%s</td><td style='color:%s'>%0.2f</td>"
                        "<td style='color:%s'>%0.2f</td></tr>",
                        sym,colLong,swapLong,colShort,swapShort);
    }
   html+="</table></div></body></html>";
  return html;
 }

//+------------------------------------------------------------------+
//| Build a combined HTML page showing spread and swap tables side by |
//| side. This keeps the existing table styles but places them in a   |
//| single page using a flex container so they appear next to each    |
//| other.                                                            |
//+------------------------------------------------------------------+
string BuildSpreadSwapHtml()
  {
  // Determine which timeframe should be shown by default
  int defaultIndex = FindTFIndex(PERIOD_M5);
   int total = symbols.Total();
   string syms[];
   double spreads[];
   ArrayResize(syms,total);
   ArrayResize(spreads,total);

   // Collect spread information
   for(int i=0;i<total;i++)
     {
      syms[i]=symbols.At(i);
      double bid,ask,point;
      if(!SymbolInfoDouble(syms[i],SYMBOL_BID,bid) ||
         !SymbolInfoDouble(syms[i],SYMBOL_ASK,ask) ||
         !SymbolInfoDouble(syms[i],SYMBOL_POINT,point))
        {
         spreads[i]=0.0;
         continue;
        }
      double raw=ask-bid;
      double sprd=(raw>0)?raw:point;
      spreads[i]=(sprd/bid)*100.0;
     }

   // Sort spreads ascending to match previous behaviour
   for(int i=0;i<total-1;i++)
      for(int j=0;j<total-1-i;j++)
         if(spreads[j]>spreads[j+1])
           {
            double td=spreads[j]; spreads[j]=spreads[j+1]; spreads[j+1]=td;
            string ts=syms[j];    syms[j]=syms[j+1];    syms[j+1]=ts;
           }

   // Build the HTML page
   string html="<html><head><meta charset='UTF-8'>";
   html+=StringFormat("<meta http-equiv='refresh' content='%d'>",RefreshSeconds);
   html+="<style>";
   html+="body{font-family:monospace;background:black;color:white;margin:0;}";
  html+="div.wrapper{display:flex;gap:20px;flex-wrap:wrap;}";
  html+="div.table-container{overflow-x:auto;}";
  html+="table{border-collapse:collapse;}";
  html+="th,td{border:1px solid white;padding:4px;text-align:right;color:white;}";
  html+="th:first-child{text-align:left;}";
   html+="</style></head><body><div class='wrapper'>";

   // Spread table
   html+="<div class='table-container'><table>";
   html+="<tr><th>Symbol</th><th>Spread %</th></tr>";
   for(int i=0;i<total;i++)
      html+=StringFormat("<tr><td>%s</td><td>%0.10f</td></tr>",syms[i],spreads[i]);
   html+="</table></div>";

   // Swap table
   html+="<div class='table-container'><table>";
   html+="<tr><th>Symbol</th><th>Swap Long</th><th>Swap Short</th></tr>";
   for(int i=0;i<total;i++)
     {
      string sym=symbols.At(i);
      double swapLong,swapShort;
      if(!SymbolInfoDouble(sym,SYMBOL_SWAP_LONG,swapLong) ||
         !SymbolInfoDouble(sym,SYMBOL_SWAP_SHORT,swapShort))
        { swapLong=0.0; swapShort=0.0; }

      string colLong  = (swapLong<0)?"red":"green";
      string colShort = (swapShort<0)?"red":"green";
      html+=StringFormat("<tr><td>%s</td><td style='color:%s'>%0.2f</td><td style='color:%s'>%0.2f</td></tr>",
                        sym,colLong,swapLong,colShort,swapShort);
     }
  html+="</table></div>";
  html+="<div class='table-container'><table id='ps_result'><tr><th colspan='2'>Last Calculation</th></tr></table>";
  html+="<button id='ps_download' onclick='downloadFiles()' style='display:none;margin-top:4px;'>Download Files</button>";
  html+="<button id='ps_copy_webhook' onclick='copyWebhook()' style='display:none;margin-top:4px;'>Copy Webhook</button>";
  html+="<button id='ps_copy_json' onclick='copyJson()' style='display:none;margin-top:4px;'>Copy JSON</button></div>";

  // Position size calculator table
  string opts="";
  for(int i=0;i<total;i++)
     opts+=StringFormat("<option value='%s'>%s</option>",symbols.At(i),symbols.At(i));

  double accBal=AccountInfoDouble(ACCOUNT_BALANCE);
  double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
  string symInfo="var symbolInfo={";
  for(int i=0;i<total;i++)
    {
     string s=symbols.At(i);
     double price=SymbolInfoDouble(s,SYMBOL_ASK);
     int digits=(int)SymbolInfoInteger(s,SYMBOL_DIGITS);
     double pt=SymbolInfoDouble(s,SYMBOL_POINT);
     double tv=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_VALUE);
     double ts=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE);
     double cs=SymbolInfoDouble(s,SYMBOL_TRADE_CONTRACT_SIZE);
     symInfo+=StringFormat("'%s':{p:%f,d:%d,pt:%f,tv:%f,ts:%f,cs:%f},",s,price,digits,pt,tv,ts,cs);
    }
  if(StringLen(symInfo)>13)
     StringSetCharacter(symInfo,StringLen(symInfo)-1,'}');
  else
     symInfo+="}";
  symInfo+=";";

  html+="<div class='table-container'><table id='ps_form'>";
  html+="<tr><th colspan='2'>Position Size Calc";
  html+="</th></tr>";
  html+="<tr><td>Symbol</td><td><select id='ps_symbol'>"+opts+"</select></td></tr>";
  html+="<tr><td>Risk Mode</td><td><select id='risk_mode' onchange='updateVis()'><option value='pct'>Risk %</option><option value='aud'>Fixed AUD</option></select></td></tr>";
  html+="<tr id='tr_fixed_risk'><td>Fixed Risk AUD</td><td><input id='fixed_risk' type='number' value='100'/></td></tr>";
  html+="<tr id='tr_risk_pct'><td>Risk %</td><td><input id='risk_pct' type='number' value='1'/></td></tr>";
  html+="<tr><td>SL Unit</td><td><select id='sl_unit'><option value='pips'>Pips</option><option value='points'>Points</option></select></td></tr>";
  html+="<tr><td>SL Value</td><td><input id='sl_value' type='number' value='20'/></td></tr>";
  html+="<tr><td>Broker</td><td><select id='broker_mode' onchange='updateVis()'><option value='pepper'>Pepperstone</option><option value='oanda'>OANDA</option></select></td></tr>";
  html+="<tr><td>RR Ratio</td><td><input id='rr_ratio' type='number' value='2'/></td></tr>";
  html+="<tr><td>Side</td><td><select id='order_side'><option value='buy'>Buy</option><option value='sell'>Sell</option></select></td></tr>";
  html+="<tr id='tr_oanda_balance'><td>OANDA Balance</td><td><input id='oanda_balance' type='number' value='0'/></td></tr>";
  html+="<tr id='tr_commission'><td>Commission/Lot</td><td><input id='commission' type='number' value='7'/></td></tr>";
  html+="<tr><td>Volume Step</td><td><input id='volume_step' type='number' value='0.01' step='0.00001'/></td></tr>";
  html+="<tr><td>Min Net Profit</td><td><input id='min_net' type='number' value='20'/></td></tr>";
  html+="<tr><td colspan='2' style='text-align:center;'><button onclick='calcPosition()'>Calculate</button></td></tr>";
  html+="</table></div>";

  html+="</div><script>"+symInfo+
  "function el(id){return document.getElementById(id);}"+
  "var accBal="+DoubleToString(accBal,2)+";var freeMarg="+DoubleToString(freeMargin,2)+";"+
  "function saveInputs(){var o={symbol:el('ps_symbol').value,risk_mode:el('risk_mode').value,fixed_risk:el('fixed_risk').value,risk_pct:el('risk_pct').value,sl_unit:el('sl_unit').value,sl_value:el('sl_value').value,broker_mode:el('broker_mode').value,rr_ratio:el('rr_ratio').value,order_side:el('order_side').value,oanda_balance:el('oanda_balance').value,commission:el('commission').value,volume_step:el('volume_step').value,min_net:el('min_net').value};localStorage.setItem('ps_inputs',JSON.stringify(o));}"+
  "function loadInputs(){var j=localStorage.getItem('ps_inputs');if(!j)return;try{var o=JSON.parse(j);for(var k in o){var e=el(k);if(e)e.value=o[k];}}catch(e){}}"+
  "function getLev(sym){sym=sym.toUpperCase();if(sym.includes('USD')&&(sym.includes('EUR')||sym.includes('GBP')||sym.includes('AUD')||sym.includes('NZD')||sym.includes('CAD')||sym.includes('CHF')||sym.includes('JPY')))return 30;if(sym.length==6||sym.length==7)return 20;if(sym.includes('XAU')||sym.includes('US500')||sym.includes('NAS')||sym.includes('UK')||sym.includes('GER'))return 20;if(sym.includes('XAG')||sym.includes('WTI')||sym.includes('BRENT'))return 10;if(sym.includes('BTC')||sym.includes('ETH')||sym.includes('LTC')||sym.includes('XRP'))return 2;return 5;}"+
  "function dl(name,text){var b=new Blob([text]);var a=document.createElement('a');a.href=URL.createObjectURL(b);a.download=name;a.click();URL.revokeObjectURL(a.href);}"+
  "function copyWebhook(){var url='https://app.signalstack.com/hook/kiwPq16apN3xpy5eMPDovH';navigator.clipboard.writeText(url);}"+
  "function copyJson(){if(lastJson)navigator.clipboard.writeText(lastJson);}"+
  "var lastTxt='';var lastJson='';"+
  "function updateVis(){var b=el('broker_mode').value;el('tr_oanda_balance').style.display=(b=='oanda')?'table-row':'none';el('tr_commission').style.display=(b=='pepper')?'table-row':'none';el('ps_copy_webhook').style.display=(b=='oanda')?'inline':'none';el('ps_copy_json').style.display=(b=='oanda')?'inline':'none';var m=el('risk_mode').value;el('tr_fixed_risk').style.display=(m=='aud')?'table-row':'none';el('tr_risk_pct').style.display=(m=='pct')?'table-row':'none';}"+
  "function downloadFiles(){var t=localStorage.getItem('ps_last_txt');if(!t)return;var ts=new Date().toISOString().replace(/[:T]/g,'-').split('.')[0];dl('PositionSizeOutput-'+ts+'.txt',t);}"+
  "function calcPosition(){var s=el('ps_symbol').value;var inf=symbolInfo[s];var price=inf.p;var digits=inf.d;"+
  "var pipSize=Math.pow(10,-digits+1);var pipVal=inf.tv*pipSize/inf.ts;"+
  "var slUnit=el('sl_unit').value;var slVal=parseFloat(el('sl_value').value);"+
  "var slPips=(slUnit=='pips')?slVal:slVal*inf.pt/pipSize;var bro=el('broker_mode').value;"+
  "var volStep=parseFloat(el('volume_step').value);var comm=parseFloat(el('commission').value);"+
  "if(bro=='oanda'){if(comm==7)comm=0;volStep=0.00001;}else{volStep=0.01;}"+
  "var bal=accBal;if(bro=='oanda'){var ob=parseFloat(el('oanda_balance').value);if(ob>0)bal=ob;}"+
  "var riskMode=el('risk_mode').value;var riskAmt=(riskMode=='aud')?parseFloat(el('fixed_risk').value):bal*parseFloat(el('risk_pct').value)/100;"+
  "if(riskAmt<=0)return;var lotRaw=riskAmt/(slPips*pipVal+comm);"+
  "var lot=Math.ceil(lotRaw/volStep)*volStep;var lotPrec=Math.round(Math.log10(1/volStep));lot=parseFloat(lot.toFixed(lotPrec));"+
  "var commiss=lot*comm;var rr=parseFloat(el('rr_ratio').value);var tpP=slPips*rr;var netReward=tpP*pipVal*lot-commiss;"+
  "var minNet=parseFloat(el('min_net').value);var reqProfit=Math.max(riskAmt*rr,minNet);"+
  "while(netReward<reqProfit){tpP+=0.5;netReward=tpP*pipVal*lot-commiss;}"+
  "var side=el('order_side').value;var buy=side=='buy';"+
  "var slPrice=buy?price-slPips*pipSize:price+slPips*pipSize;var tpPrice=buy?price+tpP*pipSize:price-tpP*pipSize;"+
  "var netRisk=slPips*pipVal*lot+commiss;var slDisp=slVal+' '+(slUnit=='pips'?'pips':'points');"+
  "var tpVal=(slUnit=='pips')?tpP:tpP*(pipSize/inf.pt);var tpDisp=tpVal.toFixed(1)+' '+(slUnit=='pips'?'pips':'points');"+
  "var isFx=s.length>=6&&s.length<=7&&!/[0-9]/.test(s);"+
  "var out='=== Position Size Calculation ===\\n';out+='Symbol: '+s+'\\n';out+='Trade Side: '+(buy?'Buy':'Sell')+'\\n';"+
  "out+='Account Balance: AUD'+bal.toFixed(2)+'\\n';out+='Risk Amount: AUD'+riskAmt.toFixed(2)+'\\n';"+
  "out+='Lot Size: '+lot.toFixed(lotPrec)+'\\n';out+='Commission: AUD'+commiss.toFixed(2)+'\\n';"+
  "out+='Net Risk: AUD'+netRisk.toFixed(2)+'\\n';"+
  "out+='Stop Loss: '+slDisp+'\\n';"+
  "out+='Take Profit: '+tpDisp+' (RR=1:'+rr.toFixed(2)+')\\n';"+
  "out+='Expected Net Profit at TP: AUD'+netReward.toFixed(2)+'\\n';out+='Minimum Net Profit Target: AUD'+minNet.toFixed(2)+'\\n';"+
  "var lev=getLev(s);var contract=inf.cs;var notion=lot*contract*price;var margin=notion/lev;"+
  "out+='Margin Needed: '+margin.toFixed(2)+'\\n';"+
  "lastTxt=out;lastJson='';"+
  "if(bro=='oanda'){var qty=Math.round(lot*100000);lastJson='{\\n \"symbol\": \"{{ticker}}\",\\n \"action\": \"'+(buy?'buy':'sell')+'\",\\n \"quantity\": '+qty+',\\n \"take_profit_price\": \"{{close}} '+(buy?'+':'-')+' '+(tpP*pipSize).toFixed(3)+'\",\\n \"stop_loss_price\": \"{{close}} '+(buy?'-':'+')+' '+(slPips*pipSize).toFixed(3)+'\"\\n}';}"+
  "localStorage.setItem('ps_last_txt',lastTxt);localStorage.setItem('ps_last_json',lastJson);el('ps_download').style.display='inline';"+
  "var r='<tr><th colspan=\"2\">Last Calculation</th></tr>';"+
  "r+='<tr><td>Lot Size</td><td>'+lot.toFixed(lotPrec)+'</td></tr>';"+
  "r+='<tr><td>Stop Loss</td><td>'+slDisp+'</td></tr>';"+
  "r+='<tr><td>Take Profit</td><td>'+tpDisp+'</td></tr>';"+
  "r+='<tr><td>Margin</td><td>'+margin.toFixed(2)+'</td></tr>';"+
  "r+='<tr><td>Net Risk</td><td>'+netRisk.toFixed(2)+'</td></tr>';"+
  "if(bro=='pepper')r+='<tr><td>Commission</td><td>'+commiss.toFixed(2)+'</td></tr>';"+
  "r+='<tr><td>Net Profit</td><td>'+netReward.toFixed(2)+'</td></tr>';"+
  "if(bro=='oanda'){el('ps_copy_webhook').style.display='inline';el('ps_copy_json').style.display='inline';}"+
  "document.getElementById('ps_result').innerHTML=r;localStorage.setItem('ps_result',r);saveInputs();updateVis();}"+
  "window.onload=function(){loadInputs();updateVis();var r=localStorage.getItem('ps_result');if(r)el('ps_result').innerHTML=r;if(localStorage.getItem('ps_last_txt'))el('ps_download').style.display='inline';var h=location.hash.substring(1);if(h=='')h='"+TFNames[defaultIndex]+"';showTF(h);var ins=document.querySelectorAll('#ps_form input,#ps_form select');for(var i=0;i<ins.length;i++)ins[i].addEventListener('change',function(){saveInputs();updateVis();});};"+
  "</script></body></html>";
  return html;
 }

//+------------------------------------------------------------------+
//| Generate an HTML table and open it in the default browser         |
//+------------------------------------------------------------------+
void ShowPopup()
  {
   // generate updated HTML content
   string combined_html = BuildSpreadSwapHtml();

   int defaultIndex = FindTFIndex(PERIOD_M5);

   string matrix_html = BuildMatrixHtml(defaultIndex);
   string matrixFile="CorrelationMatrix.html";
   int h = FileOpen(matrixFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h >= 0)
     { FileWriteString(h, matrix_html); FileClose(h); }

   string combinedFile="SpreadSwap.html";
   h = FileOpen(combinedFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h >= 0)
     { FileWriteString(h, combined_html); FileClose(h); }

   if(!pageOpened)
     {
      string base=TerminalInfoString(TERMINAL_DATA_PATH)+"\\MQL5\\Files\\";
      string fullMatrix=base+matrixFile;
      string fullCombined=base+combinedFile;

      string params=StringFormat("\"%s\" \"%s\"",
                                 fullMatrix,fullCombined);
      int res=ShellExecuteW(0,"open","msedge.exe",params,NULL,1);
      if(res>32)
         pageOpened=true;
      else
        MessageBoxW(0,BuildMatrixText(PERIOD_M5),"Correlation Matrix",0);
     }
  }

//+------------------------------------------------------------------+

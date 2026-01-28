//+------------------------------------------------------------------+
//|                                                  CamboSMCore.mq5 |
//|                                  Copyright 2026, Professional AI |
//|                                     Version 17.0 – Debug & Tools |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Professional AI"
#property link      "https://www.mql5.com"
#property version   "17.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

enum ENUM_SETUP_STATE { STATE_IDLE, STATE_WAIT_M5_BREAKOUT };

//--- INPUTS
input group "SOP Filters"
input int      InpMagicNumber        = 40000;    
input double   InpRiskPercent        = 0.5;      
input bool     InpOneTradePerDay     = true;     
input int      InpMinCandlesAbove    = 3;        

input group "Breakout Filters (Configurable)"
input bool     InpUseRSIFilter       = false;     // Enable/Disable RSI
input double   InpRSI_Overbought     = 80.0;     
input bool     InpUseADXFilter       = true;     // Enable/Disable ADX
input double   InpADX_MinTrend       = 20.0;     

input group "Trade Management"
input bool     InpEnableBE           = true;     
input double   InpBE_Trigger_USD     = 25.0;     
input double   InpBE_Profit_Lock_USD = 0.20;     
input bool     InpDisableBE_Asian    = true;     
input string   InpAsianStart         = "00:00";  
input string   InpAsianEnd           = "09:00";  

//--- GLOBALS
int hM15_E20, hM15_E50, hM15_E100, hM15_E200;
int hM5_RSI, hM5_ADX;
CTrade Trade; CPositionInfo Position; CSymbolInfo SymbolPtr; CAccountInfo Account;

datetime lastM15, lastM5;
ENUM_SETUP_STATE g_State = STATE_IDLE;
double   g_BreakoutLevel = 0;
string   g_DebugReason = "Waiting for M15 Setup";

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   if(!SymbolPtr.Name(_Symbol)) return INIT_FAILED;
   
   hM15_E20  = iMA(_Symbol, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
   hM15_E50  = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   hM15_E100 = iMA(_Symbol, PERIOD_M15, 100, 0, MODE_EMA, PRICE_CLOSE);
   hM15_E200 = iMA(_Symbol, PERIOD_M15, 200, 0, MODE_EMA, PRICE_CLOSE);
   hM5_RSI   = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
   hM5_ADX   = iADX(_Symbol, PERIOD_M5, 14);

   Trade.SetExpertMagicNumber(InpMagicNumber);
   return INIT_SUCCEEDED;
}

void OnTick() {
   UpdateDashboard();

   if(InpEnableBE) HandleBreakEven();

   if(PositionsTotal() > 0) return;
   if(InpOneTradePerDay && HasTradedToday()) {
      g_State = STATE_IDLE;
      g_DebugReason = "Daily Trade Limit Reached";
      return;
   }

   datetime m15Time = iTime(_Symbol, PERIOD_M15, 0);
   if(m15Time != lastM15) {
      lastM15 = m15Time;
      CheckM15Permission();
   }

   if(g_State == STATE_WAIT_M5_BREAKOUT) {
      MonitorM5Execution();
   }
}

//+------------------------------------------------------------------+
//| Step 2: M5 Execution with Debug Reason                           |
//+------------------------------------------------------------------+
void MonitorM5Execution() {
   double m5_c1 = iClose(_Symbol, PERIOD_M5, 1);
   
   // 1. Structural Check
   bool isBreakout = (m5_c1 > g_BreakoutLevel && m5_c1 > iHigh(_Symbol, PERIOD_M5, 2) && m5_c1 > iOpen(_Symbol, PERIOD_M5, 1));
   if(!isBreakout) {
      g_DebugReason = StringFormat("Waiting for M5 Close > %.2f", g_BreakoutLevel);
      return;
   }

   // 2. Filter Check
   double rsi[], adx[];
   CopyBuffer(hM5_RSI, 0, 0, 1, rsi);
   CopyBuffer(hM5_ADX, 0, 0, 1, adx);

   if(InpUseRSIFilter && rsi[0] >= InpRSI_Overbought) {
      g_DebugReason = StringFormat("BLOCKED: RSI Overbought (%.2f)", rsi[0]);
      return;
   }

   if(InpUseADXFilter && adx[0] < InpADX_MinTrend) {
      g_DebugReason = StringFormat("BLOCKED: Market in Range (ADX: %.2f)", adx[0]);
      return;
   }

   // 3. Execution
   ExecuteBuy(m5_c1);
   g_State = STATE_IDLE;
   g_DebugReason = "Trade Executed";
}

//+------------------------------------------------------------------+
//| Dashboard Display                                                |
//+------------------------------------------------------------------+
void UpdateDashboard() {
   double rsi_val[], adx_val[];
   CopyBuffer(hM5_RSI, 0, 0, 1, rsi_val);
   CopyBuffer(hM5_ADX, 0, 0, 1, adx_val);

   string text = "--- CAMBO SMC CORE DASHBOARD ---\n";
   text += "State: " + EnumToString(g_State) + "\n";
   text += "M5 RSI: " + DoubleToString(rsi_val[0], 2) + (InpUseRSIFilter ? " (Active)" : " (Off)") + "\n";
   text += "M5 ADX: " + DoubleToString(adx_val[0], 2) + (InpUseADXFilter ? " (Active)" : " (Off)") + "\n";
   text += "Target Breakout: " + DoubleToString(g_BreakoutLevel, 2) + "\n";
   text += "STATUS: " + g_DebugReason;

   Comment(text);
}

//+------------------------------------------------------------------+
//| Helpers (BE, Time, History)                                      |
//+------------------------------------------------------------------+
void HandleBreakEven() {
   if(InpDisableBE_Asian && IsAsianSession()) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(Position.SelectByIndex(i) && Position.Magic() == InpMagicNumber) {
         double entry = Position.PriceOpen();
         if(Position.StopLoss() < entry && (SymbolInfoDouble(_Symbol, SYMBOL_BID) - entry) >= InpBE_Trigger_USD) {
            Trade.PositionModify(Position.Ticket(), NormalizeDouble(entry + InpBE_Profit_Lock_USD, _Digits), Position.TakeProfit());
         }
      }
   }
}

bool IsAsianSession() {
   datetime now = TimeCurrent();
   datetime start = StringToTime(TimeToString(now, TIME_DATE) + " " + InpAsianStart);
   datetime end   = StringToTime(TimeToString(now, TIME_DATE) + " " + InpAsianEnd);
   return (end < start) ? (now >= start || now < end) : (now >= start && now <= end);
}

void CheckM15Permission() {
   double e20[], e50[], e100[], e200[];
   CopyBuffer(hM15_E20,0,0,4,e20); CopyBuffer(hM15_E50,0,0,4,e50);
   CopyBuffer(hM15_E100,0,0,4,e100); CopyBuffer(hM15_E200,0,0,4,e200);

   if(!(e20[0] > e50[0] && e50[0] > e100[0] && e100[0] > e200[0])) { 
      g_DebugReason = "EMAs not stacked"; 
      g_State = STATE_IDLE; 
      return; 
   }
   g_State = STATE_WAIT_M5_BREAKOUT;
   g_BreakoutLevel = iHigh(_Symbol, PERIOD_M15, 1) + 0.20;
}

void ExecuteBuy(double price) {
   double sl = price - 25.0; double tp = price + 45.0;
   Trade.Buy(0.10, _Symbol, SymbolPtr.Ask(), NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits));
}

bool HasTradedToday() {
   HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(t, DEAL_MAGIC) == InpMagicNumber && HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN) return true;
   }
   return false;
}

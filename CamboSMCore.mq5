//+------------------------------------------------------------------+
//|                                                  CamboSMCore.mq5 |
//|                                  Copyright 2026, Professional AI |
//|                                     Version 22.0 – Prop Guard    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Professional AI"
#property link      "https://www.mql5.com"
#property version   "22.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

enum ENUM_SETUP_STATE { STATE_IDLE, STATE_WAIT_M5_BREAKOUT };

//--- INPUTS
input group "🛡️ PROP FIRM RISK GUARDS"
input double InpMaxDailyLossPct      = 3.0;      // 3% daily loss lock
input double InpMaxTotalDDPct        = 8.0;      // 8% max drawdown lock
input bool   InpUseInitialBalanceDD  = true;     // baseline vs initial
input int    InpMaxTradesPerDay      = 1;        
input int    InpMaxTradesPerWeek     = 4;
input int    InpMaxOpenPositions     = 1;

input group "🧯 EXECUTION SAFETY"
input double InpMaxSpreadUSD         = 0.60;     // block if spread too high
input int    InpMaxSlippagePoints    = 30;       
input bool   InpBlockOnFridayNY      = true;     // avoid late Friday

input group "SOP Filters"
input int      InpMagicNumber        = 40168;    
input double   InpRiskPercent        = 0.5;      
input bool     InpOneTradePerDay     = true;     
input int      InpMinCandlesAbove    = 3;   

input group "Stops/Targets (Global Inputs)"
input double   InpFixedSL_Dist       = 25.0;     
input double   InpFixedTP_Dist       = 45.0;     
input double   InpEntryBuffer_USD    = 0.20;     

input group "Breakout Filters (Configurable)"
input bool     InpUseRSIFilter       = false;    
input double   InpRSI_Overbought     = 80.0;     
input bool     InpUseADXFilter       = true;     
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
double g_InitialBalance;
datetime lastM15;
ENUM_SETUP_STATE g_State = STATE_IDLE;
double   g_BreakoutLevel = 0;
string   g_DebugReason = "Waiting for M15 Setup";

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   if(!SymbolPtr.Name(_Symbol)) return INIT_FAILED;
   g_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   hM15_E20  = iMA(_Symbol, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
   hM15_E50  = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   hM15_E100 = iMA(_Symbol, PERIOD_M15, 100, 0, MODE_EMA, PRICE_CLOSE);
   hM15_E200 = iMA(_Symbol, PERIOD_M15, 200, 0, MODE_EMA, PRICE_CLOSE);
   hM5_RSI   = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
   hM5_ADX   = iADX(_Symbol, PERIOD_M5, 14);

   Trade.SetExpertMagicNumber(InpMagicNumber);
   Trade.SetDeviationInPoints(InpMaxSlippagePoints);
   return INIT_SUCCEEDED;
}

void OnTick() {
   UpdateDashboard();
   
   // Check Prop Firm Restrictions First
   if(IsRiskGuardTriggered()) return;

   if(InpEnableBE) HandleBreakEven();

   if(PositionsTotal() >= InpMaxOpenPositions) return;

   // Friday Safety
   if(InpBlockOnFridayNY && IsFridayLate()) {
      g_DebugReason = "Friday Safety Active";
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
//| Execution Checks                                                 |
//+------------------------------------------------------------------+
void MonitorM5Execution() {
   // Spread Check
   double currentSpread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(currentSpread > InpMaxSpreadUSD) {
      g_DebugReason = StringFormat("Spread Too High: %.2f", currentSpread);
      return;
   }

   double m5_c1 = iClose(_Symbol, PERIOD_M5, 1);
   bool isBreakout = (m5_c1 > g_BreakoutLevel && m5_c1 > iHigh(_Symbol, PERIOD_M5, 2) && m5_c1 > iOpen(_Symbol, PERIOD_M5, 1));
   
   if(!isBreakout) {
      g_DebugReason = StringFormat("Waiting for M5 Close > %.2f", g_BreakoutLevel);
      return;
   }

   double rsi[], adx[];
   CopyBuffer(hM5_RSI, 0, 0, 1, rsi);
   CopyBuffer(hM5_ADX, 0, 0, 1, adx);

   if(InpUseRSIFilter && rsi[0] >= InpRSI_Overbought) return;
   if(InpUseADXFilter && adx[0] < InpADX_MinTrend) return;

   ExecuteBuy(m5_c1);
   g_State = STATE_IDLE;
}

//+------------------------------------------------------------------+
//| Safety Functions                                                 |
//+------------------------------------------------------------------+
bool IsRiskGuardTriggered() {
   double dailyProfit = AccountInfoDouble(ACCOUNT_BALANCE) - AccountInfoDouble(ACCOUNT_EQUITY); // Simple check
   double currentDD = (g_InitialBalance - AccountInfoDouble(ACCOUNT_EQUITY)) / g_InitialBalance * 100.0;
   
   if(currentDD >= InpMaxTotalDDPct) {
      g_DebugReason = "BLOCK: Max Drawdown Hit";
      return true;
   }
   
   if(TradesThisPeriod(PERIOD_D1) >= InpMaxTradesPerDay) {
      g_DebugReason = "BLOCK: Daily Trade Limit";
      return true;
   }
   
   if(TradesThisPeriod(PERIOD_W1) >= InpMaxTradesPerWeek) {
      g_DebugReason = "BLOCK: Weekly Trade Limit";
      return true;
   }
   
   // HARD EQUITY PROTECTOR
   double dailyLossLimit = g_InitialBalance * (InpMaxDailyLossPct / 100.0);
   double currentDailyLoss = AccountInfoDouble(ACCOUNT_BALANCE) - AccountInfoDouble(ACCOUNT_EQUITY);

   if(currentDailyLoss >= dailyLossLimit) {
      g_DebugReason = "CRITICAL: Daily Loss Limit Hit. Closing all!";
      CloseAllPositions(); // Emergency close
      return true;
   }
   
   return false;
}

bool IsFridayLate() {
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.day_of_week == 5 && dt.hour >= 16); // Blocks after 4 PM Friday
}

int TradesThisPeriod(ENUM_TIMEFRAMES period) {
   HistorySelect(iTime(_Symbol, period, 0), TimeCurrent());
   int count = 0;
   for(int i = HistoryDealsTotal()-1; i>=0; i--) {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(t, DEAL_MAGIC) == InpMagicNumber && HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Core Logic (M15 & Helpers)                                       |
//+------------------------------------------------------------------+
void CheckM15Permission() {
   double e20[], e50[], e100[], e200[];
   CopyBuffer(hM15_E20,0,0,1,e20); CopyBuffer(hM15_E50,0,0,1,e50);
   CopyBuffer(hM15_E100,0,0,1,e100); CopyBuffer(hM15_E200,0,0,1,e200);

   if(e20[0] > e50[0] && e50[0] > e100[0] && e100[0] > e200[0]) {
      g_State = STATE_WAIT_M5_BREAKOUT;
      g_BreakoutLevel = iHigh(_Symbol, PERIOD_M15, 1) + InpEntryBuffer_USD;
   } else {
      g_State = STATE_IDLE;
   }
}

void ExecuteBuy(double price) {
   double sl = price - InpFixedSL_Dist; 
   double tp = price + InpFixedTP_Dist; 
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot = riskAmount / ((MathAbs(price - sl) / _Point) * (tickValue / (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) / _Point)));
   
   lot = MathFloor(lot / SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)) * SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   Trade.Buy(lot, _Symbol, SymbolPtr.Ask(), NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits));
}

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

void UpdateDashboard() {
   string text = "--- CAMBO SMC PROP GUARD ---\n";
   text += "Daily Trades: " + (string)TradesThisPeriod(PERIOD_D1) + "/" + (string)InpMaxTradesPerDay + "\n";
   text += "Status: " + g_DebugReason;
   Comment(text);
}

bool IsAsianSession() {
   datetime now = TimeCurrent();
   datetime start = StringToTime(TimeToString(now, TIME_DATE) + " " + InpAsianStart);
   datetime end   = StringToTime(TimeToString(now, TIME_DATE) + " " + InpAsianEnd);
   return (end < start) ? (now >= start || now < end) : (now >= start && now <= end);
}

bool HasTradedToday() { return TradesThisPeriod(PERIOD_D1) > 0; }

//+------------------------------------------------------------------+
//| New Helper Function to Emergency Close                           |
//+------------------------------------------------------------------+
void CloseAllPositions() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(Position.SelectByIndex(i) && Position.Magic() == InpMagicNumber) {
         Trade.PositionClose(Position.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//|                                                  CamboSMCore.mq5 |
//|                                  Copyright 2026, Professional AI |
//|                                   Version 22.10 – Prop Guard FIX  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Professional AI"
#property link      "https://www.mql5.com"
#property version   "22.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

enum ENUM_SETUP_STATE { STATE_IDLE, STATE_WAIT_M5_BREAKOUT };

//--- INPUTS
input group "🛡️ PROP FIRM RISK GUARDS"
input double InpMaxDailyLossPct      = 3.0;      // Daily loss lock (% of day start balance)
input double InpMaxTotalDDPct        = 8.0;      // Max drawdown lock (% of baseline)
input bool   InpUseInitialBalanceDD  = true;     // baseline vs initial (recommended TRUE for challenges)
input int    InpMaxTradesPerDay      = 1;
input int    InpMaxTradesPerWeek     = 4;
input int    InpMaxOpenPositions     = 1;
input bool   InpEmergencyCloseOnDailyLock = true;

input group "🧯 EXECUTION SAFETY"
input double InpMaxSpreadUSD         = 0.60;     // block if spread too high (XAUUSD)
input int    InpMaxSlippagePoints    = 30;
input bool   InpBlockOnFridayNY      = true;     // avoid late Friday
input int    InpFridayBlockHour      = 16;       // broker time hour

input group "SOP Filters"
input int      InpMagicNumber        = 40168;
input double   InpRiskPercent        = 0.5;

input group "Stops/Targets (Global Inputs)"
input double   InpFixedSL_Dist       = 15.0;
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

input group "⏳ START DELAY"
input int InpStartDelayHours = 4;   // Delay EA start in hours

//--- GLOBALS
int hM15_E20, hM15_E50, hM15_E100, hM15_E200;
int hM5_RSI, hM5_ADX;

CTrade        Trade;
CPositionInfo Position;
CSymbolInfo   SymbolPtr;
CAccountInfo  Account;

double   g_InitialBalance = 0.0;
double   g_DayStartBalance = 0.0;
datetime g_DayStartTime = 0;
datetime g_WeekStartTime = 0;

datetime lastM15 = 0;
ENUM_SETUP_STATE g_State = STATE_IDLE;
double   g_BreakoutLevel = 0.0;
string   g_DebugReason = "Waiting for M15 Setup";
datetime g_EAStartTime = 0;
//+------------------------------------------------------------------+
//| Utility: roll day/week baseline                                  |
//+------------------------------------------------------------------+
void UpdateDayWeekBaselines()
{
   datetime d0 = iTime(_Symbol, PERIOD_D1, 0);
   if(d0 != 0 && d0 != g_DayStartTime)
   {
      g_DayStartTime = d0;
      g_DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   }

   datetime w0 = iTime(_Symbol, PERIOD_W1, 0);
   if(w0 != 0 && w0 != g_WeekStartTime)
   {
      g_WeekStartTime = w0;
   }
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(_Period != PERIOD_M15) { Alert("❌ ERROR: Use M15 Timeframe."); return(INIT_FAILED); }
   
   if(!SymbolPtr.Name(_Symbol)) return INIT_FAILED;
   g_EAStartTime = TimeCurrent();
  
   g_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_DayStartTime   = iTime(_Symbol, PERIOD_D1, 0);
   g_WeekStartTime  = iTime(_Symbol, PERIOD_W1, 0);
   g_DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

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

//+------------------------------------------------------------------+
//| Helpers: trade counting                                          |
//+------------------------------------------------------------------+
int TradesSince(datetime fromTime)
{
   HistorySelect(fromTime, TimeCurrent());
   int count = 0;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;

      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol) continue;
      if((int)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;

      if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN)
         count++;
   }
   return count;
}

int TradesToday() { return TradesSince(g_DayStartTime); }
int TradesThisWeek() { return TradesSince(g_WeekStartTime); }

//+------------------------------------------------------------------+
//| Helpers: count positions                                         |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(Position.SelectByIndex(i))
      {
         if(Position.Symbol() == _Symbol && Position.Magic() == InpMagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Safety: friday block                                             |
//+------------------------------------------------------------------+
bool IsFridayLate()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= InpFridayBlockHour);
}

//+------------------------------------------------------------------+
//| Safety: daily loss lock & max DD lock                             |
//+------------------------------------------------------------------+
bool IsRiskGuardTriggered()
{
   UpdateDayWeekBaselines();

   // Trade caps
   if(TradesToday() >= InpMaxTradesPerDay)
   {
      g_DebugReason = "BLOCK: Daily Trade Limit";
      return true;
   }

   if(TradesThisWeek() >= InpMaxTradesPerWeek)
   {
      g_DebugReason = "BLOCK: Weekly Trade Limit";
      return true;
   }

   if(CountMyPositions() >= InpMaxOpenPositions)
   {
      g_DebugReason = "BLOCK: Max Open Positions";
      return true;
   }

   // Spread guard (USD price spread for XAUUSD-style symbols)
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadUSD = ask - bid;
   if(spreadUSD > InpMaxSpreadUSD)
   {
      g_DebugReason = StringFormat("BLOCK: Spread too high (%.2f)", spreadUSD);
      return true;
   }

   // Friday safety
   if(InpBlockOnFridayNY && IsFridayLate())
   {
      g_DebugReason = "BLOCK: Late Friday safety";
      return true;
   }

   // Daily loss: compare EQUITY now vs BALANCE at day start (includes closed+floating)
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyPnL = equity - g_DayStartBalance; // negative = loss
   double dailyLossLimit = -g_DayStartBalance * (InpMaxDailyLossPct / 100.0);

   if(dailyPnL <= dailyLossLimit)
   {
      g_DebugReason = StringFormat("CRITICAL: Daily loss lock (PnL=%.2f / Limit=%.2f)", dailyPnL, dailyLossLimit);
      if(InpEmergencyCloseOnDailyLock) CloseAllPositions();
      return true;
   }

   // Total DD lock
   double baseline = InpUseInitialBalanceDD ? g_InitialBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   if(baseline <= 0.0) baseline = AccountInfoDouble(ACCOUNT_BALANCE);

   double ddPct = (baseline - equity) / baseline * 100.0;
   if(ddPct >= InpMaxTotalDDPct)
   {
      g_DebugReason = StringFormat("CRITICAL: Max DD lock (%.2f%% >= %.2f%%)", ddPct, InpMaxTotalDDPct);
      // Optional: close positions too (usually safer for prop)
      CloseAllPositions();
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Execution: validate stops                                        |
//+------------------------------------------------------------------+
bool ValidateStopsForBuy(double entry, double sl, double tp)
{
   // Basic direction checks
   if(sl >= entry) return false;
   if(tp <= entry) return false;

   // Broker minimum stops level
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * _Point;

   if((entry - sl) < minDist) return false;
   if((tp - entry) < minDist) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Main Tick                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDashboard();
   
      if(IsStartDelayActive())
      {
         int remain = (InpStartDelayHours * 3600) - (int)(TimeCurrent() - g_EAStartTime);
         g_DebugReason = StringFormat("START DELAY ACTIVE: %d min remaining", remain / 60);
         g_State = STATE_IDLE;
         return;
      }

   
   // Prop guard first
   if(IsRiskGuardTriggered())
   {
      g_State = STATE_IDLE;
      return;
   }

   if(InpEnableBE) HandleBreakEven();

   // M15 permission check on new M15 bar
   datetime m15Time = iTime(_Symbol, PERIOD_M15, 0);
   if(m15Time != 0 && m15Time != lastM15)
   {
      lastM15 = m15Time;
      CheckM15Permission();
   }

   if(g_State == STATE_WAIT_M5_BREAKOUT)
      MonitorM5Execution();
}

//+------------------------------------------------------------------+
//| Step 2: M5 Execution                                             |
//+------------------------------------------------------------------+
void MonitorM5Execution()
{
   double m5_c1 = iClose(_Symbol, PERIOD_M5, 1);

   bool isBreakout = (m5_c1 > g_BreakoutLevel &&
                      m5_c1 > iHigh(_Symbol, PERIOD_M5, 2) &&
                      m5_c1 > iOpen(_Symbol, PERIOD_M5, 1));

   if(!isBreakout)
   {
      g_DebugReason = StringFormat("Waiting M5 Close > %.2f", g_BreakoutLevel);
      return;
   }

   double rsi[1], adx[1];
   if(CopyBuffer(hM5_RSI, 0, 0, 1, rsi) <= 0) { g_DebugReason = "RSI buffer error"; return; }
   if(CopyBuffer(hM5_ADX, 0, 0, 1, adx) <= 0) { g_DebugReason = "ADX buffer error"; return; }

   if(InpUseRSIFilter && rsi[0] >= InpRSI_Overbought)
   {
      g_DebugReason = StringFormat("BLOCK: RSI overbought (%.2f)", rsi[0]);
      return;
   }

   if(InpUseADXFilter && adx[0] < InpADX_MinTrend)
   {
      g_DebugReason = StringFormat("BLOCK: ADX too low (%.2f)", adx[0]);
      return;
   }

   ExecuteBuy();
   g_State = STATE_IDLE;
}

//+------------------------------------------------------------------+
//| Core: M15 Permission                                             |
//+------------------------------------------------------------------+
void CheckM15Permission()
{
   double e20[1], e50[1], e100[1], e200[1];
   if(CopyBuffer(hM15_E20, 0, 0, 1, e20) <= 0) { g_DebugReason = "E20 buffer error"; return; }
   if(CopyBuffer(hM15_E50, 0, 0, 1, e50) <= 0) { g_DebugReason = "E50 buffer error"; return; }
   if(CopyBuffer(hM15_E100,0, 0, 1, e100)<= 0) { g_DebugReason = "E100 buffer error"; return; }
   if(CopyBuffer(hM15_E200,0, 0, 1, e200)<= 0) { g_DebugReason = "E200 buffer error"; return; }

   if(e20[0] > e50[0] && e50[0] > e100[0] && e100[0] > e200[0])
   {
      g_State = STATE_WAIT_M5_BREAKOUT;
      g_BreakoutLevel = iHigh(_Symbol, PERIOD_M15, 1) + InpEntryBuffer_USD;
      g_DebugReason = StringFormat("M15 OK → waiting M5 breakout > %.2f", g_BreakoutLevel);
   }
   else
   {
      g_State = STATE_IDLE;
      g_DebugReason = "M15 blocked: EMAs not stacked";
   }
}

//+------------------------------------------------------------------+
//| Execution: Buy with risk lot                                     |
//+------------------------------------------------------------------+
void ExecuteBuy()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = entry - InpFixedSL_Dist;
   double tp = entry + InpFixedTP_Dist;

   if(!ValidateStopsForBuy(entry, sl, tp))
   {
      g_DebugReason = "BLOCK: Invalid SL/TP (stops level or direction)";
      return;
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0.0 || tickSize <= 0.0)
   {
      g_DebugReason = "BLOCK: Invalid tick data";
      return;
   }

   double slPoints = MathAbs(entry - sl) / _Point;
   double pointValue = tickValue / (tickSize / _Point);
   if(pointValue <= 0.0 || slPoints <= 0.0)
   {
      g_DebugReason = "BLOCK: Lot calc error";
      return;
   }

   double lot = riskAmount / (slPoints * pointValue);

   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lot = MathFloor(lot / step) * step;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   bool ok = Trade.Buy(lot, _Symbol, entry, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits));

   if(ok)
      g_DebugReason = StringFormat("Trade Sent: %.2f lots | Risk $%.2f", lot, riskAmount);
   else
      g_DebugReason = StringFormat("Order Failed: %d", GetLastError());
}

//+------------------------------------------------------------------+
//| BreakEven                                                        |
//+------------------------------------------------------------------+
void HandleBreakEven()
{
   if(InpDisableBE_Asian && IsAsianSession()) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(Position.SelectByIndex(i) && Position.Magic() == InpMagicNumber && Position.Symbol()==_Symbol)
      {
         double entry = Position.PriceOpen();
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         if(Position.StopLoss() < entry && (bid - entry) >= InpBE_Trigger_USD)
         {
            Trade.PositionModify(Position.Ticket(),
                                 NormalizeDouble(entry + InpBE_Profit_Lock_USD, _Digits),
                                 Position.TakeProfit());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   UpdateDayWeekBaselines();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyPnL = equity - g_DayStartBalance;

   string text = "--- CAMBO SMC PROP GUARD ---\n";
   text += "State: " + EnumToString(g_State) + "\n";
   text += "Day Trades: " + (string)TradesToday() + "/" + (string)InpMaxTradesPerDay + "\n";
   text += "Week Trades: " + (string)TradesThisWeek() + "/" + (string)InpMaxTradesPerWeek + "\n";
   text += "Daily PnL: " + DoubleToString(dailyPnL, 2) + "\n";
   text += "Status: " + g_DebugReason;

   Comment(text);
}

//+------------------------------------------------------------------+
//| Asian Session                                                    |
//+------------------------------------------------------------------+
bool IsAsianSession()
{
   datetime now = TimeCurrent();
   datetime start = StringToTime(TimeToString(now, TIME_DATE) + " " + InpAsianStart);
   datetime end   = StringToTime(TimeToString(now, TIME_DATE) + " " + InpAsianEnd);
   return (end < start) ? (now >= start || now < end) : (now >= start && now <= end);
}

//+------------------------------------------------------------------+
//| Emergency close                                                  |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(Position.SelectByIndex(i) && Position.Magic() == InpMagicNumber && Position.Symbol()==_Symbol)
      {
         Trade.PositionClose(Position.Ticket());
      }
   }
}

bool IsStartDelayActive()
{
   if(InpStartDelayHours <= 0) return false;

   int delaySeconds = InpStartDelayHours * 3600;
   return (TimeCurrent() - g_EAStartTime) < delaySeconds;
}

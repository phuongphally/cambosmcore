📘 CamboSMCore v22.12 — EA Documentation

Strategy Type: Trend Breakout (Momentum Continuation)
Platform: MetaTrader 5 (MT5 only)
Symbol Focus: XAUUSD (Gold)
Timeframe:

Chart: M15 (mandatory)

Execution: M5

Trend: M15 EMA structure

1️⃣ Core Strategy Overview

CamboSMCore is a trend-following breakout EA designed for:

Prop firm challenges

Strict risk control

Low frequency, high-quality trades

Momentum continuation (not reversals)

Strategy Concept

Identify clear trend on M15 using EMA structure

Define a breakout level

Wait for confirmed M5 candle close

Enter market order in trend direction

Use fixed SL / TP with 1:3 RR

Enforce hard risk & time rules

2️⃣ Direction Mode (NEW in v22.12)
Input
InpTradeMode = MODE_BOTH | MODE_BUY_ONLY | MODE_SELL_ONLY

Behavior
Mode	Allowed Trades
BOTH	Buy & Sell
BUY ONLY	Buy trades only
SELL ONLY	Sell trades only

This allows:

Separate Buy-only or Sell-only testing

Safer prop firm optimization

Market bias control

3️⃣ Timeframe Rules (Very Important)
Purpose	Timeframe
EA attached	M15 only
Trend detection	M15
Entry confirmation	M5
Break-even	Tick-based

If attached to any other timeframe → EA will stop.

4️⃣ Trend Detection (M15)
Indicators Used

EMA 20

EMA 50

EMA 100

EMA 200

Bullish Condition
EMA20 > EMA50 > EMA100 > EMA200

Bearish Condition
EMA20 < EMA50 < EMA100 < EMA200


If EMAs are mixed → NO TRADE

5️⃣ Breakout Logic (M5 Execution)

Once M15 trend is valid:

BUY Setup

Breakout level = previous M15 high + buffer

M5 candle must:

Close above breakout level

Close above previous M5 high

Be bullish (close > open)

SELL Setup

Breakout level = previous M15 low − buffer

M5 candle must:

Close below breakout level

Close below previous M5 low

Be bearish (close < open)

➡️ No wick entries. Candle close only.

6️⃣ Filters (Optional but Safe)
RSI Filter (M5)

BUY blocked if RSI ≥ InpRSI_Overbought

SELL blocked if RSI ≤ InpRSI_Oversold

(Default: OFF)

ADX Filter (M5)

Trade allowed only if:

ADX ≥ InpADX_MinTrend


(Default: ON, value = 20)

Purpose:

Avoid ranging markets

Trade only strong momentum

7️⃣ Entry Type

Market orders only

No pending orders

No limits

No scaling

No averaging

Reason:

Breakout strategy requires speed

Avoids missed momentum

Cleaner prop firm execution

8️⃣ Stop Loss & Take Profit
Fixed Distances (Price-based)
Parameter	Default
SL	15.0
TP	45.0
Risk : Reward	1 : 3

Stops are validated against:

Broker minimum stop distance

Direction correctness

Invalid SL/TP → trade blocked

9️⃣ Risk Management (Lot Calculation)
Risk Formula
Risk = Balance × InpRiskPercent


Lot size is calculated using:

SL distance

Tick value

Tick size

Broker volume rules

✔ Dynamic lot sizing
✔ Fixed percentage risk
✔ No martingale
✔ No compounding tricks

🔟 Break-Even Management
Trigger

When price moves +25 USD in profit

Action

SL moved to:

Entry ± InpBE_Profit_Lock_USD

Asian Session Protection

BE logic disabled during Asian hours (optional)

This prevents:

Early stop-outs

Low-liquidity noise

1️⃣1️⃣ Start Delay Guard
Purpose

Avoid VPS restarts

Avoid rollover spreads

Avoid session open chaos

Input
InpStartDelayHours = 4

Behavior

EA is completely inactive

Only countdown message shown

No logic runs

No trades allowed

1️⃣2️⃣ Prop Firm Risk Guards (Critical)
Trade Limits
Rule	Default
Max trades / day	1
Max trades / week	4
Max open positions	1
Daily Loss Lock

Based on day-start balance

Uses equity (floating included)

If hit:

Trading stops

Optional emergency close

Max Drawdown Lock

Based on:

Initial balance (recommended)

OR current balance

Uses equity

If hit:

All positions closed

EA locked

Spread Protection

Trade blocked if:

Ask − Bid > InpMaxSpreadUSD


Critical for XAUUSD.

Friday Safety

Trades blocked after:

Friday ≥ InpFridayBlockHour


Avoids:

Weekend gaps

Liquidity drops

1️⃣3️⃣ Dashboard (On-Chart)

Displays:

Trade mode (BUY / SELL / BOTH)

Current state

Setup direction

Daily & weekly trade count

Daily PnL

Current status / block reason

This makes the EA transparent and auditable.

1️⃣4️⃣ Emergency Close

If:

Daily loss exceeded

Max DD exceeded

Then:

All EA-controlled positions closed immediately

No new trades allowed

✅ What This EA Is (and Is Not)
✔ It IS

Trend-following

Breakout-based

Prop-firm safe

Low-frequency

Rule-based

Non-repainting

❌ It is NOT

Scalping

Reversal trading

Grid / martingale

News trading

High-frequency

🧠 Final Notes (Very Important)

This EA works because:

It is simple

It is strict

It waits for confirmation

It avoids overtrading

Do not add:

trailing stops

limit orders

averaging

extra indicators

That will reduce performance, not improve it.

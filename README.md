# 📘 CamboSMCore v22.12 – Direction Mode

**Platform:** MetaTrader 5 (MT5 only)  
**Strategy Type:** Trend Breakout / Momentum Continuation  
**Primary Symbol:** XAUUSD (Gold)  
**Author:** Professional AI  
**Version:** 22.12

---

## 1. Overview

CamboSMCore is a **low-frequency, prop-firm–safe Expert Advisor** designed to trade **strong directional breakouts** on Gold.

The EA focuses on:
- Clean trend structure
- Confirmed breakouts (no guessing)
- Fixed risk–reward (1:3)
- Strict prop firm risk protection

It is intentionally **simple, strict, and disciplined**.

---

## 2. Timeframe Rules (Mandatory)

| Purpose | Timeframe |
|------|---------|
| EA Chart | **M15 only** |
| Trend Detection | M15 |
| Entry Confirmation | M5 |

❗ If attached to any timeframe other than **M15**, the EA will stop.

---

## 3. Direction Mode (v22.12 Feature)

### Input
```cpp
InpTradeMode = MODE_BOTH | MODE_BUY_ONLY | MODE_SELL_ONLY
```

### Behavior
| Mode | Allowed Trades |
|----|---------------|
| BOTH | Buy & Sell |
| BUY ONLY | Buy trades only |
| SELL ONLY | Sell trades only |

This allows directional bias control and safer prop-firm testing.

---

## 4. Trend Detection (M15 EMA Structure)

### Indicators Used
- EMA 20
- EMA 50
- EMA 100
- EMA 200

### Bullish Trend
```
EMA20 > EMA50 > EMA100 > EMA200
```

### Bearish Trend
```
EMA20 < EMA50 < EMA100 < EMA200
```

If EMAs are mixed → **No trade allowed**.

---

## 5. Breakout Logic (M5 Confirmation)

After a valid M15 trend is detected, the EA waits for **confirmed M5 breakout**.

### BUY Breakout Conditions
- M5 close > previous M15 high + buffer
- M5 close > previous M5 high
- M5 candle is bullish (close > open)

### SELL Breakout Conditions
- M5 close < previous M15 low − buffer
- M5 close < previous M5 low
- M5 candle is bearish (close < open)

🟢 **Candle close confirmation only** — no wick entries.

---

## 6. Optional Filters

### RSI Filter (M5)
- BUY blocked if RSI ≥ `InpRSI_Overbought`
- SELL blocked if RSI ≤ `InpRSI_Oversold`

(Default: OFF)

### ADX Filter (M5)
- Trade allowed only if:
```
ADX ≥ InpADX_MinTrend
```

(Default: ON, value = 20)

Purpose: avoid ranging markets and trade momentum only.

---

## 7. Entry Type

- **Market orders only**
- No pending orders
- No limit orders
- No scaling or averaging

This ensures fast execution during breakouts.

---

## 8. Stop Loss & Take Profit

| Parameter | Default |
|--------|--------|
| Stop Loss | 15.0 |
| Take Profit | 45.0 |
| Risk : Reward | **1 : 3** |

Stops are validated against broker minimum stop levels.

---

## 9. Risk & Lot Calculation

### Risk Formula
```
Risk = Account Balance × InpRiskPercent
```

Lot size is calculated dynamically using:
- SL distance
- Tick value
- Tick size
- Broker volume constraints

✔ Fixed % risk  
✔ No martingale  
✔ No grid  
✔ No compounding tricks

---

## 10. Break-Even Logic

### Trigger
- When trade reaches **+25 USD** profit

### Action
- SL moved to:
```
Entry ± InpBE_Profit_Lock_USD
```

### Asian Session Protection
- Break-even logic can be disabled during Asian session to avoid noise.

---

## 11. Start Delay Guard

### Purpose
- Avoid VPS restarts
- Avoid rollover spreads
- Avoid session open volatility

### Input
```cpp
InpStartDelayHours = 4
```

### Behavior
- EA is fully inactive during delay
- No signal evaluation
- Countdown displayed on chart

---

## 12. Prop Firm Risk Guards

### Trade Limits
| Rule | Default |
|----|--------|
| Max trades per day | 1 |
| Max trades per week | 4 |
| Max open positions | 1 |

### Daily Loss Lock
- Based on **day-start balance**
- Uses **equity (floating included)**
- Optional emergency close

### Max Drawdown Lock
- Based on initial balance (recommended)
- Uses equity
- Auto-closes all EA positions

### Spread Protection
- Trades blocked if:
```
Ask − Bid > InpMaxSpreadUSD
```

### Friday Safety
- Trades blocked after:
```
Friday ≥ InpFridayBlockHour
```

---

## 13. Dashboard Information

The EA displays:
- Trade mode (BUY / SELL / BOTH)
- Current state & direction
- Daily & weekly trade count
- Daily PnL
- Current block or execution status

This ensures full transparency and auditability.

---

## 14. What This EA Is / Is Not

### ✔ This EA IS
- Trend-following
- Breakout-based
- Prop-firm safe
- Low-frequency
- Non-repainting

### ❌ This EA is NOT
- Scalping
- Reversal trading
- Grid or martingale
- News trading

---

## 15. AI Score System (Confirmation Layer)

### Purpose
The **AI Score** acts as a *final intelligent gate* before trade execution.

It does **NOT replace** the strategy logic.
It only answers one question:

> “Is the current market environment healthy enough to allow this setup?”

If AI Score is **against** the setup → trade is **blocked**.
If AI Score is **aligned** → trade proceeds normally.

---

### Components Used in AI Score
The AI Score is a weighted sum of market conditions:

| Component | Description | Weight |
|--------|------------|--------|
| EMA Alignment | Confirms trend strength | High |
| ADX Strength | Confirms momentum | Medium |
| RSI Position | Avoids exhaustion | Medium |
| ATR Volatility | Adapts to gold volatility | High |
| Session Quality | Avoids dead hours | Medium |

---

### Volatility-Adaptive Thresholds (Gold)

ATR (M15) dynamically adjusts how strict the AI Score must be:

| Volatility State | ATR (M15) | Required AI Score |
|-----------------|-----------|------------------|
| Low | < 2.0 | ≥ 60 |
| Normal | 2.0 – 4.0 | ≥ 70 |
| High / News | > 4.0 | ≥ 85 |

This prevents:
- Trading during news spikes
- Trading during dead Asian ranges

---

### Direction Safety Rule

AI Score is **direction-aware**:

- BUY setup → AI Score must be bullish
- SELL setup → AI Score must be bearish

If AI bias is opposite → **hard block**

This prevents:
❌ Buy breakouts into bearish momentum
❌ Sell breakouts into bullish continuation

---

### Execution Flow (Simplified)

1. Prop-firm guards checked
2. Start delay checked
3. M15 trend validated
4. M5 breakout confirmed
5. **AI Score evaluated** ← NEW
6. Trade executed only if score ≥ threshold

---

### Philosophy

The AI Score is a *filter*, not a predictor.

It exists to:
- Reduce bad trades
- Increase consistency
- Improve prop-firm survivability

---

## 15. Final Notes

This EA works because it is:
- Simple
- Strict
- Patient
- Rule-based

⚠️ **Do not add** trailing stops, limit orders, grids, or extra indicators.

They will reduce performance.

---

**Recommended Use:**  
✔ Prop firm challenges  
✔ Funded accounts  
✔ VPS deployment

---

_End of documentation_


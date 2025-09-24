cd ~/copy_trade_hub
mkdir -p MQL5/Experts

cat > MQL5/Experts/MustiFX_Master.mq5 <<'MQ'
/* Paste of the full MustiFX_Master.mq5 EA (complete, same as provided) */

//+------------------------------------------------------------------+
//| MustiFX_Master.mq5                                              |
//| MustiFX WickTrap + MACD+RSI + Prop-Firm Guards + Telegram + UI  |
//+------------------------------------------------------------------+
#property copyright "MustiFX"
#property version   "1.0"
#property strict

#include <Trade/Trade.mqh>
#include <Charts/ChartObjectsTxtControls.mqh>

CTrade trade;

// ----------------------- INPUTS -----------------------
input bool   EnableBuy            = true;
input bool   EnableSell           = false;

input bool   UseWickTrap          = true;    // enable wicktrap logic
input bool   UseMACD_RSI         = true;     // MACD + RSI module (V3 style toggle)

// Core indicators
input int    MAPeriod             = 50;
input int    RSIPeriod            = 14;
input double RSIminBuy            = 50.0;
input double RSImaxSell           = 50.0;

// WickTrap thresholds
input double MinBodyToRangePct    = 15.0;
input double MaxWickToRangePct    = 55.0;
input double MinWickPoints        = 4.0;

// MACD
input int    MACD_FastEMA         = 12;
input int    MACD_SlowEMA         = 26;
input int    MACD_Signal          = 9;

// Risk / SL / TP / Trailing
input bool   UseATR               = false;
input int    ATRperiod            = 14;
input double ATRmultSL            = 2.0;
input double ATRmultTrailGap      = 2.0;

input double StopLossPips         = 40;     // used if UseATR=false
input bool   UseTP                = false;
input double TakeProfitPips       = 120;

input bool   UseTrailing          = true;
input double TrailStartPips       = 30;
input double TrailGapPips         = 25;
input double TrailStepPips        = 10;

input bool   UseBreakEven         = true;
input double BE_TriggerPips       = 25;
input double BE_OffsetPips        = 2;

// Slippage / Spread
input int    MaxSpreadPips        = 20;
input int    SlippagePips         = 3;

// Sessions / Days
input bool Trade_Mon=true, Trade_Tue=true, Trade_Wed=true, Trade_Thu=true, Trade_Fri=true;
input bool Trade_Sat=false, Trade_Sun=false;
input bool   UseSessions          = true;
input string SessionWindows       = "07:00-11:00;13:00-17:00"; // broker time; semicolon separated

// News Block
input bool   UseNewsFilter        = true;
input int    BlockMinsBeforeNews  = 30;
input int    BlockMinsAfterNews   = 30;
input string NewsTimesToday       = "13:30;15:00"; // simple list HH:MM;HH:MM

// Money / Identity
input double Lots                 = 0.10;   // fallback if UsePercentRisk=false
input bool   UsePercentRisk       = true;   // % risk sizing ON
input double RiskPercent          = 1.0;    // % of equity per trade
input long   MagicNumber          = 20250923;

// Prop-Firm Guards
input double MaxDailyDDPercent    = 4.5;    // stop new trades for the day if breached
input double MaxTotalDDPercent    = 9.5;    // hard equity floor since EA start
input double DailyTargetPercent   = 2.0;    // optional daily target lock
input bool   PauseAfterDailyTarget= false;  // pause after reaching target

// Telegram
input bool   SendTelegram         = false;
input string TelegramBotToken     = "";     // "123456:ABC-DEF..."
input string TelegramChatID       = "";     // "-1001234567890" or "123456789"

// UI / Logging
input bool   ShowPanel            = true;
input ENUM_COLOR PanelColor       = clrWhite;

// Other
input bool   EnableSellOnOppSide  = false;  // allow opposite side (if false only one side as set)
input int    MaxPositionsPerSymbol= 1;      // maximum open positions per symbol by this EA

// ----------------------- GLOBALS -----------------------
double g_initEquity=0.0;
double g_dayStartEquity=0.0;
datetime g_lastDay=0;
bool g_pausedByDaily=false;

// Panel variables
// (We use Comment() for lightweight UI)
 
// ----------------------- HELPERS -----------------------
double PipPoint(){
  int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
  double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
  return ((d==3||d==5)? 10*pt : pt);
}
double NP(double p){ int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS); return NormalizeDouble(p,d); }

bool IsAllowedDay(datetime t){
  int wd=TimeDayOfWeek(t);
  if(wd==1 && Trade_Mon) return true;
  if(wd==2 && Trade_Tue) return true;
  if(wd==3 && Trade_Wed) return true;
  if(wd==4 && Trade_Thu) return true;
  if(wd==5 && Trade_Fri) return true;
  if(wd==6 && Trade_Sat) return true;
  if(wd==0 && Trade_Sun) return true;
  return false;
}

// Session helpers
bool HHMMInRange(datetime now,string win){
  if(StringLen(win)!=11) return false;
  int sh=(int)StringToInteger(StringSubstr(win,0,2));
  int sm=(int)StringToInteger(StringSubstr(win,3,2));
  int eh=(int)StringToInteger(StringSubstr(win,6,2));
  int em=(int)StringToInteger(StringSubstr(win,9,2));
  MqlDateTime mt; TimeToStruct(now,mt);
  int cur=mt.hour*60+mt.min, s=sh*60+sm, e=eh*60+em;
  if(s<=e) return (cur>=s && cur<=e); else return (cur>=s || cur<=e);
}
bool InAnySession(datetime now){
  if(!UseSessions) return true;
  if(StringLen(SessionWindows)<5) return true;
  string arr[]; int n=StringSplit(SessionWindows,';',arr);
  for(int i=0;i<n;i++) if(HHMMInRange(now,arr[i])) return true;
  return false;
}

// News block
bool InNewsBlock(datetime now){
  if(!UseNewsFilter) return false;
  if(StringLen(NewsTimesToday)<5) return false;
  string arr[]; int n=StringSplit(NewsTimesToday,';',arr);
  for(int i=0;i<n;i++){
    if(StringLen(arr[i])!=5) continue;
    int hh=(int)StringToInteger(StringSubstr(arr[i],0,2));
    int mm=(int)StringToInteger(StringSubstr(arr[i],3,2));
    MqlDateTime mt; TimeToStruct(now,mt);
    datetime today = now - (mt.hour*3600+mt.min*60+mt.sec);
    datetime t = today + (hh*3600+mm*60);
    if(now >= t - BlockMinsBeforeNews*60 && now <= t + BlockMinsAfterNews*60)
      return true;
  }
  return false;
}

// Spread check
bool SpreadOK(){
  double spr=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/PipPoint();
  return (spr <= MaxSpreadPips);
}

// Wick helpers
bool HasLowerWick(int i){
  double o=iOpen(_Symbol,PERIOD_CURRENT,i), c=iClose(_Symbol,PERIOD_CURRENT,i);
  double lo=iLow(_Symbol,PERIOD_CURRENT,i);
  double bodyLow=MathMin(o,c);
  return (bodyLow-lo) > (MinWickPoints*SymbolInfoDouble(_Symbol,SYMBOL_POINT));
}
bool HasUpperWick(int i){
  double o=iOpen(_Symbol,PERIOD_CURRENT,i), c=iClose(_Symbol,PERIOD_CURRENT,i);
  double hi=iHigh(_Symbol,PERIOD_CURRENT,i);
  double bodyHigh=MathMax(o,c);
  return (hi-bodyHigh) > (MinWickPoints*SymbolInfoDouble(_Symbol,SYMBOL_POINT));
}

// Trend filter (EMA50 vs EMA200)
bool TrendOK_Buy(){
  double ema50=iMA(_Symbol,PERIOD_CURRENT,50,0,MODE_EMA,PRICE_CLOSE,1);
  double ema200=iMA(_Symbol,PERIOD_CURRENT,200,0,MODE_EMA,PRICE_CLOSE,1);
  double price=iClose(_Symbol,PERIOD_CURRENT,1);
  return (ema50>ema200 && price>ema50);
}
bool TrendOK_Sell(){
  double ema50=iMA(_Symbol,PERIOD_CURRENT,50,0,MODE_EMA,PRICE_CLOSE,1);
  double ema200=iMA(_Symbol,PERIOD_CURRENT,200,0,MODE_EMA,PRICE_CLOSE,1);
  double price=iClose(_Symbol,PERIOD_CURRENT,1);
  return (ema50<ema200 && price<ema50);
}

// WickTrap checks (buy)
bool WickTrapPass_Buy(){
  if(!UseWickTrap) return false;
  if(!HasLowerWick(1) || !HasUpperWick(2)) return false;
  double ma1=iMA(_Symbol,PERIOD_CURRENT,MAPeriod,0,MODE_SMA,PRICE_CLOSE,1);
  double ma2=iMA(_Symbol,PERIOD_CURRENT,MAPeriod,0,MODE_SMA,PRICE_CLOSE,2);
  if(!(iLow(_Symbol,PERIOD_CURRENT,1) > ma1)) return false;
  if(!(iHigh(_Symbol,PERIOD_CURRENT,2) < ma2)) return false;
  if(!(iOpen(_Symbol,PERIOD_CURRENT,0) > iHigh(_Symbol,PERIOD_CURRENT,1))) return false;

  double hi=iHigh(_Symbol,PERIOD_CURRENT,1), lo=iLow(_Symbol,PERIOD_CURRENT,1);
  double o=iOpen(_Symbol,PERIOD_CURRENT,1),  c=iClose(_Symbol,PERIOD_CURRENT,1);
  double range=hi-lo; if(range<=0) return false;
  double body=fabs(c-o);
  double bodyPct=body/range*100.0;
  double upWickPct=(hi-MathMax(o,c))/range*100.0;
  double loWickPct=(MathMin(o,c)-lo)/range*100.0;
  if(bodyPct <= MinBodyToRangePct) return false;
  if(upWickPct >= MaxWickToRangePct || loWickPct >= MaxWickToRangePct) return false;

  double rsi=iRSI(_Symbol,PERIOD_CURRENT,RSIPeriod,PRICE_CLOSE,1);
  if(rsi <= RSIminBuy) return false;

  // optional trend check
  if(!TrendOK_Buy()) return false;

  return true;
}

// WickTrap sell
bool WickTrapPass_Sell(){
  if(!UseWickTrap) return false;
  if(!HasUpperWick(1) || !HasLowerWick(2)) return false;
  double ma1=iMA(_Symbol,PERIOD_CURRENT,MAPeriod,0,MODE_SMA,PRICE_CLOSE,1);
  double ma2=iMA(_Symbol,PERIOD_CURRENT,MAPeriod,0,MODE_SMA,PRICE_CLOSE,2);
  if(!(iHigh(_Symbol,PERIOD_CURRENT,1) < ma1)) return false;
  if(!(iLow(_Symbol,PERIOD_CURRENT,2)  > ma2)) return false;
  if(!(iOpen(_Symbol,PERIOD_CURRENT,0) < iLow(_Symbol,PERIOD_CURRENT,1))) return false;

  double hi=iHigh(_Symbol,PERIOD_CURRENT,1), lo=iLow(_Symbol,PERIOD_CURRENT,1);
  double o=iOpen(_Symbol,PERIOD_CURRENT,1),  c=iClose(_Symbol,PERIOD_CURRENT,1);
  double range=hi-lo; if(range<=0) return false;
  double body=fabs(c-o);
  double bodyPct=body/range*100.0;
  double upWickPct=(hi-MathMax(o,c))/range*100.0;
  double loWickPct=(MathMin(o,c)-lo)/range*100.0;
  if(bodyPct <= MinBodyToRangePct) return false;
  if(upWickPct >= MaxWickToRangePct || loWickPct >= MaxWickToRangePct) return false;

  double rsi=iRSI(_Symbol,PERIOD_CURRENT,RSIPeriod,PRICE_CLOSE,1);
  if(rsi >= RSImaxSell) return false;

  if(!TrendOK_Sell()) return false;

  return true;
}

// MACD+RSI filter (example simple confirmation)
bool MACD_RSI_Confirm_Buy(){
  if(!UseMACD_RSI) return true; // if disabled, pass
  double macd[], signal[], hist[];
  if(CopyBuffer(iMACD(_Symbol,PERIOD_CURRENT,MACD_FastEMA,MACD_SlowEMA,MACD_Signal,PRICE_CLOSE),0,1,3,macd)<=0) return true;
  if(CopyBuffer(iMACD(_Symbol,PERIOD_CURRENT,MACD_FastEMA,MACD_SlowEMA,MACD_Signal,PRICE_CLOSE),1,1,3,signal)<=0) return true;
  double hist0 = macd[0]-signal[0];
  double hist1 = macd[1]-signal[1];
  double rsi=iRSI(_Symbol,PERIOD_CURRENT,RSIPeriod,PRICE_CLOSE,1);
  return (hist1>0 && hist0>0 && rsi>RSIminBuy);
}
bool MACD_RSI_Confirm_Sell(){
  if(!UseMACD_RSI) return true;
  double macd[], signal[];
  if(CopyBuffer(iMACD(_Symbol,PERIOD_CURRENT,MACD_FastEMA,MACD_SlowEMA,MACD_Signal,PRICE_CLOSE),0,1,3,macd)<=0) return true;
  if(CopyBuffer(iMACD(_Symbol,PERIOD_CURRENT,MACD_FastEMA,MACD_SlowEMA,MACD_Signal,PRICE_CLOSE),1,1,3,signal)<=0) return true;
  double hist0 = macd[0]-signal[0];
  double hist1 = macd[1]-signal[1];
  double rsi=iRSI(_Symbol,PERIOD_CURRENT,RSIPeriod,PRICE_CLOSE,1);
  return (hist1<0 && hist0<0 && rsi<RSImaxSell);
}

// ----------------------- ORDER MGMT -----------------------
void SetSlippage(){
  int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
  int pip_to_points = (d==3||d==5)? 10 : 1;
  trade.SetDeviationInPoints(SlippagePips * pip_to_points);
}

// Adjust stops for broker stop level
void AdjustStopsToBroker(double &price, double &sl, double &tp){
  int stop_lvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
  int freeze   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
  int minstep  = MathMax(stop_lvl, freeze);
  double step_points = MathMax(1, minstep)*SymbolInfoDouble(_Symbol,SYMBOL_POINT);
  if(step_points<=0) return;
  if(tp>0 && MathAbs(tp-price) < step_points) tp = (tp>price)? price+step_points : price-step_points;
  if(sl>0 && MathAbs(price-sl) < step_points) sl = (sl>price)? price+step_points : price-step_points;
}

// Calculate lots by % risk
double CalcLotsByRisk(double price,double sl){
  if(!UsePercentRisk) return Lots;
  if(sl<=0.0 || MathAbs(price-sl)<SymbolInfoDouble(_Symbol,SYMBOL_POINT)*2) return Lots; // safety fallback

  double risk_amt = AccountInfoDouble(ACCOUNT_EQUITY) * (RiskPercent/100.0);
  double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
  double tick_sz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
  if(tick_val<=0 || tick_sz<=0) return Lots;

  double distance_points = MathAbs(price - sl)/SymbolInfoDouble(_Symbol,SYMBOL_POINT);
  double value_per_point_per_lot = (tick_val / tick_sz);
  if(value_per_point_per_lot<=0) return Lots;

  double raw_lots = risk_amt / (distance_points * value_per_point_per_lot);

  double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  double vstep= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

  if(raw_lots < vmin) raw_lots = vmin;
  if(raw_lots > vmax) raw_lots = vmax;

  raw_lots = MathFloor(raw_lots / vstep) * vstep;
  return NormalizeDouble(raw_lots, 2);
}

// Place orders
void PlaceBuy(){
  if(!SpreadOK()) return;
  SetSlippage();
  double pip=PipPoint();
  double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  double sl = NP(price - (UseATR? (iATR(_Symbol,PERIOD_CURRENT,ATRperiod,1)*ATRmultSL) : StopLossPips*pip));
  double tp = (UseTP? NP(price + TakeProfitPips*pip) : 0);

  AdjustStopsToBroker(price,sl,tp);
  double lot = CalcLotsByRisk(price, sl);
  if(lot<=0) return;

  trade.SetExpertMagicNumber(MagicNumber);
  trade.Buy(lot,NULL,price,sl,tp,"MustiFX Buy");
  if(SendTelegram) {
    string txt = StringFormat("MustiFX BUY %s lot=%.2f sl=%.1f tp=%.1f",_Symbol,lot,sl,tp);
    string url = StringFormat("https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s",TelegramBotToken,TelegramChatID,CharToString(StringToCharArray(txt)));
    uchar res[]; string headers; int timeout=5000;
    if(WebRequest("GET",url,"",0,headers,0,res) < 0) {
      // WebRequest failed — probably domain not whitelisted
    }
  }
}

void PlaceSell(){
  if(!SpreadOK()) return;
  SetSlippage();
  double pip=PipPoint();
  double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
  double sl = NP(price + (UseATR? (iATR(_Symbol,PERIOD_CURRENT,ATRperiod,1)*ATRmultSL) : StopLossPips*pip));
  double tp = (UseTP? NP(price - TakeProfitPips*pip) : 0);

  AdjustStopsToBroker(price,sl,tp);
  double lot = CalcLotsByRisk(price, sl);
  if(lot<=0) return;

  trade.SetExpertMagicNumber(MagicNumber);
  trade.Sell(lot,NULL,price,sl,tp,"MustiFX Sell");
  if(SendTelegram) {
    string txt = StringFormat("MustiFX SELL %s lot=%.2f sl=%.1f tp=%.1f",_Symbol,lot,sl,tp);
    string url = StringFormat("https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s",TelegramBotToken,TelegramChatID,CharToString(StringToCharArray(txt)));
    uchar res[]; string headers; if(WebRequest("GET",url,"",0,headers,0,res) < 0) {}
  }
}

// Manage trailing & BE
void ManageTrailing(){
  double pip=PipPoint();
  for(int i=PositionsTotal()-1;i>=0;i--){
    string sym; if(!PositionGetSymbolByIndex(i,sym)) continue;
    if(sym!=_Symbol) continue;
    if(!PositionSelect(sym)) continue;
    long mg=(long)PositionGetInteger(POSITION_MAGIC);
    if(mg!=MagicNumber) continue;

    long type=(long)PositionGetInteger(POSITION_TYPE);
    double open=PositionGetDouble(POSITION_PRICE_OPEN);
    double sl  =PositionGetDouble(POSITION_SL);
    double tp  =PositionGetDouble(POSITION_TP);

    // Break-even
    if(UseBreakEven){
      if(type==POSITION_TYPE_BUY){
        double pp=(SymbolInfoDouble(_Symbol,SYMBOL_BID)-open)/pip;
        double be=NP(open + BE_OffsetPips*pip);
        if(pp>=BE_TriggerPips && (sl==0 || sl<be)) trade.PositionModify(be,tp);
      } else if(type==POSITION_TYPE_SELL){
        double pp=(open - SymbolInfoDouble(_Symbol,SYMBOL_ASK))/pip;
        double be=NP(open - BE_OffsetPips*pip);
        if(pp>=BE_TriggerPips && (sl==0 || sl>be)) trade.PositionModify(be,tp);
      }
    }

    // Trailing
    if(UseTrailing){
      double gap = (UseATR? iATR(_Symbol,PERIOD_CURRENT,ATRperiod,1)*ATRmultTrailGap : TrailGapPips*pip);
      if(type==POSITION_TYPE_BUY){
        if(SymbolInfoDouble(_Symbol,SYMBOL_BID)-open >= TrailStartPips*pip){
          double desired=NP(SymbolInfoDouble(_Symbol,SYMBOL_BID) - gap);
          if(desired>sl && (sl==0 || (desired-sl)/pip>=TrailStepPips)) trade.PositionModify(desired,tp);
        }
      } else if(type==POSITION_TYPE_SELL){
        if(open - SymbolInfoDouble(_Symbol,SYMBOL_ASK) >= TrailStartPips*pip){
          double desired=NP(SymbolInfoDouble(_Symbol,SYMBOL_ASK) + gap);
          if(desired<sl && (sl==0 || (sl-desired)/pip>=TrailStepPips)) trade.PositionModify(desired,tp);
        }
      }
    }
  }
}

// ----------------------- GUARDS -----------------------
bool DailyDDBreached(){
  if(MaxDailyDDPercent<=0) return false;
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  double limit = g_dayStartEquity * (1.0 - MaxDailyDDPercent/100.0);
  return (eq <= limit);
}
bool TotalDDBreached(){
  if(MaxTotalDDPercent<=0) return false;
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  double limit = g_initEquity * (1.0 - MaxTotalDDPercent/100.0);
  return (eq <= limit);
}
bool DailyTargetReached(){
  if(!PauseAfterDailyTarget || DailyTargetPercent<=0) return false;
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  double target = g_dayStartEquity * (1.0 + DailyTargetPercent/100.0);
  return (eq >= target);
}

// Count positions by this EA on this symbol
int CountPositionsThisSymbol(){
  int cnt=0;
  for(int i=0;i<PositionsTotal();i++){
    string s; if(!PositionGetSymbolByIndex(i,s)) continue;
    if(s!=_Symbol) continue;
    if(!PositionSelect(s)) continue;
    long mg=(long)PositionGetInteger(POSITION_MAGIC);
    if(mg==MagicNumber) cnt++;
  }
  return cnt;
}

// ----------------------- UI PANEL -----------------------
void DrawPanel(){
  if(!ShowPanel) return;
  string txt="";
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  double bal=AccountInfoDouble(ACCOUNT_BALANCE);
  double dailyP= (eq - g_dayStartEquity)/g_dayStartEquity*100.0;
  double totP = (eq - g_initEquity)/g_initEquity*100.0;
  txt += StringFormat("MustiFX Master | Sym:%s TF:%s\n", _Symbol, EnumToString(Period()));
  txt += StringFormat("Equity: %.2f  Balance: %.2f\n", eq, bal);
  txt += StringFormat("Day P/L: %.2f%%  Total P/L: %.2f%%\n", dailyP, totP);
  txt += StringFormat("Daily Guard: %.2f%%  Total Guard: %.2f%%\n", MaxDailyDDPercent, MaxTotalDDPercent);
  txt += StringFormat("Risk: %.2f%%  UseATR:%s  TP:%s\n", RiskPercent, UseATR? "Y":"N", UseTP? "Y":"N");
  txt += StringFormat("DailyLocked:%s  TotalLocked:%s\n", DailyDDBreached()?"YES":"NO", TotalDDBreached()?"YES":"NO");
  txt += StringFormat("OpenPosThisSym: %d\n", CountPositionsThisSymbol());
  txt += "MustiFX Master - by You\n";

  Comment(txt);
}

// ----------------------- MAIN -----------------------
int OnInit(){
  g_initEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
  g_dayStartEquity = g_initEquity;
  MqlDateTime mt; TimeToStruct(TimeCurrent(),mt);
  mt.hour=0; mt.min=0; mt.sec=0;
  g_lastDay = StructToTime(mt);
  if(SendTelegram) PrintFormat("Telegram enabled - remember to add https://api.telegram.org/ to Tools->Options->Expert Advisors->Allow WebRequest for listed URL");
  return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
  Comment("");
}

void OnTick(){
  datetime now=TimeCurrent();

  if(now - g_lastDay >= 24*60*60){
    g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    MqlDateTime mt; TimeToStruct(now,mt);
    mt.hour=0; mt.min=0; mt.sec=0;
    g_lastDay = StructToTime(mt);
    g_pausedByDaily = false;
  }

  ManageTrailing();
  DrawPanel();

  static datetime lastBar=0;
  if(Time[0]==lastBar) return;
  lastBar=Time[0];

  if(TotalDDBreached()) { if(!g_pausedByDaily) { Print("MustiFX: TOTAL DD breached - no new trades."); g_pausedByDaily=true; } return; }
  if(DailyDDBreached()) { if(!g_pausedByDaily) { Print("MustiFX: DAILY DD breached - no new trades for today."); g_pausedByDaily=true; } return; }
  if(DailyTargetReached()) { if(!g_pausedByDaily) { Print("MustiFX: Daily target reached - pausing new trades."); g_pausedByDaily=true; } return; }

  if(!IsAllowedDay(now))     return;
  if(!InAnySession(now))     return;
  if(InNewsBlock(now))       return;
  if(!SpreadOK())            return;

  if(CountPositionsThisSymbol() >= MaxPositionsPerSymbol) return;

  if(MaxPositionsPerSymbol==1){
    for(int i=PositionsTotal()-1;i>=0;i--){
      string s; if(!PositionGetSymbolByIndex(i,s)) continue;
      if(s==_Symbol) return;
    }
  }

  bool canBuy=false, canSell=false;
  if(EnableBuy){
    bool w=UseWickTrap? WickTrapPass_Buy() : true;
    bool mr = MACD_RSI_Confirm_Buy();
    if(w && mr) canBuy=true;
  }
  if(EnableSell){
    bool w=UseWickTrap? WickTrapPass_Sell() : true;
    bool mr = MACD_RSI_Confirm_Sell();
    if(w && mr) canSell=true;
  }

  if(canBuy) PlaceBuy();
  if(canSell) PlaceSell();
}
//+------------------------------------------------------------------+
MQ

# confirm file saved
ls -l MQL5/Experts/MustiFX_Master.mq5

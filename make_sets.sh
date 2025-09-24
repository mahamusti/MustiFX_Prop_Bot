#!/data/data/com.termux/files/usr/bin/bash
set -e
OUT=sets
mkdir -p "$OUT"

# Common safe defaults (prop-firm)
NEWS_BEFORE=30
NEWS_AFTER=30
SESS="07:00-11:00;13:00-17:00"
MAGIC=20250923

# Template writer: $1=file $2=symbol type (GOLD|FX|INDEX) $3=tf (M5|M15|M30|H1)
write_set(){
  f="$1"; KIND="$2"; TF="$3"

  # Defaults by kind
  case "$KIND" in
    GOLD)
      # gold prefers ATR SL and wider spread
      UseATR=true;  ATRmultSL=2.0;  StopLossPips=400; MaxSpr=30;
      Risk=0.5;
      case "$TF" in
        M5)  TrailStart=20; TrailGap=20; TrailStep=5 ;;
        M15) TrailStart=30; TrailGap=25; TrailStep=10 ;;
        M30) TrailStart=40; TrailGap=30; TrailStep=15 ;;
        H1)  TrailStart=50; TrailGap=40; TrailStep=20 ;;
      esac
    ;;
    FX)
      # majors can use fixed SL and tighter spread
      UseATR=false; ATRmultSL=2.0; StopLossPips=40;  MaxSpr=15;
      Risk=0.5;
      case "$TF" in
        M5)  TrailStart=20; TrailGap=20; TrailStep=5 ;;
        M15) TrailStart=25; TrailGap=20; TrailStep=8 ;;
        M30) TrailStart=30; TrailGap=25; TrailStep=10 ;;
        H1)  TrailStart=35; TrailGap=30; TrailStep=12 ;;
      esac
    ;;
    INDEX)
      # indices (US30/NAS100) are volatile; use ATR and big gaps
      UseATR=true; ATRmultSL=2.5; StopLossPips=500; MaxSpr=60;
      Risk=0.5;
      case "$TF" in
        M5)  TrailStart=120; TrailGap=100; TrailStep=25 ;;
        M15) TrailStart=180; TrailGap=140; TrailStep=35 ;;
        M30) TrailStart=240; TrailGap=180; TrailStep=50 ;;
        H1)  TrailStart=320; TrailGap=240; TrailStep=60 ;;
      esac
    ;;
  esac

  cat > "$f" <<EOF
// MustiFX WickTrap Prop-Firm preset: $f
EnableBuy=true
EnableSell=false
UseTrendFilter=true

MAPeriod=50
RSIPeriod=14
RSIminBuy=50
RSImaxSell=50

MinBodyToRangePct=15
MaxWickToRangePct=55
MinWickPoints=4

UseATR=${UseATR}
ATRperiod=14
ATRmultSL=${ATRmultSL}
ATRmultTrailGap=2.0
StopLossPips=${StopLossPips}

UseTP=false
TakeProfitPips=120

UseTrailing=true
TrailStartPips=${TrailStart}
TrailGapPips=${TrailGap}
TrailStepPips=${TrailStep}

UseBreakEven=true
BE_TriggerPips=25
BE_OffsetPips=2

MaxSpreadPips=${MaxSpr}
SlippagePips=3

Trade_Mon=true
Trade_Tue=true
Trade_Wed=true
Trade_Thu=true
Trade_Fri=true
Trade_Sat=false
Trade_Sun=false

UseSessions=true
SessionWindows=${SESS}

UseNewsFilter=true
BlockMinsBeforeNews=${NEWS_BEFORE}
BlockMinsAfterNews=${NEWS_AFTER}
NewsTimesToday=13:30;15:00

Lots=0.10
UsePercentRisk=true
RiskPercent=${Risk}
MagicNumber=${MAGIC}
EOF
}

# GOLD (XAUUSD)
for tf in M5 M15 M30 H1; do
  write_set "$OUT/MustiFX_XAUUSD_${tf}.set" GOLD "$tf"
done

# Majors (EURUSD, GBPUSD, USDJPY)
for sym in EURUSD GBPUSD USDJPY; do
  for tf in M5 M15 M30 H1; do
    write_set "$OUT/MustiFX_${sym}_${tf}.set" FX "$tf"
  done
done

# Index example (rename to your broker symbol if needed: US30, US30.cash, DJ30, WS30, US30m, NAS100)
for sym in US30 NAS100; do
  for tf in M5 M15 M30 H1; do
    write_set "$OUT/MustiFX_${sym}_${tf}.set" INDEX "$tf"
  done
done

# Bundle to a zip (optional)
cd "$OUT"
zip -r9 ../MustiFX_Prop_sets.zip .
echo "[✓] Created presets in $(pwd) and zip: ../MustiFX_Prop_sets.zip"

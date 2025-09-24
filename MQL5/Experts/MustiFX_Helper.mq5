cd ~/copy_trade_hub
mkdir -p sets

write_set() {
  file="$1"; kind="$2"; tf="$3"
  if [ "$kind" = "GOLD" ]; then
    UseATR=true; ATRmultSL=2.0; StopLossPips=400; MaxSpr=30; Risk=0.5
    case "$tf" in
      M5) TrailStart=20; TrailGap=20; TrailStep=5 ;;
      M15) TrailStart=30; TrailGap=25; TrailStep=10 ;;
      M30) TrailStart=40; TrailGap=30; TrailStep=15 ;;
      H1) TrailStart=50; TrailGap=40; TrailStep=20 ;;
    esac
  elif [ "$kind" = "FX" ]; then
    UseATR=false; ATRmultSL=2.0; StopLossPips=40; MaxSpr=15; Risk=0.5
    case "$tf" in
      M5) TrailStart=20; TrailGap=20; TrailStep=5 ;;
      M15) TrailStart=25; TrailGap=20; TrailStep=8 ;;
      M30) TrailStart=30; TrailGap=25; TrailStep=10 ;;
      H1) TrailStart=35; TrailGap=30; TrailStep=12 ;;
    esac
  else
    # INDEX
    UseATR=true; ATRmultSL=2.5; StopLossPips=500; MaxSpr=60; Risk=0.5
    case "$tf" in
      M5) TrailStart=120; TrailGap=100; TrailStep=25 ;;
      M15) TrailStart=180; TrailGap=140; TrailStep=35 ;;
      M30) TrailStart=240; TrailGap=180; TrailStep=50 ;;
      H1) TrailStart=320; TrailGap=240; TrailStep=60 ;;
    esac
  fi

  cat > "$file" <<EOF
// MustiFX preset: $file
EnableBuy=true
EnableSell=false
UseWickTrap=true
UseMACD_RSI=true
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
SessionWindows=07:00-11:00;13:00-17:00
UseNewsFilter=true
BlockMinsBeforeNews=30
BlockMinsAfterNews=30
NewsTimesToday=13:30;15:00
Lots=0.10
UsePercentRisk=true
RiskPercent=${Risk}
MagicNumber=20250923
EOF
}

# Symbols and TFs
symbols_g="XAUUSD"
symbols_fx="EURUSD GBPUSD USDJPY"
symbols_idx="US30 NAS100"

tfs="M5 M15 M30 H1"

for s in $symbols_g; do
  for tf in $tfs; do
    write_set "sets/MustiFX_${s}_${tf}.set" GOLD "$tf"
  done
done

for s in $symbols_fx; do
  for tf in $tfs; do
    write_set "sets/MustiFX_${s}_${tf}.set" FX "$tf"
  done
done

for s in $symbols_idx; do
  for tf in $tfs; do
    write_set "sets/MustiFX_${s}_${tf}.set" INDEX "$tf"
  done
done

# list created
ls -l sets | sed -n '1,200p'

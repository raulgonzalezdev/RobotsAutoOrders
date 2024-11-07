#include <Trade\Trade.mqh>

class CTrailingStop {
private:
    CiSAR m_sar; // Indicador Parabolic SAR
    double m_step;
    double m_maximum;

public:
    CTrailingStop(double step = 0.02, double maximum = 0.2) : m_step(step), m_maximum(maximum) {
        m_sar.Create(_Symbol, PERIOD_CURRENT, m_step, m_maximum);
    }

    bool AjustarStopLoss() {
        if (!PositionSelect(_Symbol)) return false;

        double new_sl = NormalizeDouble(m_sar.Main(1), (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
        double pos_sl = PositionGetDouble(POSITION_SL);
        double base = (pos_sl == 0.0) ? PositionGetDouble(POSITION_PRICE_OPEN) : pos_sl;

        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && new_sl > base) {
            return PositionModify(PositionGetInteger(POSITION_TICKET), new_sl, 0);
        } else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && new_sl < base) {
            return PositionModify(PositionGetInteger(POSITION_TICKET), new_sl, 0);
        }
        return false;
    }
}; 
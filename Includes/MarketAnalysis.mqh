#include <Trade\Trade.mqh>

class CMarketAnalysis {
private:
    int fastMA_handle; // Handle para la media móvil rápida
    int slowMA_handle; // Handle para la media móvil lenta
    int FastMAPeriod; // Periodo de la media móvil rápida
    int SlowMAPeriod; // Periodo de la media móvil lenta

public:
    CMarketAnalysis(int fastPeriod = 50, int slowPeriod = 200) {
        FastMAPeriod = fastPeriod;
        SlowMAPeriod = slowPeriod;
        InitializeIndicators();
    }

    bool EsTendenciaAlcista();
    void InitializeIndicators();
};

void CMarketAnalysis::InitializeIndicators() {
    // Inicializar los indicadores de medias móviles
    fastMA_handle = iMA(_Symbol, PERIOD_CURRENT, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    slowMA_handle = iMA(_Symbol, PERIOD_CURRENT, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
}

bool CMarketAnalysis::EsTendenciaAlcista() {
    // Determinar si hay una tendencia alcista comparando las medias móviles
    double fastMA[1], slowMA[1];
    CopyBuffer(fastMA_handle, 0, 0, 1, fastMA);
    CopyBuffer(slowMA_handle, 0, 0, 1, slowMA);
    return fastMA[0] > slowMA[0];
}

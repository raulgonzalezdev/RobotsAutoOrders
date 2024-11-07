
#include "MarketAnalysis.mqh"
#include "RiskManager.mqh"
#include <Trade/Trade.mqh>
#include <Expert/Signal/SignalMA.mqh>
#include <Expert/Money/MoneySizeOptimized.mqh>

class CTradeManager {
private:
    CTrade trade; // Instancia para manejar operaciones de trading
    int magicNumber; // Número mágico para identificar operaciones
    datetime horaApertura; // Hora de apertura de la posición
    double precioBase; // Precio base de la operación
    double stopLossActual; // Stop Loss actual
    double takeProfitActual; // Take Profit actual

public:
    CTradeManager(int magic = 0) {
        magicNumber = magic;
        trade.SetExpertMagicNumber(magic);
    }

    // Declaraciones de funciones para manejar operaciones
    void OpenBuy(double lots);
    void OpenSell(double lots);
    void OpenBuyConStops(double lots, double sl, double tp);
    void OpenSellConStops(double lots, double sl, double tp);
    void CerrarPosicion();
    bool ExistePosicionActiva();
    bool IsBuyOrder();
    datetime GetHoraApertura() { return horaApertura; }
    void AjustarPrecioAlTick(double &precio);
    bool AbrirNuevaOperacion(CMarketAnalysis &marketAnalysis, CRiskManager &riskManager, bool useTrailingStop);
    void CerrarPosicionPorStopLoss();
    double CalcularStopLoss();
    double CalcularTakeProfit();

    // Añadido: Métodos para establecer la señal y el gestor de dinero
    void SetSignal(CSignalMA *signal) { /* Implementar lógica para establecer la señal */ }
    void SetMoneyManager(CMoneySizeOptimized *money) { /* Implementar lógica para establecer el gestor de dinero */ }
};

void CTradeManager::AjustarPrecioAlTick(double &precio) {
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    precio = NormalizeDouble(MathFloor(precio / tickSize) * tickSize, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

bool CTradeManager::AbrirNuevaOperacion(CMarketAnalysis &marketAnalysis, CRiskManager &riskManager, bool useTrailingStop) {
    double lots = riskManager.CalcularTamanoLotePorVolatilidad();
    if (marketAnalysis.EsTendenciaAlcista()) {
        if (useTrailingStop) {
            OpenBuy(lots); // Sin SL/TP
        } else {
            double sl = CalcularStopLoss();
            double tp = CalcularTakeProfit();
            OpenBuyConStops(lots, sl, tp); // Con SL/TP
        }
    } else {
        if (useTrailingStop) {
            OpenSell(lots); // Sin SL/TP
        } else {
            double sl = CalcularStopLoss();
            double tp = CalcularTakeProfit();
            OpenSellConStops(lots, sl, tp); // Con SL/TP
        }
    }
    return true;
}

void CTradeManager::CerrarPosicionPorStopLoss() {
    CerrarPosicion();
    horaApertura = TimeCurrent();
}

bool CTradeManager::ExistePosicionActiva() {
   return PositionSelect(_Symbol);
}

void CTradeManager::CerrarPosicion() {
    if (ExistePosicionActiva()) trade.PositionClose(_Symbol);
}

bool CTradeManager::IsBuyOrder() {
    if (ExistePosicionActiva()) return PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
    return false;
}

void CTradeManager::OpenBuy(double lots) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (trade.Buy(lots, _Symbol, ask, 0, 0)) {
        horaApertura = TimeCurrent();
    }
}

void CTradeManager::OpenSell(double lots) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if (trade.Sell(lots, _Symbol, bid, 0, 0)) {
        horaApertura = TimeCurrent();
    }
}

void CTradeManager::OpenBuyConStops(double lots, double sl, double tp) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (trade.Buy(lots, _Symbol, ask, sl, tp)) {
        horaApertura = TimeCurrent();
    }
}

void CTradeManager::OpenSellConStops(double lots, double sl, double tp) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if (trade.Sell(lots, _Symbol, bid, sl, tp)) {
        horaApertura = TimeCurrent();
    }
}

double CTradeManager::CalcularStopLoss() {
    // Implementa la lógica para calcular el Stop Loss
    return 0.0; // Ejemplo, ajusta según tu lógica
}

double CTradeManager::CalcularTakeProfit() {
    // Implementa la lógica para calcular el Take Profit
    return 0.0; // Ejemplo, ajusta según tu lógica
}

#include <Trade/Trade.mqh>

class CRiskManager {
private:
    double riskPercent; // Porcentaje del capital a arriesgar por operación
    bool fixedVolume; // Indica si se debe usar un volumen fijo
    double profitTarget; // Objetivo de ganancia para cerrar la posición
    int consecutiveWins; // Contador de ganancias consecutivas
    datetime horaUltimoStopLoss; // Hora del último cierre por Stop Loss
    datetime horaUltimaPausaPorGanancias; // Hora de la última pausa por ganancias

public:
    // Constructor para inicializar los parámetros de gestión de riesgos
    CRiskManager(double risk = 1.0, bool useFixedVolume = true, double target = 20.0) {
        riskPercent = risk;
        fixedVolume = useFixedVolume;
        profitTarget = target;
        consecutiveWins = 0;
    }

    // Calcula el tamaño del lote basado en la volatilidad del mercado
    double CalcularTamanoLotePorVolatilidad();

    // Valida si los niveles de Stop Loss y Take Profit son adecuados
    bool ValidarStops(double precio, double sl, double tp, bool isBuyOrder);

    // Registra el resultado de una operación y actualiza el contador de ganancias
    void RegistrarResultadoOperacion(double profit);

    // Verifica si la ganancia actual es mayor o igual al objetivo
    bool GananciaMayorIgualA(double target);

    // Verifica si la posición actual tiene beneficios
    bool PosicionConBeneficio();

    // Verifica si la posición está cerca del Stop Loss y la pérdida es aceptable
    bool PosicionCercaDeStopLossYPerdidaMenorA(double perdidaMaxima);

    // Devuelve la hora del último Stop Loss
    datetime GetHoraUltimoStopLoss() { return horaUltimoStopLoss; }

    // Devuelve la hora de la última pausa por ganancias
    datetime GetHoraUltimaPausaPorGanancias() { return horaUltimaPausaPorGanancias; }
};

double CRiskManager::CalcularTamanoLotePorVolatilidad() {
    if (fixedVolume) return 1.0; // Retorna un volumen fijo si está configurado
    double atr_values[1];
    int atr_handle = iATR(_Symbol, PERIOD_D1, 14); // Calcula el ATR para medir la volatilidad
    CopyBuffer(atr_handle, 0, 0, 1, atr_values);
    double atr = atr_values[0];
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (riskPercent / 100.0); // Calcula el monto a arriesgar
    double pipValue = atr * SymbolInfoDouble(_Symbol, SYMBOL_POINT); // Calcula el valor del pip
    double lotSize = riskAmount / pipValue; // Calcula el tamaño del lote
    return MathMax(MathMin(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)); // Asegura que el tamaño del lote esté dentro de los límites permitidos
}

bool CRiskManager::GananciaMayorIgualA(double target) {
    if (!PositionSelect(_Symbol)) return false; // Verifica si hay una posición activa
    return PositionGetDouble(POSITION_PROFIT) >= target; // Compara la ganancia actual con el objetivo
}

bool CRiskManager::PosicionConBeneficio() {
    if (!PositionSelect(_Symbol)) return false; // Verifica si hay una posición activa
    return PositionGetDouble(POSITION_PROFIT) > 0; // Verifica si la posición tiene beneficios
}

bool CRiskManager::PosicionCercaDeStopLossYPerdidaMenorA(double perdidaMaxima) {
    if (!PositionSelect(_Symbol)) return false; // Verifica si hay una posición activa
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double stopLoss = PositionGetDouble(POSITION_SL);
    // Verifica si la pérdida es menor a la máxima permitida y si el precio está cerca del Stop Loss
    return PositionGetDouble(POSITION_PROFIT) <= perdidaMaxima && MathAbs(currentPrice - stopLoss) <= 0.01 * PositionGetDouble(POSITION_PRICE_OPEN);
}

void CRiskManager::RegistrarResultadoOperacion(double profit) {
    if (profit > 0) consecutiveWins++; // Incrementa el contador de ganancias si hay beneficio
    else {
        consecutiveWins = 0; // Reinicia el contador si hay una pérdida
        horaUltimoStopLoss = TimeCurrent(); // Registra la hora del último Stop Loss
    }
}

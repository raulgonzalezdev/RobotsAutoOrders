#property copyright "Tu Nombre"
#property version   "2.0"
#property strict

#include <SQLite3/Include/SQLite3/SQLite3.mqh>
#include <Expert/Signal/SignalMA.mqh>
#include <Expert/Money/MoneySizeOptimized.mqh>

#include "Includes/DatabaseHandler.mqh"
#include "Includes/MarketAnalysis.mqh"
#include "Includes/RiskManager.mqh"
#include "Includes/TradeManager.mqh"
#include "Includes/TrailingStop.mqh"

// Instancias de las clases principales
CTradeManager tradeManager;
CMarketAnalysis marketAnalysis;
CRiskManager riskManager;
CTrailingStop trailingStop;

// Parámetros de entrada para la configuración del bot
input double RiskPercent = 1.0;             // Porcentaje del capital para arriesgar en cada operación
input int MagicNumber = 123456;             // Número mágico para identificar las operaciones
input double StopLossPercent = 2.0;         // Stop Loss en porcentaje del precio de compra o venta
input double TakeProfitPercent = 10.0;      // Take Profit en porcentaje del precio de compra o venta
input bool FixedVolume = true;              // Usar volumen fijo de 1 si es true, de lo contrario calcular
input double UmbralCercaniaSL = 0.2;        // Umbral de cercanía al SL en porcentaje (por ejemplo, 0.2%)
input double PerdidaMaxima = -100.0;        // Pérdida máxima para cerrar la posición (por ejemplo, -100)
input int PauseAfterStopLoss = 15;          // Tiempo de pausa en minutos después de cierre por Stop Loss
input bool AllowSellOrders = false;         // Permitir órdenes de venta en tendencias bajistas
input int MaxConsecutiveWins = 4;
input int PauseAfterWins = 15;
input double ProfitTarget = 20.0;           // Ganancia objetivo para cerrar la posición
input bool UseTrailingStop = false;         // Nuevo parámetro para seleccionar el uso de trailing stop
input int SignalMA_Period = 12;             // Periodo de la media móvil para SignalMA
input int SignalMA_Shift = 6;               // Desplazamiento de la media móvil para SignalMA
input ENUM_MA_METHOD SignalMA_Method = MODE_SMA; // Método de la media móvil para SignalMA
input ENUM_APPLIED_PRICE SignalMA_Applied = PRICE_CLOSE; // Precio aplicado para SignalMA
input double MoneySize_DecreaseFactor = 3.0; // Factor de disminución para MoneySizeOptimized
input double MoneySize_Percent = 10.0;       // Porcentaje para MoneySizeOptimized

int OnInit() {
    // Inicialización de las instancias de las clases con los parámetros de entrada
    tradeManager = CTradeManager(MagicNumber);
    marketAnalysis = CMarketAnalysis();
    riskManager = CRiskManager(RiskPercent, FixedVolume, ProfitTarget);
    trailingStop = CTrailingStop();

    if (UseTrailingStop) {
        // Inicializar SignalMA
        CSignalMA *signal = new CSignalMA();
        signal.PeriodMA(SignalMA_Period);
        signal.Shift(SignalMA_Shift);
        signal.Method(SignalMA_Method);
        signal.Applied(SignalMA_Applied);

        // Inicializar MoneySizeOptimized
        CMoneySizeOptimized *money = new CMoneySizeOptimized();
        money.DecreaseFactor(MoneySize_DecreaseFactor);
        money.Percent(MoneySize_Percent);

        // Asegúrate de que estas funciones existan en CTradeManager
        tradeManager.SetSignal(signal);
        tradeManager.SetMoneyManager(money);
    }

    // Inicialización de la base de datos SQLite
    InitSQLite();
    InitDatabase();
    return INIT_SUCCEEDED;
}

void OnTick() {
    // Verificar si existe una posición activa
    if (tradeManager.ExistePosicionActiva()) {
        if (UseTrailingStop) {
            // Ajustar el trailing stop si está habilitado
            trailingStop.AjustarStopLoss();
        }

        // Cerrar posición si la ganancia es mayor o igual al objetivo
        if (riskManager.GananciaMayorIgualA(ProfitTarget)) {
            tradeManager.CerrarPosicion();
            OrderData order;
            // Rellenar los datos de la orden
            order.symbol = _Symbol;
            order.ticket = PositionGetInteger(POSITION_TICKET);
            order.open_time = (datetime)PositionGetInteger(POSITION_TIME);
            order.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            order.volume = PositionGetDouble(POSITION_VOLUME);
            order.open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            order.stop_loss = PositionGetDouble(POSITION_SL);
            order.take_profit = PositionGetDouble(POSITION_TP);
            order.close_price = PositionGetDouble(POSITION_PRICE_CURRENT);
            order.profit = PositionGetDouble(POSITION_PROFIT);
            order.motivo = "Cierre por ganancia objetivo";
            RegistrarOrdenEnBD(order);
            return;
        }
        
        // Cerrar y abrir una nueva operación si la posición tiene beneficio después de una hora
        if (TimeCurrent() - tradeManager.GetHoraApertura() >= 3600 && riskManager.PosicionConBeneficio()) {
            tradeManager.CerrarPosicion();
            tradeManager.AbrirNuevaOperacion(marketAnalysis, riskManager, true); // Asegúrate de pasar el tercer parámetro
            OrderData order;
            // Rellenar los datos de la orden
            order.symbol = _Symbol;
            order.ticket = PositionGetInteger(POSITION_TICKET);
            order.open_time = (datetime)PositionGetInteger(POSITION_TIME);
            order.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            order.volume = PositionGetDouble(POSITION_VOLUME);
            order.open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            order.stop_loss = PositionGetDouble(POSITION_SL);
            order.take_profit = PositionGetDouble(POSITION_TP);
            order.close_price = PositionGetDouble(POSITION_PRICE_CURRENT);
            order.profit = PositionGetDouble(POSITION_PROFIT);
            order.motivo = "Cierre y reapertura por beneficio";
            RegistrarOrdenEnBD(order);
            return;
        }

        // Cerrar posición si está cerca del Stop Loss y la pérdida es menor a la máxima permitida
        if (riskManager.PosicionCercaDeStopLossYPerdidaMenorA(PerdidaMaxima)) {
            tradeManager.CerrarPosicionPorStopLoss();
            OrderData order;
            // Rellenar los datos de la orden
            order.symbol = _Symbol;
            order.ticket = PositionGetInteger(POSITION_TICKET);
            order.open_time = (datetime)PositionGetInteger(POSITION_TIME);
            order.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            order.volume = PositionGetDouble(POSITION_VOLUME);
            order.open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            order.stop_loss = PositionGetDouble(POSITION_SL);
            order.take_profit = PositionGetDouble(POSITION_TP);
            order.close_price = PositionGetDouble(POSITION_PRICE_CURRENT);
            order.profit = PositionGetDouble(POSITION_PROFIT);
            order.motivo = "Cierre por cercanía al Stop Loss";
            RegistrarOrdenEnBD(order);
            return;
        }
    } else {
        // Pausar después de un Stop Loss
        if (TimeCurrent() - riskManager.GetHoraUltimoStopLoss() < PauseAfterStopLoss * 60) return;

        // Pausar después de alcanzar el número máximo de ganancias consecutivas
        if (TimeCurrent() - riskManager.GetHoraUltimaPausaPorGanancias() < PauseAfterWins * 60) return;

        // Abrir una nueva operación si no hay posiciones activas
        tradeManager.AbrirNuevaOperacion(marketAnalysis, riskManager, UseTrailingStop); // Asegúrate de pasar el tercer parámetro
        OrderData order;
        // Rellenar los datos de la orden
        order.symbol = _Symbol;
        order.ticket = PositionGetInteger(POSITION_TICKET);
        order.open_time = (datetime)PositionGetInteger(POSITION_TIME);
        order.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        order.volume = PositionGetDouble(POSITION_VOLUME);
        order.open_price = PositionGetDouble(POSITION_PRICE_OPEN);
        order.stop_loss = PositionGetDouble(POSITION_SL);
        order.take_profit = PositionGetDouble(POSITION_TP);
        order.close_price = PositionGetDouble(POSITION_PRICE_CURRENT);
        order.profit = PositionGetDouble(POSITION_PROFIT);
        order.motivo = "Apertura de nueva operación";
        RegistrarOrdenEnBD(order);
    }
}

void OnDeinit(const int reason) {
    // Cerrar la conexión con SQLite al desinicializar
    ShutdownSQLite();
}

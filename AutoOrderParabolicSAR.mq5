//+------------------------------------------------------------------+
//|                   Bot de Orden Automática con Trailing SAR y Apertura Manual |
//+------------------------------------------------------------------+
#property copyright "Raul Gonzalez"
#property link      "gonzalezquijadaraulantonio@gmail.com"
#property version   "2.1"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// Parámetros de entrada
input double RiskPercent = 1.0;            // Porcentaje del capital para arriesgar en cada operación
input bool OrdenesSinSLTP = false;         // Crear órdenes con SL y TP a cero
input int MagicNumber = 11436207;          // Número mágico para identificar las operaciones
input double StopLossPercent = 2.0;        // Stop Loss en porcentaje del precio de compra o venta
input double ProfitEstimated = 20.0;       // Ganancia estimada para cerrar la posición
input double TakeProfitPercent = 10.0;     // Take Profit en porcentaje del precio de compra o venta
input bool FixedVolume = true;             // Usar volumen fijo de 1 si es true, de lo contrario calcular
input double UmbralCercaniaSL = 0.2;       // Umbral de cercanía al SL en porcentaje
input double PerdidaMaxima = -100.0;       // Pérdida máxima para cerrar la posición
input int PauseAfterStopLoss = 15;         // Tiempo de pausa en minutos después de cierre por Stop Loss
input bool AllowSellOrders = false;        // Permitir órdenes de venta en tendencias bajistas
input int MaxConsecutiveWins = 4;          // Número máximo de operaciones ganadoras consecutivas antes de pausar
input int PauseAfterWins = 15;             // Tiempo de pausa en minutos después de alcanzar el máximo de ganancias consecutivas
input double ParabolicStep = 0.02;         // Paso del Parabolic SAR para el trailing stop
input double ParabolicMax = 0.2;           // Máximo del Parabolic SAR para el trailing stop
input bool OpenOrdenManual = false;        // Activar apertura de orden manual
input string TipoOrdenManual = "SELL";     // Tipo de orden manual: "BUY" o "SELL"

// Variables de control
bool OrdenManual = false;                  // Variable para activar la apertura de orden manual
double precioBase = 0.0;
double stopLossActual = 0.0;
double takeProfitActual = 0.0;
double Lots = 1.0;
datetime horaApertura;
datetime horaUltimoStopLoss = 0;
int consecutiveWins = 0;
datetime horaUltimaPausaPorGanancias = 0;

// Manejador del Parabolic SAR
int sar_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Función de Inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   OrdenManual = OpenOrdenManual;
   trade.SetExpertMagicNumber(MagicNumber);
   Lots = FixedVolume ? 1.0 : CalcularTamañoLotePorVolatilidad();

   // Inicializar el Parabolic SAR
   sar_handle = iSAR(_Symbol, PERIOD_CURRENT, ParabolicStep, ParabolicMax);
   if (sar_handle == INVALID_HANDLE)
   {
      Print("Error al crear Parabolic SAR: ", GetLastError());
      return INIT_FAILED;
   }

   if(!ExistePosicionActiva())
   {
      AbrirOperacionSegunTendencia();
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Función OnTick: Se ejecuta en cada tick del mercado              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(IsNewBar())
   {
      TrailingStopBySAR(); // Activar trailing stop solo en una nueva barra
   }

   // Verificar si el usuario activó la apertura de una orden manual
   if(OpenOrdenManual && OrdenManual)
   {
      AbrirOrdenManual(TipoOrdenManual);
      OrdenManual = false;
   }

   if(ExistePosicionActiva())
   {
      if(GananciaMayorIgual())
      {
         Print("Ganancia alcanzada. Cerrando posición.");
         CerrarPosicion();
         AbrirOperacionSegunTendencia();
         return;
      }

      if(TimeCurrent() - horaApertura >= 3600 && PosicionConBeneficio())
      {
         Print("Posición con beneficio después de 1 hora. Cerrando posición.");
         CerrarPosicion();
         AbrirOperacionSegunTendencia();
         return;
      }

      if(PosicionCercaDeStopLossYPerdidaMenorA(PerdidaMaxima))
      {
         Print("Pérdida máxima alcanzada. Cerrando posición por Stop Loss.");
         CerrarPosicionPorStopLoss();
         return;
      }
   }
   else
   {
      if(TimeCurrent() - horaUltimoStopLoss < PauseAfterStopLoss * 60)
         return;

      if(TimeCurrent() - horaUltimaPausaPorGanancias < PauseAfterWins * 60)
         return;

      AbrirOperacionSegunTendencia();
   }
}

//+------------------------------------------------------------------+
//| Función para manejar transacciones comerciales                   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      TrailingStopBySAR(); // Activar trailing stop al abrir nueva posición
   }
}

//+------------------------------------------------------------------+
//| Función para obtener el valor de Parabolic SAR                   |
//+------------------------------------------------------------------+
double GetParabolicSARValue()
{
   double sar_values[];
   if(CopyBuffer(sar_handle, 0, 1, 1, sar_values) > 0)
   {
      return sar_values[0];
   }
   else
   {
      Print("Error al obtener datos de Parabolic SAR: ", GetLastError());
      return EMPTY_VALUE;
   }
}
//+------------------------------------------------------------------+
//| Función para trailing stop usando Parabolic SAR                  |
//+------------------------------------------------------------------+
void TrailingStopBySAR()
{
   double sar_value = GetParabolicSARValue();
   if(sar_value == EMPTY_VALUE)
   {
      Print("Error: Valor de Parabolic SAR no disponible.");
      return;
   }

   // Obtener el nivel mínimo de stops
   double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double pos_sl = PositionGetDouble(POSITION_SL);
         double pos_tp = PositionGetDouble(POSITION_TP);
         double pos_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double new_sl = sar_value;
         double currentPrice = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl_distance = fabs(new_sl - currentPrice);
         string symbol = PositionGetString(POSITION_SYMBOL);  // Obtener el símbolo como string

         // Mostrar información detallada para diagnóstico
         PrintFormat("Revisando posición %d: tipo=%s, SL actual=%.5f, SL nuevo=%.5f, TP=%.5f, precio actual=%.5f, distancia SL=%.5f, minStopLevel=%.5f",
                     ticket,
                     (pos_type == POSITION_TYPE_BUY) ? "BUY" : "SELL",
                     pos_sl,
                     new_sl,
                     pos_tp,
                     currentPrice,
                     sl_distance,
                     minStopLevel);

         // Verificar que el nuevo SL cumple con el nivel mínimo de stops y la lógica de trailing
         bool sl_valido = false;

         if(pos_type == POSITION_TYPE_BUY)
         {
            if(new_sl < pos_open_price && sl_distance > minStopLevel)
               sl_valido = true;
         }
         else if(pos_type == POSITION_TYPE_SELL)
         {
            if(new_sl > pos_open_price && sl_distance > minStopLevel)
               sl_valido = true;
         }

         // Intentar modificar el SL si cumple las condiciones
         if(sl_valido)
         {
            string symbol = PositionGetString(POSITION_SYMBOL);  // Obtener el símbolo como string
            if(trade.PositionModify(ticket, new_sl, pos_tp))
            {
               PrintFormat("Trailing Stop ajustado exitosamente a %.5f para el ticket %d", new_sl, ticket);
            }
            else
            {
               int error_code = GetLastError();
               PrintFormat("Error al modificar Stop Loss para ticket %d: Código de error %d (%s)", ticket, error_code);
            }
         }
         else
         {
            PrintFormat("El nuevo Stop Loss para el ticket %d no cumple con la distancia mínima permitida (distancia actual: %.5f, mínimo requerido: %.5f).", ticket, sl_distance, minStopLevel);
         }
      }
   }
}


//+------------------------------------------------------------------+
//| Función para abrir posición de compra usando Parabolic SAR       |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sar_value = GetParabolicSARValue();

   if(sar_value == EMPTY_VALUE) {
      Print("Error al obtener el valor del Parabolic SAR para OpenBuy.");
      return;
   }

   precioBase = Ask;

   // Configurar Stop Loss usando el valor del SAR
   if(OrdenesSinSLTP)
   {
      stopLossActual = 0.0;
      takeProfitActual = 0.0;
   }
   else
   {
      stopLossActual = sar_value < Ask ? sar_value : Ask - (StopLossPercent / 100.0) * Ask;
      takeProfitActual = Ask + (TakeProfitPercent / 100.0) * Ask;

      // Verificación de niveles mínimos de SL y TP
      if(!ValidarStops(Ask, stopLossActual, takeProfitActual, true))
      {
         Print("Error: Los niveles de SL o TP no cumplen los requisitos mínimos para OpenBuy.");
         return;
      }
   }

   if(trade.Buy(Lots, _Symbol, Ask, stopLossActual, takeProfitActual, "Compra con Parabolic SAR"))
   {
      horaApertura = TimeCurrent();
      PrintFormat("Orden de compra abierta: Precio=%.2f, SL=%.2f, TP=%.2f", Ask, stopLossActual, takeProfitActual);
   }
   else
   {
      PrintFormat("Error al abrir orden de compra: %d", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Función para abrir posición de venta usando Parabolic SAR        |
//+------------------------------------------------------------------+
void OpenSell()
{
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sar_value = GetParabolicSARValue();

   if(sar_value == EMPTY_VALUE) {
      Print("Error al obtener el valor del Parabolic SAR para OpenSell.");
      return;
   }

   precioBase = Bid;

   // Configurar Stop Loss usando el valor del SAR
   if(OrdenesSinSLTP)
   {
      stopLossActual = 0.0;
      takeProfitActual = 0.0;
   }
   else
   {
      stopLossActual = sar_value > Bid ? sar_value : Bid + (StopLossPercent / 100.0) * Bid;
      takeProfitActual = Bid - (TakeProfitPercent / 100.0) * Bid;

      // Verificación de niveles mínimos de SL y TP
      if(!ValidarStops(Bid, stopLossActual, takeProfitActual, false))
      {
         Print("Error: Los niveles de SL o TP no cumplen los requisitos mínimos para OpenSell.");
         return;
      }
   }

   if(trade.Sell(Lots, _Symbol, Bid, stopLossActual, takeProfitActual, "Venta con Parabolic SAR"))
   {
      horaApertura = TimeCurrent();
      PrintFormat("Orden de venta abierta: Precio=%.2f, SL=%.2f, TP=%.2f", Bid, stopLossActual, takeProfitActual);
   }
   else
   {
      PrintFormat("Error al abrir orden de venta: %d", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Función para validar los niveles de SL y TP                      |
//+------------------------------------------------------------------+
bool ValidarStops(double precio, double sl, double tp, bool isBuyOrder)
{
   long minStopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDistance = minStopsLevel * point;

   // Ajuste si el minStopsLevel es demasiado bajo
   if(minDistance < point)
      minDistance = point;

   // Validar que la distancia entre el precio y SL/TP cumple con los requisitos mínimos
   bool sl_valid = fabs(precio - sl) >= minDistance;
   bool tp_valid = fabs(precio - tp) >= minDistance;

   // Mensajes de error en caso de validación fallida
   if(!sl_valid)
      PrintFormat("Error: La distancia entre el precio y el Stop Loss es menor que el mínimo permitido (%.2f)", minDistance);
   if(!tp_valid)
      PrintFormat("Error: La distancia entre el precio y el Take Profit es menor que el mínimo permitido (%.2f)", minDistance);

   // Validar lógica de SL y TP según el tipo de orden
   if(isBuyOrder && (sl >= precio || tp <= precio))
   {
      Print("Error: SL o TP incorrectos para una orden de compra.");
      return false;
   }
   else if(!isBuyOrder && (sl <= precio || tp >= precio))
   {
      Print("Error: SL o TP incorrectos para una orden de venta.");
      return false;
   }

   return sl_valid && tp_valid;
}

//+------------------------------------------------------------------+
//| Función para calcular el tamaño de lote según la volatilidad     |
//+------------------------------------------------------------------+
double CalcularTamañoLotePorVolatilidad()
{
   int atr_handle = iATR(_Symbol, PERIOD_D1, 14);
   double atr_values[];
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_values) <= 0)
   {
      Print("Error al copiar datos del ATR: ", GetLastError());
      return Lots;
   }
   double atr = atr_values[0];
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   double pipValue = atr * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double lotSize = riskAmount / pipValue;
   return MathMax(MathMin(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
}

//+------------------------------------------------------------------+
//| Función para verificar si existe una posición activa             |
//+------------------------------------------------------------------+
bool ExistePosicionActiva()
{
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
   {
      horaApertura = (datetime)PositionGetInteger(POSITION_TIME);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Función para verificar si es una nueva barra                     |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime last_bar_time = 0;
   datetime array[1];  // Array para almacenar la hora de apertura de la última barra

   // Obtener la hora de la barra actual
   if(CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, array) > 0)
   {
      datetime current_bar_time = array[0];
      if(current_bar_time != last_bar_time)
      {
         last_bar_time = current_bar_time;
         return true;
      }
   }
   return false;
}


//+------------------------------------------------------------------+
//| Función para abrir operaciones según la tendencia                |
//+------------------------------------------------------------------+
void AbrirOperacionSegunTendencia()
{
   Lots = FixedVolume ? 1.0 : CalcularTamañoLotePorVolatilidad();

   if(EsTendenciaAlcista())
      OpenBuy();
   else if(AllowSellOrders)
      OpenSell();
}

//+------------------------------------------------------------------+
//| Función para determinar si hay ganancia mayor o igual a estimada |
//+------------------------------------------------------------------+
bool GananciaMayorIgual()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit >= ProfitEstimated)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Función para cerrar posición abierta                             |
//+------------------------------------------------------------------+
void CerrarPosicion()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         if(trade.PositionClose(ticket))
         {
            Print("Posición cerrada: Ticket=", ticket);
         }
         else
         {
            Print("Error al cerrar posición: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Función para cerrar posición por Stop Loss y registrar la hora   |
//+------------------------------------------------------------------+
void CerrarPosicionPorStopLoss()
{
   CerrarPosicion();
   horaUltimoStopLoss = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Función para verificar si la posición tiene beneficio positivo   |
//+------------------------------------------------------------------+
bool PosicionConBeneficio()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit > 0)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Función para verificar si posición cerca de SL con pérdida menor |
//+------------------------------------------------------------------+
bool PosicionCercaDeStopLossYPerdidaMenorA(double perdidaMaxima)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         double sl = PositionGetDouble(POSITION_SL);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double distanciaSL = fabs(currentPrice - sl);
         double umbralCercania = (UmbralCercaniaSL / 100.0) * currentPrice;

         if(distanciaSL <= umbralCercania && profit <= perdidaMaxima)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Función para determinar la tendencia del mercado                 |
//+------------------------------------------------------------------+
bool EsTendenciaAlcista()
{
   int fastMA_handle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
   int slowMA_handle = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);
   double fastMA[1], slowMA[1];

   // Copiar el valor más reciente de cada media móvil
   if(CopyBuffer(fastMA_handle, 0, 0, 1, fastMA) > 0 && CopyBuffer(slowMA_handle, 0, 0, 1, slowMA) > 0)
   {
      return fastMA[0] > slowMA[0];
   }
   return false;
}

//+------------------------------------------------------------------+
//| Función para abrir orden manual                                  |
//+------------------------------------------------------------------+
void AbrirOrdenManual(string tipoOrden)
{
   Lots = FixedVolume ? 1.0 : CalcularTamañoLotePorVolatilidad();

   if(tipoOrden == "BUY")
      OpenBuy();
   else if(tipoOrden == "SELL")
      OpenSell();
   else
      Print("Tipo de orden no reconocido: ", tipoOrden);
}

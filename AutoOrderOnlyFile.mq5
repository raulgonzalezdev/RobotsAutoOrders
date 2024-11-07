//+------------------------------------------------------------------+
//|                   Bot de Orden Simple Automática                 |
//+------------------------------------------------------------------+
#property copyright "Raul Gonzalez"
#property link      "gonzalezquijadaraulantonio@gmail.com"
#property version   "1.9"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// Parámetros de entrada
input double RiskPercent = 1.0;             // Porcentaje del capital para arriesgar en cada operación
input bool OrdenesSinSLTP = false;          // Crear órdenes con SL y TP a cero
input int MagicNumber = 11436207;             // Número mágico para identificar las operaciones
input double StopLossPercent = 2.0;         // Stop Loss en porcentaje del precio de compra o venta
input double ProfitEstimated = 20.0;      // Ganancia estimada para cerrar la posición
input double TakeProfitPercent = 10.0;      // Take Profit en porcentaje del precio de compra o venta
input bool FixedVolume = true;              // Usar volumen fijo de 1 si es true, de lo contrario calcular
input double UmbralCercaniaSL = 0.2;        // Umbral de cercanía al SL en porcentaje (por ejemplo, 0.2%)
input double PerdidaMaxima = -100.0;        // Pérdida máxima para cerrar la posición (por ejemplo, -100)
input int PauseAfterStopLoss = 15;          // Tiempo de pausa en minutos después de cierre por Stop Loss
input bool AllowSellOrders = false;         // Permitir órdenes de venta en tendencias bajistas
input int MaxConsecutiveWins = 4;           // Número máximo de operaciones ganadoras consecutivas antes de pausar
input int PauseAfterWins = 15;              // Tiempo de pausa en minutos después de alcanzar el máximo de ganancias consecutivas


// Variables de control
double precioBase = 0.0;                    // Precio base para cálculos de SL y TP
double stopLossActual = 0.0;
double takeProfitActual = 0.0;
double Lots = 1.0;                          // Tamaño del lote calculado dinámicamente o fijo
datetime horaApertura;                      // Hora de apertura de la operación actual
datetime horaUltimoStopLoss = 0;            // Hora del último cierre por Stop Loss
int consecutiveWins = 0;                    // Contador de operaciones ganadoras consecutivas
datetime horaUltimaPausaPorGanancias = 0;   // Hora en que comenzó la última pausa por ganancias

// Variables para análisis de tendencia
int FastMAPeriod = 50;                      // Periodo de la media móvil rápida
int SlowMAPeriod = 200;                     // Periodo de la media móvil lenta

// Manejadores de los indicadores de media móvil
int fastMA_handle;
int slowMA_handle;

//+------------------------------------------------------------------+
//| Función de Inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   // Establecer el número mágico para las operaciones
   trade.SetExpertMagicNumber(MagicNumber);
   Lots = FixedVolume ? 1.0 : CalcularTamañoLotePorVolatilidad();  // Asignar volumen fijo o calculado

   // Inicializar los indicadores de media móvil
   fastMA_handle = iMA(_Symbol, PERIOD_CURRENT, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowMA_handle = iMA(_Symbol, PERIOD_CURRENT, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(fastMA_handle == INVALID_HANDLE || slowMA_handle == INVALID_HANDLE)
   {
      Print("Error al crear indicadores de media móvil: ", GetLastError());
      return INIT_FAILED;
   }

   // Verificar si ya existe una posición activa
   if(!ExistePosicionActiva())
   {
      AbrirNuevaOperacion();
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Función OnTick: Se ejecuta en cada tick del mercado              |
//+------------------------------------------------------------------+
void OnTick()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ExistePosicionActiva())
   {
      if(GananciaMayorIgual())
      {
         Print("Ganancia >= 20 detectada. Cerrando posición.");
         CerrarPosicion();
         AbrirNuevaOperacion();
         return;
      }

      if(TimeCurrent() - horaApertura >= 3600 && PosicionConBeneficio())
      {
         Print("Posición con beneficio después de 1 hora. Cerrando posición.");
         CerrarPosicion();
         AbrirNuevaOperacion();
         return;
      }

      if(PosicionCercaDeStopLossYPerdidaMenorA(PerdidaMaxima))
      {
         CerrarPosicionPorStopLoss();
         return;
      }

      if((IsBuyOrder() && (currentPrice >= takeProfitActual || currentPrice <= stopLossActual)) ||
         (!IsBuyOrder() && (currentPrice <= takeProfitActual || currentPrice >= stopLossActual)))
      {
         Print("Take Profit o Stop Loss alcanzado. Cerrando posición.");
         CerrarPosicion();
         AbrirNuevaOperacion();
      }
   }
   else
   {
      // Verificar si estamos en pausa después de un Stop Loss
      if(TimeCurrent() - horaUltimoStopLoss < PauseAfterStopLoss * 60)
      {
         // Estamos en pausa, no abrir nuevas operaciones
         return;
      }

      // Verificar si estamos en pausa después de alcanzar el número máximo de ganancias consecutivas
      if(TimeCurrent() - horaUltimaPausaPorGanancias < PauseAfterWins * 60)
      {
         // Estamos en pausa, no abrir nuevas operaciones
         PrintFormat("En pausa por ganancias consecutivas. Restan %d segundos.", PauseAfterWins * 60 - (TimeCurrent() - horaUltimaPausaPorGanancias));
         return;
      }

      // Si no hay posición activa, intentar abrir una nueva
      AbrirNuevaOperacion();
   }
}

//+------------------------------------------------------------------+
//| Función para ajustar el precio al múltiplo de tick más cercano   |
//+------------------------------------------------------------------+
double AjustarPrecioAlTick(double precio)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0)
      tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);  // Usar el tamaño de punto si el tamaño de tick es cero

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   return NormalizeDouble(MathFloor(precio / tickSize) * tickSize, digits);
}

//+------------------------------------------------------------------+
//| Función para verificar si la posición está cerca del SL y con    |
//| pérdida menor o igual a una pérdida máxima especificada          |
//+------------------------------------------------------------------+
bool PosicionCercaDeStopLossYPerdidaMenorA(double perdidaMaxima)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelect(i))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double sl = PositionGetDouble(POSITION_SL);
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double distanciaSL = fabs(currentPrice - sl);
            double umbralCercania = (UmbralCercaniaSL / 100.0) * currentPrice; // Umbral de cercanía en precio

            double profit = PositionGetDouble(POSITION_PROFIT);

            if(distanciaSL <= umbralCercania && profit <= perdidaMaxima)
            {
               PrintFormat("Posición cerca del Stop Loss (distancia: %.2f), pérdida actual: %.2f, superando la pérdida máxima permitida: %.2f", distanciaSL, profit, perdidaMaxima);
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Función para abrir una nueva operación                           |
//+------------------------------------------------------------------+
void AbrirNuevaOperacion()
{
   trade.SetExpertMagicNumber(MagicNumber);  // Asegurar que el MagicNumber se establece

   // Verificar si estamos en pausa después de alcanzar el número máximo de ganancias consecutivas
   if(TimeCurrent() - horaUltimaPausaPorGanancias < PauseAfterWins * 60)
   {
      // Estamos en pausa, no abrir nuevas operaciones
      PrintFormat("En pausa por ganancias consecutivas. Restan %d segundos.", PauseAfterWins * 60 - (TimeCurrent() - horaUltimaPausaPorGanancias));
      return;
   }

   Lots = FixedVolume ? 1.0 : CalcularTamañoLotePorVolatilidad();  // Recalcular el lote si es necesario

   // Determinar la tendencia del mercado
   bool esTendenciaAlcista = EsTendenciaAlcista();

   if(esTendenciaAlcista)
   {
      OpenBuy();
   }
   else
   {
      if(AllowSellOrders)
      {
         OpenSell();
      }
      else
      {
         // Si no se permiten órdenes de venta, esperar hasta que la tendencia sea alcista
         Print("Tendencia bajista detectada y las órdenes de venta están deshabilitadas. Esperando tendencia alcista.");
         // Si hubo un cierre por Stop Loss recientemente, aplicar pausa de 15 minutos
         if(TimeCurrent() - horaUltimoStopLoss < PauseAfterStopLoss * 60)
         {
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Función para validar SL y TP                                     |
//+------------------------------------------------------------------+
bool ValidarStops(double precio, double sl, double tp, bool isBuyOrder)
{
   long minStopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double minDistance = minStopsLevel * point;
   if(minDistance < point)
      minDistance = point;

   bool sl_valid = fabs(precio - sl) >= minDistance;
   bool tp_valid = fabs(precio - tp) >= minDistance;

   if(!sl_valid)
   {
      PrintFormat("Error: La distancia entre el precio y el Stop Loss es menor que la mínima permitida (%f)", minDistance);
   }
   if(!tp_valid)
   {
      PrintFormat("Error: La distancia entre el precio y el Take Profit es menor que la mínima permitida (%f)", minDistance);
   }

   // Verificar que SL y TP tengan sentido lógico
   if(isBuyOrder)
   {
      if(sl >= precio || tp <= precio)
      {
         Print("Error: SL o TP incorrectos para una orden de compra.");
         return false;
      }
   }
   else
   {
      if(sl <= precio || tp >= precio)
      {
         Print("Error: SL o TP incorrectos para una orden de venta.");
         return false;
      }
   }

   return sl_valid && tp_valid;
}

//+------------------------------------------------------------------+
//| Función para abrir posición de compra                            |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(Ask == 0)
      return;

   precioBase = Ask;
   double sl_distance = (StopLossPercent / 100.0) * Ask;
   double tp_distance = (TakeProfitPercent / 100.0) * Ask;

   // Obtener la distancia mínima permitida por el broker
   long minStopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double minDistance = minStopsLevel * point;
   if(minDistance < point)
      minDistance = point;

   // Asegurar que la distancia SL cumple con la mínima
   if(sl_distance < minDistance)
   {
      PrintFormat("La distancia SL calculada es menor que la mínima permitida. Ajustando de %f a %f", sl_distance, minDistance);
      sl_distance = minDistance;
   }

   // Asegurar que la distancia TP cumple con la mínima
   if(tp_distance < minDistance)
   {
      PrintFormat("La distancia TP calculada es menor que la mínima permitida. Ajustando de %f a %f", tp_distance, minDistance);
      tp_distance = minDistance;
   }

   if (OrdenesSinSLTP)
   {
      stopLossActual = 0.0;
      takeProfitActual = 0.0;
   }
   else
   {
      stopLossActual = AjustarPrecioAlTick(Ask - sl_distance);
      takeProfitActual = AjustarPrecioAlTick(Ask + tp_distance);

      if(!ValidarStops(Ask, stopLossActual, takeProfitActual, true))
      {
         Print("Error: SL o TP inválidos para orden de compra.");
         return;
      }
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if(!trade.Buy(Lots, _Symbol, Ask, stopLossActual, takeProfitActual, "Compra Simple"))
   {
      Print("Error al abrir compra: ", GetLastError());
   }
   else
   {
      horaApertura = TimeCurrent();
      PrintFormat("Orden de compra abierta: Precio Inicial: %.2f, Stop Loss: %.2f, Take Profit: %.2f", precioBase, stopLossActual, takeProfitActual);
   }
}

//+------------------------------------------------------------------+
//| Función para abrir posición de venta                             |
//+------------------------------------------------------------------+
void OpenSell()
{
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(Bid == 0)
      return;

   precioBase = Bid;
   double sl_distance = (StopLossPercent / 100.0) * Bid;
   double tp_distance = (TakeProfitPercent / 100.0) * Bid;

   // Obtener la distancia mínima permitida por el broker
   long minStopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double minDistance = minStopsLevel * point;
   if(minDistance < point)
      minDistance = point;

   // Asegurar que la distancia SL cumple con la mínima
   if(sl_distance < minDistance)
   {
      PrintFormat("La distancia SL calculada es menor que la mínima permitida. Ajustando de %f a %f", sl_distance, minDistance);
      sl_distance = minDistance;
   }

   // Asegurar que la distancia TP cumple con la mínima
   if(tp_distance < minDistance)
   {
      PrintFormat("La distancia TP calculada es menor que la mínima permitida. Ajustando de %f a %f", tp_distance, minDistance);
      tp_distance = minDistance;
   }

   if (OrdenesSinSLTP)
   {
      stopLossActual = 0.0;
      takeProfitActual = 0.0;
   }
   else
   {
      stopLossActual = AjustarPrecioAlTick(Bid + sl_distance);
      takeProfitActual = AjustarPrecioAlTick(Bid - tp_distance);

      if(!ValidarStops(Bid, stopLossActual, takeProfitActual, false))
      {
         Print("Error: SL o TP inválidos para orden de venta.");
         return;
      }
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if(!trade.Sell(Lots, _Symbol, Bid, stopLossActual, takeProfitActual, "Venta Simple"))
   {
      Print("Error al abrir venta: ", GetLastError());
   }
   else
   {
      horaApertura = TimeCurrent();
      PrintFormat("Orden de venta abierta: Precio Inicial: %.2f, Stop Loss: %.2f, Take Profit: %.2f", precioBase, stopLossActual, takeProfitActual);
   }
}

//+------------------------------------------------------------------+
//| Función para cerrar posición abierta                             |
//+------------------------------------------------------------------+
void CerrarPosicion()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelect(i))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            double profit = PositionGetDouble(POSITION_PROFIT);

            if(trade.PositionClose(ticket))
            {
               Print("Posición cerrada: Ticket=", ticket);
               RegistrarResultadoOperacion(profit);
            }
            else
            {
               Print("Error al cerrar posición: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Función para registrar el resultado de la operación              |
//+------------------------------------------------------------------+
void RegistrarResultadoOperacion(double profit)
{
   if(profit > 0)
   {
      consecutiveWins++;
      PrintFormat("Operación ganadora. Ganancias consecutivas: %d", consecutiveWins);

      if(consecutiveWins >= MaxConsecutiveWins)
      {
         horaUltimaPausaPorGanancias = TimeCurrent();
         PrintFormat("Alcanzadas %d ganancias consecutivas. Pausando operaciones por %d minutos.", MaxConsecutiveWins, PauseAfterWins);
         consecutiveWins = 0; // Reiniciar el contador
      }
   }
   else
   {
      consecutiveWins = 0; // Reiniciar el contador si hubo pérdida
      Print("Operación perdedora. Contador de ganancias consecutivas reiniciado.");
   }
}

//+------------------------------------------------------------------+
//| Función para cerrar posición por Stop Loss y registrar la hora   |
//+------------------------------------------------------------------+
void CerrarPosicionPorStopLoss()
{
   Print("Cerrando posición anticipadamente debido a pérdida y cercanía al Stop Loss.");
   CerrarPosicion();
   horaUltimoStopLoss = TimeCurrent();  // Registrar la hora del cierre por Stop Loss
}

//+------------------------------------------------------------------+
//| Función para verificar si alguna posición tiene ganancia >= 20   |
//+------------------------------------------------------------------+
bool GananciaMayorIgual()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelect(i))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            Print("Ganancia actual de la posición: ", profit);
            if(profit >= ProfitEstimated)
            {
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Función para calcular el tamaño de lote según la volatilidad     |
//+------------------------------------------------------------------+
double CalcularTamañoLotePorVolatilidad()
{
   if(FixedVolume)
      return 1.0;  // Si FixedVolume es verdadero, devolver 1 directamente

   int atr_handle = iATR(_Symbol, PERIOD_D1, 14);
   if(atr_handle == INVALID_HANDLE)
   {
      Print("Error al crear el ATR: ", GetLastError());
      return Lots;
   }

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

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lotSize = MathMax(MathMin(lotSize, maxLot), minLot);

   return lotSize;
}

//+------------------------------------------------------------------+
//| Función para verificar si la posición tiene beneficio positivo   |
//+------------------------------------------------------------------+
bool PosicionConBeneficio()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelect(i))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit > 0)
            {
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Función para verificar si existe una posición activa             |
//+------------------------------------------------------------------+
bool ExistePosicionActiva()
{
   int totalPositions = PositionsTotal();
   PrintFormat("Total de posiciones abiertas: %d", totalPositions);

   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string symbol = PositionGetString(POSITION_SYMBOL);

         // Imprimir el símbolo de la posición
         PrintFormat("Revisando posición: Ticket=%d, Símbolo=%s", ticket, symbol);

         if(symbol == _Symbol)
         {
            horaApertura = (datetime)PositionGetInteger(POSITION_TIME);
            PrintFormat("Posición activa encontrada: Ticket=%d, Símbolo=%s, Hora de apertura=%s", ticket, symbol, TimeToString(horaApertura));
            return true;
         }
      }
      else
      {
         PrintFormat("No se pudo seleccionar la posición con Ticket=%d", ticket);
      }
   }

   Print("No se encontró ninguna posición activa con el símbolo especificado.");
   return false;
}

//+------------------------------------------------------------------+
//| Función para determinar si es una orden de compra                |
//+------------------------------------------------------------------+
bool IsBuyOrder()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelect(i))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            return (type == POSITION_TYPE_BUY);
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
   double fastMA[], slowMA[];
   if(CopyBuffer(fastMA_handle, 0, 0, 1, fastMA) <= 0 || CopyBuffer(slowMA_handle, 0, 0, 1, slowMA) <= 0)
   {
      Print("Error al copiar datos de medias móviles: ", GetLastError());
      return true;  // Por defecto, consideramos tendencia alcista si hay error
   }

   // Comparar las medias móviles
   return fastMA[0] > slowMA[0];
}

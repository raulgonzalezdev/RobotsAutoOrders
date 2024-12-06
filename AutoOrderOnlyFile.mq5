//+------------------------------------------------------------------+ 
//|               Bot Mejorado para Gestión de Tendencias            |
//+------------------------------------------------------------------+
#property copyright "Raul Gonzalez"
#property link      "gonzalezquijadaraulantonio@gmail.com"
#property version   "2.1"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// Parámetros de entrada
input double RiskPercent = 0.01;             // Porcentaje del capital para arriesgar en cada operación
input bool OrdenesSinSLTP = true;            // Crear órdenes con SL y TP a cero
input int MagicNumber = 11436207;            // Número mágico para identificar las operaciones
input double StopLossPercent = 1.0;          // Stop Loss en porcentaje del precio de compra o venta
input double ProfitEstimated = 0.25;         // Ganancia estimada para cerrar la posición
input double TakeProfitPercent = 2.0;        // Take Profit en porcentaje del precio de compra o venta
input bool FixedVolume = false;              // Usar volumen fijo de 1 si es true, de lo contrario calcular
input double UmbralCercaniaSL = 0.2;         // Umbral de cercanía al SL en porcentaje (por ejemplo, 0.2%)
input double PerdidaMaxima = -3.0;           // Pérdida máxima para cerrar la posición (no se usará en este caso)
input int PauseAfterStopLoss = 5;            // Tiempo de pausa en minutos después de cierre por Stop Loss
input bool AllowSellOrders = true;           // Permitir órdenes de venta en tendencias bajistas
input int MaxConsecutiveWins = 10;           // Número máximo de operaciones ganadoras consecutivas antes de pausar
input int PauseAfterWins = 5;                // Tiempo de pausa en minutos después de alcanzar el máximo de ganancias consecutivas
input int MaxOpenTime = 7200;                // Tiempo máximo en segundos que una posición puede estar abierta antes de abrir una contraria (por ejemplo, 2 horas)

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

   // Determinar la tendencia actual
   bool esTendenciaAlcista = EsTendenciaAlcista();

   if(ExistePosicionActiva())
   {
      AjustarStopLossDinamico(); // Ajustar SL dinámico de la posición existente

      // Verificar si se ha alcanzado la ganancia estimada
      if(GananciaMayorIgual())
      {
         Print("Ganancia >= ", ProfitEstimated, " detectada. Cerrando posición.");
         CerrarPosicion();
         AbrirNuevaOperacion();
         return;
      }

      // Verificar si la posición ha estado abierta por mucho tiempo
      if(TimeCurrent() - horaApertura >= MaxOpenTime)
      {
         // Verificar si ya existe una posición contraria
         if(!ExistePosicionContraria())
         {
            CrearOrdenContraria(esTendenciaAlcista);
         }
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
//| Función para abrir una nueva operación                           |
//+------------------------------------------------------------------+
void AbrirNuevaOperacion()
{
   if(ExistePosicionActiva())
   {
      Print("Ya existe una posición activa. No se abre una nueva operación.");
      return;
   }
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

   if (OrdenesSinSLTP)
   {
      stopLossActual = 0.0;
      takeProfitActual = 0.0;
   }
   else
   {
      stopLossActual = AjustarPrecioAlTick(Ask - sl_distance); // SL por debajo del precio de compra
      takeProfitActual = AjustarPrecioAlTick(Ask + tp_distance); // TP por encima del precio de compra
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if(!trade.Buy(Lots, _Symbol, Ask, stopLossActual, takeProfitActual, "Compra Simple"))
   {
      PrintFormat("Error al abrir compra: %d, SL=%.2f, TP=%.2f", GetLastError(), stopLossActual, takeProfitActual);
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

   if (OrdenesSinSLTP)
   {
      stopLossActual = 0.0;
      takeProfitActual = 0.0;
   }
   else
   {
      stopLossActual = AjustarPrecioAlTick(Bid + sl_distance); // SL por encima del precio de venta
      takeProfitActual = AjustarPrecioAlTick(Bid - tp_distance); // TP por debajo del precio de venta
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if(!trade.Sell(Lots, _Symbol, Bid, stopLossActual, takeProfitActual, "Venta Simple"))
   {
      PrintFormat("Error al abrir venta: %d, SL=%.2f, TP=%.2f", GetLastError(), stopLossActual, takeProfitActual);
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
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
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
//| Función para verificar si alguna posición tiene ganancia >= ProfitEstimated |
//+------------------------------------------------------------------+
bool GananciaMayorIgual()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
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
   Print("No hay ganancia suficiente");
   return false; // Devuelve false si no hay ganancia suficiente
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
//| Función para verificar si existe una posición activa             |
//+------------------------------------------------------------------+
bool ExistePosicionActiva()
{
   for(int i = PositionsTotal() -1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            horaApertura = (datetime)PositionGetInteger(POSITION_TIME);
            PrintFormat("Posición activa encontrada: Símbolo=%s, Hora de apertura=%s", _Symbol, TimeToString(horaApertura));
            return true;
         }
      }
   }
   PrintFormat("No se encontró ninguna posición activa con el símbolo: %s", _Symbol);
   return false;
}

//+------------------------------------------------------------------+
//| Función para determinar si es una orden de compra                |
//+------------------------------------------------------------------+
bool IsBuyOrder()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
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

//+------------------------------------------------------------------+
//| Ajustar Stop Loss dinámico solo para la orden existente          |
//+------------------------------------------------------------------+
void AjustarStopLossDinamico()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double precioActual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            double nuevoSL = (tipo == POSITION_TYPE_BUY)
                                ? precioActual - (StopLossPercent / 100.0) * precioActual
                                : precioActual + (StopLossPercent / 100.0) * precioActual;

            nuevoSL = AjustarPrecioAlTick(nuevoSL);

            if (!trade.PositionModify(ticket, nuevoSL, PositionGetDouble(POSITION_TP)))
            {
               Print("Error al modificar SL: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Crear nueva orden contraria sin cerrar la original               |
//+------------------------------------------------------------------+
void CrearOrdenContraria(bool esTendenciaAlcista)
{
   double precio = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl_distance = (StopLossPercent / 100.0) * precio;
   double tp_distance = (TakeProfitPercent / 100.0) * precio;

   double stopLoss, takeProfit;

   if (OrdenesSinSLTP)
   {
      stopLoss = 0.0;
      takeProfit = 0.0;
   }
   else
   {
      if(esTendenciaAlcista)
      {
         stopLoss = AjustarPrecioAlTick(precio - sl_distance); // SL para compra
         takeProfit = AjustarPrecioAlTick(precio + tp_distance); // TP para compra
      }
      else
      {
         stopLoss = AjustarPrecioAlTick(precio + sl_distance); // SL para venta
         takeProfit = AjustarPrecioAlTick(precio - tp_distance); // TP para venta
      }
   }

   trade.SetExpertMagicNumber(MagicNumber);

   if (esTendenciaAlcista)
   {
      if(!trade.Buy(Lots, _Symbol, precio, stopLoss, takeProfit, "Compra Contraria"))
      {
         Print("Error al abrir posición de compra contraria: ", GetLastError());
      }
      else
      {
         Print("Nueva posición de compra contraria abierta sin cerrar la original.");
      }
   }
   else
   {
      if(!trade.Sell(Lots, _Symbol, precio, stopLoss, takeProfit, "Venta Contraria"))
      {
         Print("Error al abrir posición de venta contraria: ", GetLastError());
      }
      else
      {
         Print("Nueva posición de venta contraria abierta sin cerrar la original.");
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar si ya existe una posición contraria                    |
//+------------------------------------------------------------------+
bool ExistePosicionContraria()
{
   ENUM_POSITION_TYPE tipoOriginal = IsBuyOrder() ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if(tipo != tipoOriginal)
            {
               return true; // Ya existe una posición contraria
            }
         }
      }
   }
   return false;
}

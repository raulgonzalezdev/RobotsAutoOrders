//+------------------------------------------------------------------+
//|               Bot Mejorado para Gestión de Tendencias            |
//|        Mantiene la posición principal, crea opuesta si resiste   |
//|        y sólo cierra la principal por Profit o Stop del Broker    |
//+------------------------------------------------------------------+
#property copyright "Raul Gonzalez"
#property link      "gonzalezquijadaraulantonio@gmail.com"
#property version   "2.4"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// Parámetros de entrada
input double RiskPercent = 0.01;             // Porcentaje del capital a arriesgar
input bool OrdenesSinSLTP = true;            // Crear órdenes sin SL/TP
input int MagicNumber = 11436207;            // Número mágico
input double StopLossPercent = 1.0;          // SL como % del precio
input double ProfitEstimated = 0.25;         // Ganancia estimada para cerrar por el bot
input double TakeProfitPercent = 2.0;        // TP como % del precio
input bool FixedVolume = false;              // Volumen fijo 1.0 si true, sino cálculo dinámico
input double UmbralCercaniaSL = 0.2;         // Umbral de cercanía al SL en %
input double PerdidaMaxima = -3.0;           // Pérdida máxima no utilizada para cierre, sólo referencia
input int PauseAfterStopLoss = 5;            // Pausa tras SL en minutos
input bool AllowSellOrders = true;           // Permitir órdenes de venta
input int MaxConsecutiveWins = 10;           // Máx ganancias seguidas
input int PauseAfterWins = 5;                // Pausa tras máx ganancias en minutos
input int TiempoResistiendo = 3600;          // Tiempo (seg) para considerar que una orden resiste y crear contraria

// Variables de control
double precioBase = 0.0;
double stopLossActual = 0.0;
double takeProfitActual = 0.0;
double Lots = 1.0;
datetime horaApertura;
datetime horaUltimoStopLoss = 0;
int consecutiveWins = 0;
datetime horaUltimaPausaPorGanancias = 0;

// Variables de tendencia
int FastMAPeriod = 50;
int SlowMAPeriod = 200;
int fastMA_handle;
int slowMA_handle;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   Lots = FixedVolume ? 1.0 : CalcularTamañoLotePorVolatilidad();

   fastMA_handle = iMA(_Symbol, PERIOD_CURRENT, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowMA_handle = iMA(_Symbol, PERIOD_CURRENT, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(fastMA_handle == INVALID_HANDLE || slowMA_handle == INVALID_HANDLE)
   {
      Print("Error al crear MAs: ", GetLastError());
      return INIT_FAILED;
   }

   if(!ExistePosicionActiva())
      AbrirNuevaOperacion();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   bool esTendenciaAlcista = EsTendenciaAlcista();

   if(ExistePosicionActiva())
   {
      AjustarStopLossDinamico();

      // Si se alcanzó el profit estimado, cerrar la posición del bot
      if(GananciaMayorIgual())
      {
         CerrarPosicionesBot();
         AbrirNuevaOperacion();
         return;
      }

      // Si la orden lleva demasiado tiempo abierta, crear orden contraria sin cerrar la actual
      if(TimeCurrent() - horaApertura > TiempoResistiendo)
      {
         CrearOrdenContraria(esTendenciaAlcista);
      }

      // No se cierra por pérdida manual ni cuando se cierra la orden opuesta manualmente.
      // La orden principal sigue abierta hasta que el broker la cierre por SL/TP o se logre ProfitEstimated.
   }
   else
   {
      // Pausa tras SL
      if(TimeCurrent() - horaUltimoStopLoss < PauseAfterStopLoss * 60)
         return;

      // Pausa tras ganancias consecutivas
      if(TimeCurrent() - horaUltimaPausaPorGanancias < PauseAfterWins * 60)
         return;

      // Abrir nueva operación si no hay posición activa
      AbrirNuevaOperacion();
   }
}

//+------------------------------------------------------------------+
double AjustarPrecioAlTick(double precio)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0)
      tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(MathFloor(precio / tickSize) * tickSize, digits);
}

//+------------------------------------------------------------------+
void AbrirNuevaOperacion()
{
   if(ExistePosicionActiva())
      return;

   if(TimeCurrent() - horaUltimaPausaPorGanancias < PauseAfterWins * 60)
      return;

   Lots = FixedVolume ? 1.0 : CalcularTamañoLotePorVolatilidad();
   bool esTendenciaAlcista = EsTendenciaAlcista();

   if(esTendenciaAlcista)
      OpenBuy();
   else
   {
      if(AllowSellOrders)
         OpenSell();
      else
         return;
   }
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(Ask == 0)
      return;

   precioBase = Ask;
   double sl_distance = (StopLossPercent / 100.0) * Ask;
   double tp_distance = (TakeProfitPercent / 100.0) * Ask;

   if(OrdenesSinSLTP)
   {
      stopLossActual = 0.0;
      takeProfitActual = 0.0;
   }
   else
   {
      stopLossActual = AjustarPrecioAlTick(Ask - sl_distance);
      takeProfitActual = AjustarPrecioAlTick(Ask + tp_distance);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if(trade.Buy(Lots, _Symbol, Ask, stopLossActual, takeProfitActual, "Compra"))
   {
      horaApertura = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(Bid == 0)
      return;

   precioBase = Bid;
   double sl_distance = (StopLossPercent / 100.0) * Bid;
   double tp_distance = (TakeProfitPercent / 100.0) * Bid;

   if(OrdenesSinSLTP)
   {
      stopLossActual = 0.0;
      takeProfitActual = 0.0;
   }
   else
   {
      stopLossActual = AjustarPrecioAlTick(Bid + sl_distance);
      takeProfitActual = AjustarPrecioAlTick(Bid - tp_distance);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if(trade.Sell(Lots, _Symbol, Bid, stopLossActual, takeProfitActual, "Venta"))
   {
      horaApertura = TimeCurrent();
   }
}

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
            if(profit >= ProfitEstimated)
               return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
double CalcularTamañoLotePorVolatilidad()
{
   if(FixedVolume)
      return 1.0;

   int atr_handle = iATR(_Symbol, PERIOD_D1, 14);
   if(atr_handle == INVALID_HANDLE)
      return Lots;

   double atr_values[];
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_values) <= 0)
      return Lots;
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
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool EsTendenciaAlcista()
{
   double fastMA[], slowMA[];
   if(CopyBuffer(fastMA_handle, 0, 0, 1, fastMA) <= 0 || CopyBuffer(slowMA_handle, 0, 0, 1, slowMA) <= 0)
      return true;
   return fastMA[0] > slowMA[0];
}

//+------------------------------------------------------------------+
void AjustarStopLossDinamico()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double precioActual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            double nuevoSL = (tipo == POSITION_TYPE_BUY)
                             ? precioActual - (StopLossPercent / 100.0) * precioActual
                             : precioActual + (StopLossPercent / 100.0) * precioActual;

            nuevoSL = AjustarPrecioAlTick(nuevoSL);
            trade.PositionModify(ticket, nuevoSL, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
void CrearOrdenContraria(bool esTendenciaAlcista)
{
   double precio = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tp_distance = (TakeProfitPercent / 100.0) * precio;
   double takeProfit = AjustarPrecioAlTick(esTendenciaAlcista ? precio + tp_distance : precio - tp_distance);

   // Crear orden contraria sin cerrar la existente. Esta orden contraria se cierra manualmente por el usuario.
   trade.SetExpertMagicNumber(MagicNumber);
   if(esTendenciaAlcista)
      trade.Sell(Lots, _Symbol, 0, 0.0, takeProfit, "Contraria Manual");
   else
      trade.Buy(Lots, _Symbol, 0, 0.0, takeProfit, "Contraria Manual");
}

//+------------------------------------------------------------------+
void CerrarPosicionesBot()
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
               RegistrarResultadoOperacion(profit);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void RegistrarResultadoOperacion(double profit)
{
   if(profit > 0)
   {
      consecutiveWins++;
      if(consecutiveWins >= MaxConsecutiveWins)
      {
         horaUltimaPausaPorGanancias = TimeCurrent();
         consecutiveWins = 0;
      }
   }
   else
   {
      consecutiveWins = 0;
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|       Bot Experto en Tendencias Mejorado                         |
//|       Incorporando filtros ADX, trailing inteligente y parcial   |
//|       Ejemplo conceptual, no garantiza ganancias                 |
//+------------------------------------------------------------------+
#property copyright "Raul Gonzalez"
#property link      "gonzalezquijadaraulantonio@gmail.com"
#property version   "5.0"
#property strict

#include <Trade/Trade.mqh>
CTrade tradeObj;

// Parámetros de entrada
input double RiskPercent = 1.0;                // Porcentaje de riesgo por operación
input bool OrdenesSinSLTP = false;             // Usar SL/TP
input int MagicNumber = 777777;                // Número mágico
input double StopLossATRFactor = 2.0;          // SL = ATR * factor
input double TakeProfitATRFactor = 4.0;        // TP = ATR * factor
input double PartialCloseFactor = 2.0;         // Primer objetivo parcial = ATR * factor menor que TP

input bool FixedVolume = false;                // Volumen fijo 1.0 si true
input int FastMAPeriod = 50;                   // Período MA rápida
input int SlowMAPeriod = 200;                  // Período MA lenta
input ENUM_TIMEFRAMES HigherTF = PERIOD_H4;    // TF mayor
input ENUM_TIMEFRAMES EntryTF = PERIOD_M15;    // TF entrada
input int RSIPeriod = 14;                      // RSI
input double RSIBuyLevel = 55.0;               // Nivel RSI compra base
input double RSISellLevel = 45.0;              // Nivel RSI venta base
input int ADXPeriod = 14;                      // ADX para medir fuerza de tendencia
input double MinADX = 20.0;                    // ADX mínimo para considerar tendencia válida
input int MaxConsecutiveWins = 5;              // Máx ganancias seguidas antes de pausar
input int PauseAfterWins = 15;                 // Pausa tras máx ganancias (min)
input int PauseAfterStopLoss = 5;              // Pausa tras StopLoss (min)
input double ProfitEstimated = 50.0;           // Profit total para cierre
input bool AllowSellOrders = true;             // Permitir ventas

// Variables internas
double Lots = 1.0;
datetime horaUltimoStopLoss = 0;
datetime horaUltimaPausaPorGanancias = 0;
int consecutiveWins = 0;
datetime horaApertura;

// Handles indicadores
int fastMA_Higher, slowMA_Higher;
int fastMA_Entry, slowMA_Entry;
int rsi_handle;
int atr_handle;
int adx_handle;

// Estructura para guardar el precio max/min logrado desde que se abrió posición (para trailing inteligente)
double maxPriceSinceOpen = 0.0;
double minPriceSinceOpen = 0.0;
bool partialClosed = false; // Para saber si ya se realizó el cierre parcial

//+------------------------------------------------------------------+
int OnInit()
{
   tradeObj.SetExpertMagicNumber(MagicNumber);
   Lots = FixedVolume ? 1.0 : CalcularTamañoLote(RiskPercent);

   // MAs en TF mayor
   fastMA_Higher = iMA(_Symbol, HigherTF, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowMA_Higher = iMA(_Symbol, HigherTF, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   // MAs en TF entrada
   fastMA_Entry = iMA(_Symbol, EntryTF, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowMA_Entry = iMA(_Symbol, EntryTF, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   // RSI en TF entrada
   rsi_handle = iRSI(_Symbol, EntryTF, RSIPeriod, PRICE_CLOSE);

   // ATR para EntryTF
   atr_handle = iATR(_Symbol, EntryTF, 14);

   // ADX para EntryTF (mismo TF que entrada, podría ser TF mayor también)
   adx_handle = iADX(_Symbol, EntryTF, ADXPeriod, PRICE_CLOSE);

   if(fastMA_Higher == INVALID_HANDLE || slowMA_Higher == INVALID_HANDLE ||
      fastMA_Entry == INVALID_HANDLE || slowMA_Entry == INVALID_HANDLE ||
      rsi_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE || adx_handle == INVALID_HANDLE)
   {
      Print("Error al crear indicadores: ", GetLastError());
      return INIT_FAILED;
   }

   if(!ExistePosicionActiva())
      IntentarApertura();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(ExistePosicionActiva())
   {
      if(GananciaMayorIgual())
      {
         CerrarPosicionesBot();
         IntentarApertura();
         return;
      }

      AjustarStopLossDinamicoInteligente();

      // Realizar cierre parcial si cumple condiciones
      IntentarCierreParcial();
   }
   else
   {
      // Pausas
      if(TimeCurrent() - horaUltimoStopLoss < PauseAfterStopLoss * 60) return;
      if(TimeCurrent() - horaUltimaPausaPorGanancias < PauseAfterWins * 60) return;

      IntentarApertura();
   }
}

//+------------------------------------------------------------------+
void IntentarApertura()
{
   if(ExistePosicionActiva()) return;

   bool esTendenciaAlcista = TendenciaAlcista(fastMA_Higher, slowMA_Higher);
   bool esTendenciaEntrada = TendenciaAlcista(fastMA_Entry, slowMA_Entry);

   double rsi_val = ValorActualRSI();
   if(rsi_val < 0) return;

   double adx_val = ValorADX();
   if(adx_val < 0) return;

   // Ajuste adaptativo simple: Si ADX es alto (mercado con tendencia fuerte), aumentar nivel RSI para ser más selectivo
   double rsiBuyAdapt = RSIBuyLevel;
   double rsiSellAdapt = RSISellLevel;
   if(adx_val > 25) 
   {
      rsiBuyAdapt += 5.0; // Mercado con tendencia fuerte, pedir mayor RSI para entrada de compra
      rsiSellAdapt -= 5.0; // Para ventas, pedir RSI más bajo aún
   }

   Lots = FixedVolume ? 1.0 : CalcularTamañoLote(RiskPercent);

   // Chequeo ADX para evitar mercados laterales
   if(adx_val < MinADX)
   {
      // Mercado sin tendencia clara
      return;
   }

   if(esTendenciaAlcista && esTendenciaEntrada && rsi_val > rsiBuyAdapt)
   {
      AbrirOperacion(true);
   }
   else if(!esTendenciaAlcista && !esTendenciaEntrada && rsi_val < rsiSellAdapt && AllowSellOrders)
   {
      AbrirOperacion(false);
   }
}

//+------------------------------------------------------------------+
void AbrirOperacion(bool buy)
{
   double precio = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(precio <= 0) return;

   double atr = ValorATR();
   if(atr <= 0) return;

   double SL = 0.0, TP = 0.0;
   if(!OrdenesSinSLTP)
   {
      double sl_distance = atr * StopLossATRFactor;
      double tp_distance = atr * TakeProfitATRFactor;

      if(buy)
      {
         SL = AjustarPrecioAlTick(precio - sl_distance);
         TP = AjustarPrecioAlTick(precio + tp_distance);
      }
      else
      {
         SL = AjustarPrecioAlTick(precio + sl_distance);
         TP = AjustarPrecioAlTick(precio - tp_distance);
      }
   }

   tradeObj.SetExpertMagicNumber(MagicNumber);
   bool result = false;
   if(buy)
      result = tradeObj.Buy(Lots, _Symbol, precio, SL, TP, "Compra Tendencial");
   else
      result = tradeObj.Sell(Lots, _Symbol, precio, SL, TP, "Venta Tendencial");

   if(result)
   {
      horaApertura = TimeCurrent();
      partialClosed = false; // reset de cierre parcial
      // Guardamos precio inicial como referencia
      maxPriceSinceOpen = precio;
      minPriceSinceOpen = precio;
   }
   else
   {
      Print("Error al abrir operación: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
bool TendenciaAlcista(int fastHandle, int slowHandle)
{
   double fastMA[], slowMA[];
   if(CopyBuffer(fastHandle, 0, 0, 1, fastMA) <= 0 || CopyBuffer(slowHandle, 0, 0, 1, slowMA) <= 0)
      return true;
   return fastMA[0] > slowMA[0];
}

//+------------------------------------------------------------------+
double ValorActualRSI()
{
   double rsi_val[];
   if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_val) <= 0)
   {
      Print("Error al copiar RSI: ", GetLastError());
      return -1.0;
   }
   return rsi_val[0];
}

//+------------------------------------------------------------------+
double ValorATR()
{
   double atr_val[];
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_val) <= 0)
   {
      Print("Error al copiar ATR: ", GetLastError());
      return -1.0;
   }
   return atr_val[0];
}

//+------------------------------------------------------------------+
double ValorADX()
{
   double adx_val[];
   // ADX en buffer principal = índice 0
   if(CopyBuffer(adx_handle,0,0,1,adx_val)<=0)
   {
      Print("Error al copiar ADX: ", GetLastError());
      return -1.0;
   }
   return adx_val[0];
}

//+------------------------------------------------------------------+
double AjustarPrecioAlTick(double precio)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0) tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(MathFloor(precio / tickSize) * tickSize, digits);
}

//+------------------------------------------------------------------+
bool ExistePosicionActiva()
{
   for(int i = PositionsTotal() -1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            horaApertura = (datetime)PositionGetInteger(POSITION_TIME);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void AjustarStopLossDinamicoInteligente()
{
   // Ajusta SL sólo cuando se forman nuevos máximos/mínimos desde la apertura
   double atr = ValorATR();
   if(atr <= 0) return;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double precioActual = (tipo == POSITION_TYPE_BUY) ? 
                                  SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                  SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            // Actualizar max/min desde la apertura
            if(tipo == POSITION_TYPE_BUY && precioActual > maxPriceSinceOpen)
               maxPriceSinceOpen = precioActual;
            if(tipo == POSITION_TYPE_SELL && precioActual < minPriceSinceOpen)
               minPriceSinceOpen = precioActual;

            double posicionSL = PositionGetDouble(POSITION_SL);
            double trailingDistance = atr * StopLossATRFactor;

            double nuevoSL = 0.0;
            // Para BUY: si alcanzó un nuevo máximo, subir SL cerca del mínimo entre el nuevo max y trailingDistance
            if(tipo == POSITION_TYPE_BUY)
            {
               double potentialSL = AjustarPrecioAlTick(maxPriceSinceOpen - trailingDistance);
               // Mover SL sólo si favorece la operación y no supera el precio actual
               if(potentialSL > posicionSL && potentialSL < precioActual)
                  nuevoSL = potentialSL;
            }
            else
            {
               double potentialSL = AjustarPrecioAlTick(minPriceSinceOpen + trailingDistance);
               if(potentialSL < posicionSL && potentialSL > precioActual)
                  nuevoSL = potentialSL;
            }

            if(nuevoSL != 0.0 && !tradeObj.PositionModify(ticket, nuevoSL, PositionGetDouble(POSITION_TP)))
            {
               Print("Error al modificar SL dinámico: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
bool GananciaMayorIgual()
{
   double totalProfit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            totalProfit += profit;
         }
      }
   }

   if(totalProfit >= ProfitEstimated)
      return true;

   return false;
}

//+------------------------------------------------------------------+
double CalcularTamañoLote(double riskPercent)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (riskPercent / 100.0);

   double atr = ValorATR();
   if(atr <= 0) return 0.01;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slPips = (atr * StopLossATRFactor) / point;
   if(slPips <= 0) slPips = 100;

   double pipValuePerLot = (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE))*point;
   if(pipValuePerLot <= 0) pipValuePerLot = 1.0;

   double lossPerLot = slPips * pipValuePerLot;
   double lotSize = riskAmount / lossPerLot;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lotSize = MathMax(MathMin(lotSize, maxLot), minLot);

   return lotSize;
}

//+------------------------------------------------------------------+
void CerrarPosicionesBot()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(tradeObj.PositionClose(ticket))
               RegistrarResultadoOperacion(profit);
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
      horaUltimoStopLoss = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
void IntentarCierreParcial()
{
   // Cierre parcial: si alcanza un objetivo intermedio (2*ATR por ejemplo),
   // cerrar la mitad y dejar correr el resto.
   // Esta es una lógica simple, se asume que sólo hay una posición del bot.

   for(int i = PositionsTotal() -1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol && !partialClosed)
         {
            ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double atr = ValorATR();
            if(atr <= 0) return;

            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = (tipo == POSITION_TYPE_BUY) ? 
                                  SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                  SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            double partialDistance = atr * PartialCloseFactor;

            if(tipo == POSITION_TYPE_BUY && currentPrice >= entryPrice + partialDistance)
            {
               // cerrar la mitad
               double volume = PositionGetDouble(POSITION_VOLUME);
               double closeVolume = volume/2.0;
               if(tradeObj.PositionClosePartial(ticket, closeVolume))
                  partialClosed = true;
            }
            else if(tipo == POSITION_TYPE_SELL && currentPrice <= entryPrice - partialDistance)
            {
               double volume = PositionGetDouble(POSITION_VOLUME);
               double closeVolume = volume/2.0;
               if(tradeObj.PositionClosePartial(ticket, closeVolume))
                  partialClosed = true;
            }
         }
      }
   }
}
//+------------------------------------------------------------------+

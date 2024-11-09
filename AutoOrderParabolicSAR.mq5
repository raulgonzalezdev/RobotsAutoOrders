//+------------------------------------------------------------------+
//|                   Bot de Orden Automática con Trailing SAR y Apertura Manual |
//+------------------------------------------------------------------+
#property copyright "Raul Gonzalez"
#property link      "gonzalezquijadaraulantonio@gmail.com"
#property version   "2.2"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// Parámetros de entrada
input double RiskPercent = 1.0;   // Porcentaje del capital para arriesgar en cada operación
input double  ProfitEstimated = 20;        // Ganancia estimada para cerrar la Orden
input int MagicNumber = 11436207;          // Número mágico para identificar las operaciones
input double TakeProfitPercent = 3.0;     // Take Profit en porcentaje del precio de compra o venta
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
bool OrdenManual = false;                  
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
//| Función OnTick                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   if(IsNewBar())
      TrailingStopBySAR(MagicNumber, 0, 0); 

   if(OpenOrdenManual && OrdenManual)
   {
        AbrirOrdenManual(TipoOrdenManual);
      OrdenManual = false;
   }

   if(ExistePosicionActiva())
   {
      if(GananciaMayorIgual())
      {
         CerrarPosicion();
         AbrirOperacionSegunTendencia();
         return;
      }

      if(TimeCurrent() - horaApertura >= 3600 && PosicionConBeneficio())
      {
         CerrarPosicion();
         AbrirOperacionSegunTendencia();
         return;
      }

      if(PosicionCercaDeStopLossYPerdidaMenorA(PerdidaMaxima))
      {
         CerrarPosicionPorStopLoss();
         return;
      }
   }
   else
   {
      if(TimeCurrent() - horaUltimoStopLoss < PauseAfterStopLoss * 60 || 
         TimeCurrent() - horaUltimaPausaPorGanancias < PauseAfterWins * 60)
         return;

      AbrirOperacionSegunTendencia();
   }
}

//+------------------------------------------------------------------+
//| Función para obtener el valor de Parabolic SAR                   |
//+------------------------------------------------------------------+
double GetParabolicSARValue()
{
   double sar_values[];
   if(CopyBuffer(sar_handle, 0, 1, 1, sar_values) > 0)
      return sar_values[0];
   else
      Print("Error al obtener datos de Parabolic SAR: ", GetLastError());
   return EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| Función para obtener datos del SAR en índice                     |
//+------------------------------------------------------------------+
double GetSARData(const int index)
{
   double array[1];
   if(CopyBuffer(sar_handle, 0, index, 1, array) != 1)
      Print("Error en CopyBuffer para SAR en GetSARData: ", GetLastError());
   return array[0];
}

//+------------------------------------------------------------------+
//| Trailing Stop usando SAR                                         |
//+------------------------------------------------------------------+
void TrailingStopBySAR(const long magic=-1, const int trailing_step_pt=0, const int trailing_start_pt=0)
{
   double sar = GetSARData(1);
   if(sar == EMPTY_VALUE)
      return;

   TrailingStopByValue(sar, magic, trailing_step_pt, trailing_start_pt);
}

//+------------------------------------------------------------------+
//| Trailing Stop basado en valor                                    |
//+------------------------------------------------------------------+
void TrailingStopByValue(const double value_sl, const long magic=-1, const int trailing_step_pt=0, const int trailing_start_pt=0)
{
   int total = PositionsTotal();
   MqlTick tick;
   for(int i = total - 1; i >= 0; i--)
   {
      ulong pos_ticket = PositionGetTicket(i);
      if(pos_ticket == 0)
         continue;
         
      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      long pos_magic = PositionGetInteger(POSITION_MAGIC);
      if((magic != -1 && pos_magic != magic) || pos_symbol != Symbol())
         continue;
      
      if(!SymbolInfoTick(Symbol(), tick))
         continue;
      
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
      double pos_sl = PositionGetDouble(POSITION_SL);

      if(CheckCriterion(pos_type, pos_open, pos_sl, value_sl, trailing_step_pt, trailing_start_pt, tick))
         ModifySL(pos_ticket, value_sl);
   }
}

//+------------------------------------------------------------------+
//| Función para modificar Stop Loss                                 |
//+------------------------------------------------------------------+
bool ModifySL(const ulong ticket, const double stop_loss)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_SLTP;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.magic = PositionGetInteger(POSITION_MAGIC);
   request.position = ticket;
   request.sl = NormalizeDouble(stop_loss, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));

   // Calcular el Take Profit basado en un porcentaje del precio de apertura
   double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
   takeProfitActual = pos_open * (1 + TakeProfitPercent / 100.0);
   request.tp = NormalizeDouble(takeProfitActual, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));

   if(!OrderSend(request, result))
   {
      PrintFormat("Error al modificar SL/TP del ticket %d: %d", ticket, GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Validación de criterio de Stop Loss                              |
//+------------------------------------------------------------------+
bool CheckCriterion(ENUM_POSITION_TYPE pos_type, double pos_open, double pos_sl, double value_sl, 
                    int trailing_step_pt, int trailing_start_pt, MqlTick &tick)
{
   if(NormalizeDouble(pos_sl - value_sl, Digits()) == 0)
      return false;

   double trailing_step = trailing_step_pt * Point();
   double stop_level = StopLevel(2) * Point();
   int pos_profit_pt = 0;
   
   if(pos_type == POSITION_TYPE_BUY)
   {
      pos_profit_pt = int((tick.bid - pos_open) / Point());
      return (tick.bid - stop_level > value_sl) && 
             (pos_sl + trailing_step < value_sl) && 
             (trailing_start_pt == 0 || pos_profit_pt > trailing_start_pt);
   }
   else if(pos_type == POSITION_TYPE_SELL)
   {
      pos_profit_pt = int((pos_open - tick.ask) / Point());
      return (tick.ask + stop_level < value_sl) && 
             ((pos_sl - trailing_step > value_sl) || pos_sl == 0) && 
             (trailing_start_pt == 0 || pos_profit_pt > trailing_start_pt);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Obtener el nivel mínimo de Stop                                  |
//+------------------------------------------------------------------+
int StopLevel(const int spread_multiplier)
{
   int spread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   int stop_level = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
   return(stop_level == 0 ? spread * spread_multiplier : stop_level);
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

//+------------------------------------------------------------------+
//| Función para abrir una orden de compra                           |
//+------------------------------------------------------------------+
void OpenBuy()
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("Error al obtener el tick: ", GetLastError());
      return;
   }

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = Lots;
   request.type = ORDER_TYPE_BUY;
   request.price = tick.ask;
   request.sl = 0; // Inicialmente en cero
   request.tp = 0; // Inicialmente en cero
   request.deviation = 10;
   request.magic = MagicNumber;

   if(!OrderSend(request, result))
   {
      Print("Error al enviar orden de compra: ", GetLastError());
   }
   else
   {
      Print("Orden de compra enviada: Ticket=", result.order);
      if(result.order > 0)
      {
         // Verificar y depurar valores de SL y TP
         stopLossActual = CalcularStopLoss(tick.ask);
         takeProfitActual = CalcularTakeProfit(tick.ask);
         Print("Valores calculados - SL: ", stopLossActual, " TP: ", takeProfitActual);

         // Asegúrate de que estos valores no sean 0 antes de modificar
         ModifySL(result.order, stopLossActual);
         TrailingStopBySAR(MagicNumber,0,0);
      }
      else
      {
         Print("Error: Ticket de orden no válido.");
      }
   }
}

//+------------------------------------------------------------------+
//| Función para abrir una orden de venta                            |
//+------------------------------------------------------------------+
void OpenSell()
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("Error al obtener el tick: ", GetLastError());
      return;
   }

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = Lots;
   request.type = ORDER_TYPE_SELL;
   request.price = tick.bid;
   request.sl = 0; // Inicialmente en cero
   request.tp = 0; // Inicialmente en cero
   request.deviation = 10;
   request.magic = MagicNumber;

   if(!OrderSend(request, result))
   {
      Print("Error al enviar orden de venta: ", GetLastError());
   }
   else
   {
      Print("Orden de venta enviada: Ticket=", result.order);
      if(result.order > 0)
      {
         // Calcular stopLossActual y takeProfitActual antes de llamar a ModifySL
         stopLossActual = CalcularStopLoss(tick.bid);
         takeProfitActual = CalcularTakeProfit(tick.bid);
         ModifySL(result.order, stopLossActual);

         // Aplicar Trailing Stop usando SAR
         TrailingStopBySAR(MagicNumber,0,0);
      }
      else
      {
         Print("Error: Ticket de orden no válido.");
      }
   }
}

// Funciones para calcular el Stop Loss y Take Profit
double CalcularStopLoss(double precioActual)
{
   // Implementa la lógica para calcular el Stop Loss basado en el Parabolic SAR
   double sarValue = GetParabolicSARValue();
   return sarValue; // Ajusta según tu lógica
}

double  CalcularTakeProfit(double precioActual)
{
   // Implementa la lógica para calcular el Take Profit
   return precioActual * (1 + TakeProfitPercent / 100.0);
}

//+------------------------------------------------------------------+
//| Función para calcular el tamaño del lote basado en la volatilidad|
//+------------------------------------------------------------------+
double CalcularTamañoLotePorVolatilidad()
{
   // Parámetros de configuración
   double lotSize = 0.1; // Tamaño de lote fijo por defecto
   double maxLotSize = 2.0; // Tamaño máximo del lote permitido
   double riskFactor = 1.5; // Factor de riesgo basado en rendimiento histórico

   // Obtener el margen libre y calcular el monto de riesgo
   double freeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
   double riskAmount = (RiskPercent / 100.0) * freeMargin;

   // Calcular la volatilidad usando ATR
   double atr = iATR(_Symbol, PERIOD_CURRENT, 14);
   if (atr > 0)
   {
      // Ajustar el tamaño del lote basado en la volatilidad
      lotSize = riskAmount / atr;
   }

   // Evaluar el rendimiento histórico (simplificado)
   double historicalPerformance = EvaluarRendimientoHistorico();
   if (historicalPerformance > 1.0)
   {
      // Aumentar el tamaño del lote si el rendimiento es positivo
      lotSize *= riskFactor;
   }

   // Asegúrate de que el tamaño del lote no sea menor que el mínimo permitido
   double minLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lotSize = MathMax(lotSize, minLotSize);

   // Limitar el tamaño del lote al máximo permitido
   return NormalizeDouble(MathMin(lotSize, maxLotSize), 2);
}

//+------------------------------------------------------------------+
//| Función para evaluar el rendimiento histórico del mercado        |
//+------------------------------------------------------------------+
double EvaluarRendimientoHistorico()
{
   // Seleccionar el historial de operaciones para el símbolo actual
   datetime from = TimeCurrent() - PERIOD_M1 * 1440; // Últimos 24 horas
   datetime to = TimeCurrent();
   if(!HistorySelect(from, to))
   {
      Print("Error al seleccionar el historial: ", GetLastError());
      return 1.0; // Valor por defecto si hay un error
   }

   double totalProfit = 0.0;
   int totalDeals = 0;

   // Recorrer las operaciones históricas
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) == _Symbol)
      {
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         totalProfit += profit;
         totalDeals++;
      }
   }

   // Calcular la relación ganancia/pérdida
   double performanceRatio = totalDeals > 0 ? totalProfit / totalDeals : 1.0;

   // Ajustar el rendimiento histórico basado en la relación
   return performanceRatio > 0 ? 1.2 : 0.8; // Ejemplo de ajuste
}

//+------------------------------------------------------------------+
//| Función para verificar si existe una posición activa para el símbolo actual |
//+------------------------------------------------------------------+
bool ExistePosicionActiva()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && 
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol) // Verifica el símbolo actual
      {
         return true;
      }
   }
   return false;
}


//+------------------------------------------------------------------+
//| Return the bar opening time by timeseries index                  |
//+------------------------------------------------------------------+
datetime TimeOpenBar(const int index)
  {
   datetime array[1];
   ResetLastError();
   if(CopyTime(NULL, PERIOD_CURRENT, index, 1, array)!=1)
     {
      PrintFormat("%s: CopyTime() failed. Error %d", __FUNCTION__, GetLastError());
      return 0;
     }
   return array[0];
  }
  
//+------------------------------------------------------------------+
//| Return new bar opening flag                                      |
//+------------------------------------------------------------------+
bool IsNewBar(void)
  {
   static datetime time_prev=0;
   datetime        bar_open_time=TimeOpenBar(0);
   if(bar_open_time==0)
      return false;
   if(bar_open_time!=time_prev)
     {
      time_prev=bar_open_time;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Función para evaluar el rendimiento del mercado                  |
//+------------------------------------------------------------------+
double EvaluarRendimientoDelMercado()
{
   // Definir el período de tiempo para el análisis
   int period = 14; // Período para el cálculo del ATR
   double atr = iATR(_Symbol, PERIOD_CURRENT, period);

   // Calcular medias móviles para evaluar la tendencia
   int fastMA_handle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
   int slowMA_handle = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);
   double fastMA[1], slowMA[1];

   // Copiar el valor más reciente de cada media móvil
   if(CopyBuffer(fastMA_handle, 0, 0, 1, fastMA) > 0 && CopyBuffer(slowMA_handle, 0, 0, 1, slowMA) > 0)
   {
      if (fastMA[0] > slowMA[0])
      {
         Print("Tendencia alcista detectada.");
         return 1.2; // Valor positivo para tendencia alcista
      }
      else if (fastMA[0] < slowMA[0])
      {
         Print("Tendencia bajista detectada.");
         return 0.8; // Valor negativo para tendencia bajista
      }
   }

   // Evaluar la volatilidad
   if (atr > 0)
   {
      Print("Volatilidad actual (ATR): ", atr);
   }

   // Retornar un valor basado en la evaluación
   return 1.0; // Valor neutral si no hay una tendencia clara
}

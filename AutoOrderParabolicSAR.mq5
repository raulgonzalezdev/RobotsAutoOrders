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
input double RiskPercent = 0.5;   // Porcentaje del capital para arriesgar en cada operación
input double ProfitEstimated = 5;  // Ganancia estimada para cerrar la Orden
input int MagicNumber = 11436207;  // Número mágico para identificar las operaciones
input double TakeProfitPercent = 1.0; // Take Profit en porcentaje del precio de compra o venta
input bool FixedVolume = true;    // Usar volumen fijo de 0.5 si es true, de lo contrario calcular
input double ParabolicStep = 0.01;   // Paso del Parabolic SAR para el trailing stop
input double ParabolicMax = 0.1;     // Máximo del Parabolic SAR para el trailing stop
input bool OpenOrdenManual = false;  // Activar apertura de orden manual
input string TipoOrdenManual = "SELL"; // Tipo de orden manual: "BUY" o "SELL"
input double ADXThreshold = 11.0;    // Umbral del ADX para abrir operaciones
input int ADXPeriod = 7;             // Período del ADX para evaluar la fuerza de la tendencia
input string Mercado = "CRYPTO";     // Mercado: "CRYPTO" o "OTHER"
input int CryptoFastPeriod = 10;
input int CryptoSlowPeriod = 30;
input ENUM_TIMEFRAMES CryptoTimeframe = PERIOD_M5; // Marco temporal de 5 minutos
input int OtherFastPeriod = 50;
input int OtherSlowPeriod = 200;
input ENUM_TIMEFRAMES OtherTimeframe = PERIOD_CURRENT; // Marco temporal actual


// Variables de control 
bool OrdenManual = false;                  
double precioBase = 0.0;
double stopLossActual = 0.0;
double takeProfitActual = 0.0;
double Lots = RiskPercent;


// Manejador del Parabolic SAR
int sar_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Función de Inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   OrdenManual = OpenOrdenManual;
   trade.SetExpertMagicNumber(MagicNumber);
   Lots = FixedVolume ? 0.5 : CalcularTamañoLotePorVolatilidad();

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

   

     
   }
   else
   {
        
      AbrirOperacionSegunTendencia();
        
   }

  
   CheckWilliamsR();
 

   // Calcular niveles de Fibonacci
   double swingHigh = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, 20, 0));
   double swingLow = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, 20, 0));
   CalculateFibonacciLevels(swingHigh, swingLow);

   VerificarYModificarStopLossCritico();
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
        double pos_tp = PositionGetDouble(POSITION_TP);

        // Determinar value_sl adecuado para BUY o SELL
        double adjusted_value_sl = value_sl;
        if(pos_type == POSITION_TYPE_SELL)
        {
            adjusted_value_sl = MathMax(value_sl, tick.ask + StopLevel(2) * Point());
            pos_tp = CalcularTakeProfit(tick.ask, pos_type);
        }
        else if(pos_type == POSITION_TYPE_BUY)
        {
            adjusted_value_sl = MathMin(value_sl, tick.bid - StopLevel(2) * Point());
            pos_tp = CalcularTakeProfit(tick.bid, pos_type);
        }
        if (PositionGetDouble(POSITION_TP)== 0 && PositionGetDouble(POSITION_SL) == 0)
        {
             ModifySL(pos_ticket, adjusted_value_sl, pos_tp);
        }   
        if(CheckCriterion(pos_type, pos_open, pos_sl, adjusted_value_sl, trailing_step_pt, trailing_start_pt, tick))
            ModifySL(pos_ticket, adjusted_value_sl, pos_tp);
    }
}


//+------------------------------------------------------------------+
//| Función para modificar Stop Loss                                 |
//+------------------------------------------------------------------+
bool ModifySL(const ulong ticket, const double stop_loss, const double take_profit)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_SLTP;
    request.symbol = PositionGetString(POSITION_SYMBOL);
    request.magic = PositionGetInteger(POSITION_MAGIC);
    request.position = ticket;
    request.sl = NormalizeDouble(stop_loss, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
    request.tp = NormalizeDouble(take_profit, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));

    if(!OrderSend(request, result))
    {
        PrintFormat("Error al modificar SL/TP del ticket %d: %d", ticket, GetLastError());
        return false;
    }
    else
    {
        PrintFormat("SL/TP modificados para el ticket %d: SL=%.5f, TP=%.5f", ticket, request.sl, request.tp);
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
   Lots = FixedVolume ? RiskPercent : CalcularTamañoLotePorVolatilidad();
   
   // Evaluar la fuerza de la tendencia usando ADX con la función GetADXValue
   double adxValue = GetADXValue(ADXPeriod); // Usar el período configurado

   if(adxValue < 0) // Verificar si hubo un error al obtener el ADX
   {
      Print("Error al obtener el valor del ADX, no se abrirán operaciones.");
      return;
   }

   if(adxValue < ADXThreshold) // Usar el parámetro de entrada
   {
      Print("Tendencia débil detectada, no se abrirán operaciones. ADX: ", adxValue);
      return;
   }
   
   if(EsTendenciaAlcista())
   {
      OpenBuy();
      TrailingStopBySAR(MagicNumber, 0, 0); 
   }
   else 
   {
      OpenSell();
      TrailingStopBySAR(MagicNumber, 0, 0); 
   }
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
//| Función para determinar la tendencia del mercado                 |
//+------------------------------------------------------------------+
bool EsTendenciaAlcista()
{
    int fastPeriod;
    int slowPeriod;
    ENUM_TIMEFRAMES timeframe;

    // Ajustar los períodos de las medias móviles y el marco temporal según el tipo de mercado
    if(Mercado == "CRYPTO")
    {
        fastPeriod = CryptoFastPeriod;
        slowPeriod = CryptoSlowPeriod;
        timeframe = CryptoTimeframe;
    }
    else
    {
        fastPeriod = OtherFastPeriod;
        slowPeriod = OtherSlowPeriod;
        timeframe = OtherTimeframe;
    }

    // Crear handles para las medias móviles
    int fastMA_handle = iMA(_Symbol, timeframe, fastPeriod, 0, MODE_EMA, PRICE_CLOSE);
    int slowMA_handle = iMA(_Symbol, timeframe, slowPeriod, 0, MODE_EMA, PRICE_CLOSE);
    double fastMA[1], slowMA[1];

    // Copiar el valor más reciente de cada media móvil
    if(CopyBuffer(fastMA_handle, 0, 0, 1, fastMA) > 0 &&
       CopyBuffer(slowMA_handle, 0, 0, 1, slowMA) > 0)
    {
        return fastMA[0] > slowMA[0];
    }
    else
    {
        Print("Error al copiar los buffers de las medias móviles.");
    }
    return false;
}


//+------------------------------------------------------------------+
//| Función para abrir orden manual                                  |
//+------------------------------------------------------------------+
void AbrirOrdenManual(string tipoOrden)
{
   Lots = FixedVolume ? RiskPercent : CalcularTamañoLotePorVolatilidad();

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

    if (!MarketOpenHours(_Symbol)) {
        Print("El mercado está cerrado. No se puede abrir la orden de tipo: ", ORDER_TYPE_BUY);
        return;
    }

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
   //request.deviation = 10;
   request.magic = MagicNumber;

   if(!OrderSend(request, result))
   {
      Print("Error al enviar orden de compra: ", GetLastError());
   }
   else
   {
      Print("Orden de compra enviada: Ticket=", result.order);
  
      TrailingStopBySAR(MagicNumber,0,0);
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

   if (!MarketOpenHours(_Symbol)) {
        Print("El mercado está cerrado. No se puede abrir la orden de tipo: ", ORDER_TYPE_SELL);
        return;
    }

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
   //request.deviation = 10;
   request.magic = MagicNumber;

   if(!OrderSend(request, result))
   {
      Print("Error al enviar orden de venta: ", GetLastError());
   }
   else
   {
      Print("Orden de venta enviada: Ticket=", result.order);
    
      TrailingStopBySAR(MagicNumber,0,0);
   }
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
   double atr = iATR(_Symbol, PERIOD_CURRENT, ADXPeriod);
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
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         if(posType == POSITION_TYPE_BUY)
         {
            return  true;
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            return true;
         }
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

void CalculateFibonacciLevels(double swingHigh, double swingLow)
{
    double diff = swingHigh - swingLow;
    double level61_8 = swingHigh - 0.618 * diff;

    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (fabs(currentPrice - level61_8) < (0.001 * currentPrice))
    {
        // Guardar la señal en un archivo CSV
        SaveSignalToCSV("Near 61.8% Fibonacci", currentPrice);

        // Decidir si abrir una orden de compra o venta
        if (EsTendenciaAlcista()) // Supongamos que tienes una función para verificar la tendencia
        {
            if(!ExistePosicionActiva())
            {
                OpenBuy(); // Función para abrir una orden de compra
            }
        }
        else
        {
            if(!ExistePosicionActiva())
            {
                OpenSell(); // Función para abrir una orden de venta
            }
        }
    }
}

void SaveSignalToCSV(string signalType, double price)
{
    static string lastSignalType = "";
    static double lastPrice = 0.0;
    static datetime lastSignalTime = 0;

    datetime currentTime = TimeCurrent();
    if (signalType == lastSignalType && fabs(price - lastPrice) < 0.01 && currentTime - lastSignalTime < 60)
    {
        // Si la señal es similar a la última y ocurrió en menos de un minuto, no la guardes
        return;
    }

    int fileHandle = FileOpen("signals.csv", FILE_WRITE|FILE_CSV|FILE_READ);
    if (fileHandle != INVALID_HANDLE)
    {
        FileSeek(fileHandle, 0, SEEK_END); // Mover al final del archivo
        FileWrite(fileHandle, TimeToString(currentTime, TIME_DATE|TIME_MINUTES), signalType, price);
        FileClose(fileHandle);

        // Actualizar la última señal registrada
        lastSignalType = signalType;
        lastPrice = price;
        lastSignalTime = currentTime;
    }
    else
    {
        Print("Error al abrir el archivo CSV: ", GetLastError());
    }
}

double GetWilliamsR(int period)
{
   double wpr[];
   ArraySetAsSeries(wpr, true);
   int wprHandle = iWPR(_Symbol, PERIOD_CURRENT, period);
   
   if(CopyBuffer(wprHandle, 0, 0, 1, wpr) > 0)
   {
      return wpr[0];
   }
   return 0.0;
}

void CheckWilliamsR()
{
   double wprValue = GetWilliamsR(ADXPeriod); // Usando un período de 14

   if(wprValue < -80) // Nivel de sobreventa
   {
      // Guardar la señal de compra en un archivo CSV
      SaveSignalToCSV("Buy Signal - Williams %R Oversold", SymbolInfoDouble(_Symbol, SYMBOL_BID));

      // Abrir una orden de compra
      if(!ExistePosicionActiva())
      {
         OpenBuy();
      }
   }
   else if (wprValue > -20) // Nivel de sobrecompra
   {
      // Guardar la señal de venta en un archivo CSV
      SaveSignalToCSV("Sell Signal - Williams %R Overbought", SymbolInfoDouble(_Symbol, SYMBOL_ASK));

      // Abrir una orden de venta
      if(!ExistePosicionActiva())
      {
         OpenSell();
      }
   }
}

double GetADXValue(int period)
{
    int adxHandle = iADX(_Symbol, PERIOD_CURRENT, period);
    double adxBuffer[];
    ArraySetAsSeries(adxBuffer, true);

    if (CopyBuffer(adxHandle, 0, 0, 1, adxBuffer) > 0)
    {
        return adxBuffer[0];
    }
    else
    {
        Print("Error al obtener el valor del ADX: ", GetLastError());
        return -1; // Devuelve un valor de error
    }
}


double CalcularStopLoss(double precioActual, ENUM_POSITION_TYPE posType)
{
    double sarValue = GetParabolicSARValue();
    if(posType == POSITION_TYPE_BUY)
    {
        // Para BUY, el SL debe estar debajo del precio actual
        return MathMin(sarValue, precioActual);
    }
    else if(posType == POSITION_TYPE_SELL)
    {
        // Para SELL, el SL debe estar encima del precio actual
        return MathMax(sarValue, precioActual);
    }
    else
    {
        return 0;
    }
}


// Modificación de CalcularTakeProfit
double CalcularTakeProfit(double precioActual, ENUM_POSITION_TYPE posType)
{
   if(posType == POSITION_TYPE_BUY)
   {
      return precioActual * (1 + TakeProfitPercent / 100.0);
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      return precioActual * (1 - TakeProfitPercent / 100.0);
   }
   else
   {
      return 0;
   }
}

//+------------------------------------------------------------------+
//| Función para verificar y ajustar el Stop Loss                    |
//+------------------------------------------------------------------+
void VerificarYModificarStopLossCritico()
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
        if(pos_symbol != Symbol())
            continue;
        
        if(!SymbolInfoTick(Symbol(), tick))
            continue;
        
        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double pos_sl = PositionGetDouble(POSITION_SL);
        double pos_tp = PositionGetDouble(POSITION_TP);
        double critical_sl = CalcularStopLossCritico(tick, pos_type);
        
        // Modificar SL si es necesario
        if (pos_sl != critical_sl)
        {
            ModifySL(pos_ticket, critical_sl, pos_tp);
        }
        
        // Verificar si el mercado está abierto antes de cerrar la posición
        if (MarketOpenHours(pos_symbol) && PosicionConBeneficio())
        {
            trade.PositionClose(pos_ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Función para calcular el Stop Loss crítico                       |
//+------------------------------------------------------------------+
double CalcularStopLossCritico(MqlTick &tick, ENUM_POSITION_TYPE posType)
{
    double critical_sl = 0.0;
    double stop_level = StopLevel(2) * Point();
    
    if(posType == POSITION_TYPE_BUY)
    {
        critical_sl = tick.bid - stop_level;
    }
    else if(posType == POSITION_TYPE_SELL)
    {
        critical_sl = tick.ask + stop_level;
    }
    
    return critical_sl;
}

//+------------------------------------------------------------------+
//| MarketOpenHours                                                  |
//+------------------------------------------------------------------+
/*bool MarketOpenHours(string sym) {
    MqlDateTime ServerTime;
    datetime ServerDateTime = TimeTradeServer();
    datetime R1S=0, R1E=0, R2S=0, R2E=0, R3S=0, R3E=0, R4S=0, R4E=0;
    TimeToStruct(ServerDateTime, ServerTime);
    ENUM_DAY_OF_WEEK today = (ENUM_DAY_OF_WEEK)ServerTime.day_of_week;

    if (!SymbolInfoSessionTrade(sym, today, 0, R1S, R1E) ||
        !SymbolInfoSessionTrade(sym, today, 1, R2S, R2E) ||
        !SymbolInfoSessionTrade(sym, today, 2, R3S, R3E) ||
        !SymbolInfoSessionTrade(sym, today, 3, R4S, R4E)) {
        return false; // Si no se pueden obtener las sesiones, el mercado está cerrado
    }

    datetime currentTime = ServerDateTime % 86400; // Obtener solo la hora del día

    return (currentTime >= R1S && currentTime <= R1E) ||
           (currentTime >= R2S && currentTime <= R2E) ||
           (currentTime >= R3S && currentTime <= R3E) ||
           (currentTime >= R4S && currentTime <= R4E);
}*/

bool MarketOpenHours(string sym) {
  bool isOpen = false;                                  // by default market is closed
  MqlDateTime mdtServerTime;                            // declare server time structure variable
  datetime dtServerDateTime = TimeTradeServer();        // store server time 
  if(!TimeToStruct(dtServerDateTime,                    // is servertime correctly converted to struct?
                   mdtServerTime)) {
    return(false);                                      // no, return market is closed
  }

  ENUM_DAY_OF_WEEK today = (ENUM_DAY_OF_WEEK)           // get actual day and cast to enum
                            mdtServerTime.day_of_week;

  if(today > 0 || today < 6) {                          // is today in monday to friday?
    datetime dtF;                                       // store trading session begin and end time
    datetime dtT;                                       // date component is 1970.01.01 (0)
    datetime dtServerTime = dtServerDateTime % 86400;   // set date to 1970.01.01 (0)
    if(!SymbolInfoSessionTrade(sym, today,              // do we have values for dtFrom and dtTo?
                               0, dtF, dtT)) {
      return(false);                                    // no, return market is closed
    }
    switch(today) {                                     // check for different trading sessions
      case 1:
        if(dtServerTime >= dtF && dtServerTime <= dtT)  // is server time in 00:05 (300) - 00:00 (86400)
          isOpen = true;                                // yes, set market is open
        break;
      case 5:
        if(dtServerTime >= dtF && dtServerTime <= dtT)  // is server time in 00:04 (240) - 23:55 (86100)
          isOpen = true;                                // yes, set market is open
        break;
      default:
        if(dtServerTime >= dtF && dtServerTime <= dtT)  // is server time in 00:04 (240) - 00:00 (86400)
          isOpen = true;                                // yes, set market is open
        break;
    }
  }
  return(isOpen);
}

//+------------------------------------------------------------------+
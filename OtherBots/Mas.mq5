//+------------------------------------------------------------------+
//|                   Bot de Trading con Medias Móviles              |
//+------------------------------------------------------------------+
#property copyright "Tu Nombre"
#property link      "tu.email@ejemplo.com"
#property version   "1.03"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

///--- Parámetros de entrada para pruebas rápidas//
input double Lots = 0.1;                  // Tamaño del lote
input double StopLoss = 10;               // Stop Loss reducido para pruebas en puntos
input double TakeProfit = 15;             // Take Profit reducido para pruebas en puntos
input int    MagicNumber = 123456;        // Número mágico para identificar las operaciones
input bool   UseSignalFilter = true;      // Usar filtro de señales
input bool   UseVolatilityFilter = false; // Desactivar filtro de volatilidad para pruebas rápidas
input double MinATRValue = 0.0005;        // Valor mínimo de ATR reducido para pruebas

//--- Manejadores de indicadores
int ma_9_h = 0;
int ma_15_h = 0;
int ma_30_h = 0;       // Media móvil para filtrar señales, ajustada a 30 periodos
int atr_handle = 0;    // Manejador para el ATR

//--- Arrays para almacenar valores de los indicadores
double ma_9_array[];
double ma_15_array[];
double ma_30_array[];
double atr_array[];

//+------------------------------------------------------------------+
//| Función de Inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Crear indicadores de medias móviles
   ma_9_h = iMA(_Symbol, _Period, 9, 0, MODE_SMA, PRICE_CLOSE);
   ma_15_h = iMA(_Symbol, _Period, 15, 0, MODE_SMA, PRICE_CLOSE);
   ma_30_h = iMA(_Symbol, _Period, 30, 0, MODE_SMA, PRICE_CLOSE); // Media móvil para tendencia

   //--- Crear el indicador ATR
   atr_handle = iATR(_Symbol, _Period, 14);

   //--- Verificar si los indicadores se crearon correctamente
   if(ma_9_h == INVALID_HANDLE || ma_15_h == INVALID_HANDLE || ma_30_h == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
     {
      Print("Error al crear los indicadores");
      return(INIT_FAILED);
     }

   //--- Configurar los arrays como series temporales
   ArraySetAsSeries(ma_9_array, true);
   ArraySetAsSeries(ma_15_array, true);
   ArraySetAsSeries(ma_30_array, true);
   ArraySetAsSeries(atr_array, true);

   //--- Establecer el Magic Number
   trade.SetExpertMagicNumber(MagicNumber);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Función de Desinicialización                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Liberar los manejadores de los indicadores
   if(ma_9_h != INVALID_HANDLE)
      IndicatorRelease(ma_9_h);
   if(ma_15_h != INVALID_HANDLE)
      IndicatorRelease(ma_15_h);
   if(ma_30_h != INVALID_HANDLE)
      IndicatorRelease(ma_30_h);
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
  }

//+------------------------------------------------------------------+
//| Función OnTick: Se ejecuta en cada tick del mercado              |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Obtener los últimos valores de las medias móviles y el ATR
   if(CopyBuffer(ma_9_h, 0, 0, 3, ma_9_array) <= 0 ||
      CopyBuffer(ma_15_h, 0, 0, 3, ma_15_array) <= 0 ||
      CopyBuffer(ma_30_h, 0, 0, 1, ma_30_array) <= 0 ||
      CopyBuffer(atr_handle, 0, 0, 1, atr_array) <= 0)
     {
      Print("Error al obtener los datos de los indicadores");
      return;
     }

   //--- Valores actuales y previos de las medias móviles y ATR
   double ma9_current = ma_9_array[0];
   double ma15_current = ma_15_array[0];
   double ma9_previous = ma_9_array[1];
   double ma15_previous = ma_15_array[1];
   double ma30_current = ma_30_array[0];
   double atr_value = atr_array[0];

   //--- Verificar el filtro de volatilidad (ATR)
   if(UseVolatilityFilter && atr_value < MinATRValue)
     {
      Print("ATR demasiado bajo, se omiten operaciones");
      return;
     }

   //--- Filtrar señales falsas si está habilitado
   if(UseSignalFilter)
     {
      //--- Solo operar en dirección de la tendencia principal (determinada por la MA de 30 periodos)
      if(ma9_current > ma30_current)
        {
         //--- Tendencia alcista: Solo considerar compras
         if(PositionSelectByMagic(_Symbol, MagicNumber))
            return; // Ya hay una posición abierta

         //--- Verificar cruce alcista
         if(ma9_previous < ma15_previous && ma9_current > ma15_current)
           {
            OpenBuy();
           }
        }
      else if(ma9_current < ma30_current)
        {
         //--- Tendencia bajista: Solo considerar ventas
         if(PositionSelectByMagic(_Symbol, MagicNumber))
            return; // Ya hay una posición abierta

         //--- Verificar cruce bajista
         if(ma9_previous > ma15_previous && ma9_current < ma15_current)
           {
            OpenSell();
           }
        }
     }
   else
     {
      //--- Sin filtro de tendencia: Operar en ambos sentidos
      if(PositionSelectByMagic(_Symbol, MagicNumber))
         return; // Ya hay una posición abierta

      //--- Verificar cruce alcista
      if(ma9_previous < ma15_previous && ma9_current > ma15_current)
        {
         OpenBuy();
        }
      //--- Verificar cruce bajista
      else if(ma9_previous > ma15_previous && ma9_current < ma15_current)
        {
         OpenSell();
        }
     }
  }

//+------------------------------------------------------------------+
//| Función para abrir posición de compra                            |
//+------------------------------------------------------------------+
void OpenBuy()
  {
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(Ask == 0)
     {
      Print("Error al obtener el precio Ask");
      return;
     }

   double sl = NormalizeDouble(Ask - StopLoss * _Point, _Digits);
   double tp = NormalizeDouble(Ask + TakeProfit * _Point, _Digits);

   if(trade.Buy(Lots, _Symbol, 0.0, sl, tp, "Compra MA Crossover"))
     {
      Print("Orden de compra abierta con éxito");
      LogOperation("Compra", Lots, sl, tp);
     }
   else
     {
      Print("Error al abrir orden de compra: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Función para abrir posición de venta                             |
//+------------------------------------------------------------------+
void OpenSell()
  {
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(Bid == 0)
     {
      Print("Error al obtener el precio Bid");
      return;
     }

   double sl = NormalizeDouble(Bid + StopLoss * _Point, _Digits);
   double tp = NormalizeDouble(Bid - TakeProfit * _Point, _Digits);

   if(trade.Sell(Lots, _Symbol, 0.0, sl, tp, "Venta MA Crossover"))
     {
      Print("Orden de venta abierta con éxito");
      LogOperation("Venta", Lots, sl, tp);
     }
   else
     {
      Print("Error al abrir orden de venta: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Función para registrar operaciones                               |
//+------------------------------------------------------------------+
void LogOperation(string tipo, double volumen, double sl, double tp)
  {
   string mensaje = StringFormat("Operación: %s, Volumen: %f, SL: %f, TP: %f, Hora: %s",
                                 tipo, volumen, sl, tp, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   Print(mensaje);

   int file_handle = FileOpen("RegistroOperaciones.csv", FILE_CSV|FILE_WRITE|FILE_READ|FILE_COMMON, ";");
   if(file_handle != INVALID_HANDLE)
     {
      FileSeek(file_handle, 0, SEEK_END);
      FileWrite(file_handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), tipo, DoubleToString(volumen, 2),
                DoubleToString(sl, _Digits), DoubleToString(tp, _Digits));
      FileClose(file_handle);
     }
   else
     {
      Print("Error al abrir el archivo de registro: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Función para seleccionar posición por Magic Number               |
//+------------------------------------------------------------------+
bool PositionSelectByMagic(string symbol, int magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == magic)
           {
            return(true);
           }
        }
     }
   return(false);
  }

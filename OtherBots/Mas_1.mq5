//+------------------------------------------------------------------+
//|                       Bot de Trading - Bandas de Bollinger       |
//+------------------------------------------------------------------+
#property copyright "Tu Nombre"
#property link      "tu.email@ejemplo.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//|                   Bot de Trading - Bandas de Bollinger           |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

//--- Parámetros de entrada
input double Lots = 0.1;                 // Tamaño del lote
input double StopLoss = 20;              // Stop Loss en puntos
input double TakeProfit = 20;            // Take Profit en puntos
input int    BollingerPeriod = 20;       // Período de Bandas de Bollinger
input double BollingerDeviation = 2.0;   // Desviación estándar para Bandas de Bollinger
input int    MagicNumber = 987654;       // Número mágico para identificar las operaciones

//--- Manejador de indicador de Bandas de Bollinger
int bollinger_handle;

//--- Arrays para almacenar valores de las Bandas de Bollinger
double upper_band[];
double middle_band[];
double lower_band[];

//+------------------------------------------------------------------+
//| Función de Inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Crear el indicador de Bandas de Bollinger
   bollinger_handle = iBands(_Symbol, _Period, BollingerPeriod, 0, BollingerDeviation, PRICE_CLOSE);

   // Verificar si el indicador se creó correctamente
   if(bollinger_handle == INVALID_HANDLE)
     {
      Print("Error al crear el indicador de Bandas de Bollinger");
      return(INIT_FAILED);
     }

   // Configurar los arrays como series temporales
   ArraySetAsSeries(upper_band, true);
   ArraySetAsSeries(middle_band, true);
   ArraySetAsSeries(lower_band, true);

   // Establecer el Magic Number
   trade.SetExpertMagicNumber(MagicNumber);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Función para obtener el volumen mínimo permitido                 |
//+------------------------------------------------------------------+
double GetMinimumVolume()
  {
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(min_volume < 0.1) min_volume = 0.1; // Valor predeterminado si no se puede obtener
   return min_volume;
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

   // Obtener el volumen mínimo permitido
   double volume = GetMinimumVolume();

   // Distancia mínima de SL y TP en puntos
   double min_distance = 5 * _Point;

   // Ajustar SL y TP para evitar errores
   double sl = NormalizeDouble(Ask - StopLoss * _Point, _Digits);
   double tp = NormalizeDouble(Ask + TakeProfit * _Point, _Digits);
   if((Ask - sl) < min_distance) sl = Ask - min_distance;
   if((tp - Ask) < min_distance) tp = Ask + min_distance;

   if(trade.Buy(volume, _Symbol, Ask, sl, tp, "Compra Bollinger"))
     {
      Print("Orden de compra abierta con éxito");
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

   // Obtener el volumen mínimo permitido
   double volume = GetMinimumVolume();

   // Distancia mínima de SL y TP en puntos
   double min_distance = 5 * _Point;

   // Ajustar SL y TP para evitar errores
   double sl = NormalizeDouble(Bid + StopLoss * _Point, _Digits);
   double tp = NormalizeDouble(Bid - TakeProfit * _Point, _Digits);
   if((sl - Bid) < min_distance) sl = Bid + min_distance;
   if((Bid - tp) < min_distance) tp = Bid - min_distance;

   if(trade.Sell(volume, _Symbol, Bid, sl, tp, "Venta Bollinger"))
     {
      Print("Orden de venta abierta con éxito");
     }
   else
     {
      Print("Error al abrir orden de venta: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Función de Desinicialización                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Liberar el manejador del indicador
   if(bollinger_handle != INVALID_HANDLE)
      IndicatorRelease(bollinger_handle);
  }

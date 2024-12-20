//+------------------------------------------------------------------+
//|                   Bot de Trading con Medias Móviles              |
//+------------------------------------------------------------------+
#property copyright "Tu Nombre"
#property link      "tu.email@ejemplo.com"
#property version   "1.04"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Parámetros de entrada para pruebas rápidas
input double Lots = 0.1;                  // Tamaño del lote
input int    MagicNumber = 123456;        // Número mágico para identificar las operaciones
input bool   UseSignalFilter = true;      // Usar filtro de señales
input bool   UseVolatilityFilter = false; // Desactivar filtro de volatilidad para pruebas rápidas
input double MinATRValue = 0.0005;        // Valor mínimo de ATR reducido para pruebas

// Manejadores de indicadores
int ma_9_h = 0;
int ma_15_h = 0;
int ma_30_h = 0;
int atr_handle = 0;

// Arrays para almacenar valores de los indicadores
double ma_9_array[];
double ma_15_array[];
double ma_30_array[];
double atr_array[];

// Variables de control de precios y estados
double precioBase = 0.0;
double stopLossActual = 0.0;
double takeProfitActual = 0.0;
bool operacionActiva = false;
int direccionUltimaOperacion = 0; // 1 para compra, -1 para venta

//+------------------------------------------------------------------+
//| Función de Inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   // Crear indicadores de medias móviles
   ma_9_h = iMA(_Symbol, _Period, 9, 0, MODE_SMA, PRICE_CLOSE);
   ma_15_h = iMA(_Symbol, _Period, 15, 0, MODE_SMA, PRICE_CLOSE);
   ma_30_h = iMA(_Symbol, _Period, 30, 0, MODE_SMA, PRICE_CLOSE);
   atr_handle = iATR(_Symbol, _Period, 14);

   // Verificar si los indicadores se crearon correctamente
   if(ma_9_h == INVALID_HANDLE || ma_15_h == INVALID_HANDLE || ma_30_h == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
   {
      Print("Error al crear los indicadores");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(ma_9_array, true);
   ArraySetAsSeries(ma_15_array, true);
   ArraySetAsSeries(ma_30_array, true);
   ArraySetAsSeries(atr_array, true);

   trade.SetExpertMagicNumber(MagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Función OnTick: Se ejecuta en cada tick del mercado              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(CopyBuffer(ma_9_h, 0, 0, 3, ma_9_array) <= 0 ||
      CopyBuffer(ma_15_h, 0, 0, 3, ma_15_array) <= 0 ||
      CopyBuffer(ma_30_h, 0, 0, 1, ma_30_array) <= 0 ||
      CopyBuffer(atr_handle, 0, 0, 1, atr_array) <= 0)
   {
      Print("Error al obtener los datos de los indicadores");
      return;
   }

   double ma9_current = ma_9_array[0];
   double ma15_current = ma_15_array[0];
   double ma9_previous = ma_9_array[1];
   double ma15_previous = ma_15_array[1];
   double ma30_current = ma_30_array[0];

   // Verificar condiciones para nuevas órdenes si no hay una operación activa
   if(!operacionActiva)
   {
      if(UseSignalFilter)
      {
         if(ma9_current > ma30_current && ma9_previous < ma15_previous && ma9_current > ma15_current)
            OpenBuy();
         else if(ma9_current < ma30_current && ma9_previous > ma15_previous && ma9_current < ma15_current)
            OpenSell();
      }
   }
   else
   {
      // Verificar si se alcanzó el Take Profit o el Stop Loss
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(direccionUltimaOperacion == 1 && currentPrice >= takeProfitActual) // Si fue una compra y se alcanzó el TP
      {
         ClosePosition();
         Print("Ganancia alcanzada en compra, abriendo nueva operación de compra.");
         OpenBuy(); // Reabrir una nueva operación de compra con el precio actual como precio base
      }
      else if(direccionUltimaOperacion == -1 && currentPrice <= takeProfitActual) // Si fue una venta y se alcanzó el TP
      {
         ClosePosition();
         Print("Ganancia alcanzada en venta, abriendo nueva operación de venta.");
         OpenSell(); // Reabrir una nueva operación de venta con el precio actual como precio base
      }
      else if(currentPrice <= stopLossActual && direccionUltimaOperacion == 1) // SL en compra
      {
         ClosePosition();
         Print("Pérdida alcanzada en compra, esperando nuevas condiciones.");
         operacionActiva = false;
      }
      else if(currentPrice >= stopLossActual && direccionUltimaOperacion == -1) // SL en venta
      {
         ClosePosition();
         Print("Pérdida alcanzada en venta, esperando nuevas condiciones.");
         operacionActiva = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Función para abrir posición de compra                            |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(Ask == 0) return;

   precioBase = Ask;
   stopLossActual = NormalizeDouble(precioBase * (1 - 0.03), _Digits);  // SL a 3% por debajo
   takeProfitActual = NormalizeDouble(precioBase * (1 + 0.20), _Digits); // TP a 20% por encima

   if(trade.Buy(Lots, _Symbol, Ask, stopLossActual, takeProfitActual, "Compra Inicial"))
   {
      Print("Compra abierta con éxito: SL=", stopLossActual, " TP=", takeProfitActual);
      operacionActiva = true;
      direccionUltimaOperacion = 1;
   }
   else
      Print("Error al abrir compra: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Función para abrir posición de venta                             |
//+------------------------------------------------------------------+
void OpenSell()
{
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(Bid == 0) return;

   precioBase = Bid;
   stopLossActual = NormalizeDouble(precioBase * (1 + 0.03), _Digits);  // SL a 3% por encima
   takeProfitActual = NormalizeDouble(precioBase * (1 - 0.20), _Digits); // TP a 20% por debajo

   if(trade.Sell(Lots, _Symbol, Bid, stopLossActual, takeProfitActual, "Venta Inicial"))
   {
      Print("Venta abierta con éxito: SL=", stopLossActual, " TP=", takeProfitActual);
      operacionActiva = true;
      direccionUltimaOperacion = -1;
   }
   else
      Print("Error al abrir venta: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Función para cerrar posición abierta                             |
//+------------------------------------------------------------------+
void ClosePosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         ulong ticket = PositionGetTicket(i);
         trade.PositionClose(ticket);
         Print("Posición cerrada: Ticket=", ticket);
      }
   }
   operacionActiva = false; // Reiniciar para permitir nuevas órdenes
}

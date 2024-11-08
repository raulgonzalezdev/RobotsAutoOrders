//+------------------------------------------------------------------+
//|                                             TrailingBySAR_03.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#define   SAR_DATA_INDEX   1  // bar we get Parabolic SAR data from

#include "TrailingsFunc.mqh"

//--- input parameters
input ENUM_TIMEFRAMES   InpTimeframeSAR   =  PERIOD_CURRENT;   // Parabolic SAR Timeframe
input double            InpStepSAR        =  0.02;             // Parabolic SAR Step
input double            InpMaximumSAR     =  0.2;              // Parabolic SAR Maximum
input long              InpMagic          =  123;              // Expert Magic Number

//--- global variables
int   ExtHandleSAR=INVALID_HANDLE;  // Parabolic SAR handle

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create Parabolic SAR handle
   ExtHandleSAR=CreateSAR(Symbol(), InpTimeframeSAR, InpStepSAR, InpMaximumSAR);
   
//--- if there is an error creating the indicator, exit OnInit with an error
   if(ExtHandleSAR==INVALID_HANDLE)
      return(INIT_FAILED);

//--- successful
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- if not a new bar, leave the handler
   if(!IsNewBar())
      return;
      
//--- trail position stops by Parabolic SAR
   TrailingByDataInd(ExtHandleSAR, SAR_DATA_INDEX, InpMagic);
  }
//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
      TrailingByDataInd(ExtHandleSAR, SAR_DATA_INDEX, InpMagic);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                             TrailingBySAR_01.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#define   SAR_DATA_INDEX   1  // bar we get Parabolic SAR data from

//--- input parameters
input ENUM_TIMEFRAMES   InpTimeframeSAR   =  PERIOD_CURRENT;   // Parabolic SAR Timeframe
input double            InpStepSAR        =  0.02;             // Parabolic SAR Step
input double            InpMaximumSAR     =  0.2;              // Parabolic SAR Maximum

//--- global variables
int      ExtHandleSAR =INVALID_HANDLE;    // Parabolic SAR handle
double   ExtStepSAR   =0;                 // Parabolic SAR step
double   ExtMaximumSAR=0;                 // Parabolic SAR maximum

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- set the Parabolic SAR parameters within acceptable limits
   ExtStepSAR   =(InpStepSAR<0.0001 ? 0.0001 : InpStepSAR);
   ExtMaximumSAR=(InpMaximumSAR<0.0001 ? 0.0001 : InpMaximumSAR);
   
//--- if there is an error creating the indicator, display a message in the journal and exit from OnInit with an error
   ExtHandleSAR =iSAR(Symbol(), InpTimeframeSAR, ExtStepSAR, ExtMaximumSAR);
   if(ExtHandleSAR==INVALID_HANDLE)
     {
      PrintFormat("Failed to create iSAR(%s, %s, %.3f, %.2f) handle. Error %d",
                  Symbol(), TimeframeDescription(InpTimeframeSAR), ExtStepSAR, ExtMaximumSAR, GetLastError());
      return(INIT_FAILED);
     }   
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
   TrailingStopBySAR();
  }
//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
      TrailingStopBySAR();
  }
//+------------------------------------------------------------------+
//| Return timeframe description                                     |
//+------------------------------------------------------------------+
string TimeframeDescription(const ENUM_TIMEFRAMES timeframe)
  {
   return(StringSubstr(EnumToString(timeframe==PERIOD_CURRENT ? Period() : timeframe), 7));
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
//| Return Parabolic SAR data from the specified timeseries index    |
//+------------------------------------------------------------------+
double GetSARData(const int index)
  {
   double array[1];
   ResetLastError();
   if(CopyBuffer(ExtHandleSAR, 0, index, 1, array)!=1)
     {
      PrintFormat("%s: CopyBuffer() failed. Error %d", __FUNCTION__, GetLastError());
      return EMPTY_VALUE;
     }
   return array[0];
  }
//+------------------------------------------------------------------+
//| Return StopLevel value of the current symbol in points           |
//+------------------------------------------------------------------+
int StopLevel(const int spread_multiplier)
  {
   int spread    =(int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   int stop_level=(int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
   return(stop_level==0 ? spread * spread_multiplier : stop_level);
  }
//+------------------------------------------------------------------+
//| Trailing stop function by StopLoss price value                   |
//+------------------------------------------------------------------+
void TrailingStopByValue(const double value_sl, const long magic=-1, const int trailing_step_pt=0, const int trailing_start_pt=0)
  {
//--- price structure
   MqlTick tick={};
//--- in a loop by the total number of open positions
   int total=PositionsTotal();
   for(int i=total-1; i>=0; i--)
     {
      //--- get the ticket of the next position
      ulong  pos_ticket=PositionGetTicket(i);
      if(pos_ticket==0)
         continue;
         
      //--- get the symbol and position magic
      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      long   pos_magic  = PositionGetInteger(POSITION_MAGIC);
      
      //--- skip positions that do not match the filter by symbol and magic number
      if((magic!=-1 && pos_magic!=magic) || pos_symbol!=Symbol())
         continue;
         
      //--- if failed to get the prices, move on
      if(!SymbolInfoTick(Symbol(), tick))
         continue;
      
      //--- get the position type, its opening price and StopLoss level
      ENUM_POSITION_TYPE pos_type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             pos_open=PositionGetDouble(POSITION_PRICE_OPEN);
      double             pos_sl  =PositionGetDouble(POSITION_SL);
      
      //--- if StopLoss modification conditions are suitable, modify the position stop level
      if(CheckCriterion(pos_type, pos_open, pos_sl, value_sl, trailing_step_pt, trailing_start_pt, tick))
         ModifySL(pos_ticket, value_sl);
     }
  }
//+------------------------------------------------------------------+
//|Check the StopLoss modification criteria and return a flag        |
//+------------------------------------------------------------------+
bool CheckCriterion(ENUM_POSITION_TYPE pos_type, double pos_open, double pos_sl, double value_sl, 
                    int trailing_step_pt, int trailing_start_pt, MqlTick &tick)
  {
//--- if the stop position and the stop level for modification are equal, return 'false'
   if(NormalizeDouble(pos_sl-value_sl, Digits())==0)
      return false;

   double trailing_step = trailing_step_pt * Point(); // convert the trailing step into price
   double stop_level    = StopLevel(2) * Point();     // convert the StopLevel of the symbol into price
   int    pos_profit_pt = 0;                          // position profit in points
   
//--- depending on the type of position, check the conditions for modifying StopLoss
   switch(pos_type)
     {
      //--- long position
      case POSITION_TYPE_BUY :
        pos_profit_pt=int((tick.bid - pos_open) / Point());             // calculate the position profit in points
        if(tick.bid - stop_level > value_sl                             // if the price and the StopLevel level pending from it are higher than the StopLoss level (the distance to StopLevel is observed)
           && pos_sl + trailing_step < value_sl                         // if the StopLoss level exceeds the trailing step based on the current StopLoss
           && (trailing_start_pt==0 || pos_profit_pt>trailing_start_pt) // if we trail at any profit or position profit in points exceeds the trailing start, return 'true'
          )
           return true;
        break;
        
      //--- short position
      case POSITION_TYPE_SELL :
        pos_profit_pt=int((pos_open - tick.ask) / Point());             // calculate position profit in points
        if(tick.ask + stop_level < value_sl                             // if the price and the StopLevel level pending from it are lower than the StopLoss level (the distance to StopLevel is observed)
           && (pos_sl - trailing_step > value_sl || pos_sl==0)          // if the StopLoss level is below the trailing step based on the current StopLoss or a position has no StopLoss
           && (trailing_start_pt==0 || pos_profit_pt>trailing_start_pt) // if we trail at any profit or position profit in points exceeds the trailing start, return 'true'
          )
           return true;
        break;
        
      //--- return 'false' by default
      default: break;
     }
//--- no matching criteria
   return false;
  }
//+------------------------------------------------------------------+
//| Modify StopLoss of a position by ticket                          |
//+------------------------------------------------------------------+
bool ModifySL(const ulong ticket, const double stop_loss)
  {
//--- if failed to select a position by ticket, report this in the journal and return 'false'
   ResetLastError();
   if(!PositionSelectByTicket(ticket))
     {
      PrintFormat("%s: Failed to select position by ticket number %I64u. Error %d", __FUNCTION__, ticket, GetLastError());
      return false;
     }
     
//--- declare the structures of the trade request and the request result
   MqlTradeRequest   request={};
   MqlTradeResult    result ={};
   
//--- fill in the request structure
   request.action    = TRADE_ACTION_SLTP;
   request.symbol    = PositionGetString(POSITION_SYMBOL);
   request.magic     = PositionGetInteger(POSITION_MAGIC);
   request.tp        = PositionGetDouble(POSITION_TP);
   request.position  = ticket;
   request.sl        = NormalizeDouble(stop_loss,(int)SymbolInfoInteger(Symbol(),SYMBOL_DIGITS));
   
//--- if the trade operation could not be sent, report this to the journal and return 'false'
   if(!OrderSend(request, result))
     {
      PrintFormat("%s: OrderSend() failed to modify position #%I64u. Error %d",__FUNCTION__, ticket, GetLastError());
      return false;
     }
     
//--- request to change StopLoss position successfully sent
   return true;
  }
//+------------------------------------------------------------------+
//| StopLoss trailing function using the Parabolic SAR indicator     |
//+------------------------------------------------------------------+
void TrailingStopBySAR(const long magic=-1, const int trailing_step_pt=0, const int trailing_start_pt=0)
  {
//--- get the Parabolic SAR value from the first bar of the timeseries
   double sar=GetSARData(SAR_DATA_INDEX);
   
//--- if failed to obtain data, leave
   if(sar==EMPTY_VALUE)
      return;
      
//--- call the universal trailing function with the StopLoss price obtained from Parabolic SAR 
   TrailingStopByValue(sar, magic, trailing_step_pt, trailing_start_pt);
  }
//+------------------------------------------------------------------+

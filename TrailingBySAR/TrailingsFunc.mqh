//+------------------------------------------------------------------+
//|                                                TrailingsFunc.mqh |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
//+------------------------------------------------------------------+
//| Simple trailing by value                                         |
//+------------------------------------------------------------------+
void SimpleTrailingByValue(const double value_sl, const long magic=-1,
                           const int trailing_step_pt=0, const int trailing_start_pt=0, const int trailing_offset_pt=0)
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
   MqlTradeRequest    request={};
   MqlTradeResult     result ={};
   
//--- fill in the request structure
   request.action    = TRADE_ACTION_SLTP;
   request.symbol    = PositionGetString(POSITION_SYMBOL);
   request.magic     = PositionGetInteger(POSITION_MAGIC);
   request.tp        = PositionGetDouble(POSITION_TP);
   request.position  = ticket;
   request.sl        = NormalizeDouble(stop_loss,(int)SymbolInfoInteger(request.symbol,SYMBOL_DIGITS));
   
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
//| Return StopLevel in points                                       |
//+------------------------------------------------------------------+
int StopLevel(const int spread_multiplier)
  {
   int spread    =(int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   int stop_level=(int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
   return(stop_level==0 ? spread * spread_multiplier : stop_level);
  }
//+------------------------------------------------------------------+
//| Return timeframe description                                     |
//+------------------------------------------------------------------+
string TimeframeDescription(const ENUM_TIMEFRAMES timeframe)
  {
   return(StringSubstr(EnumToString(timeframe==PERIOD_CURRENT ? Period() : timeframe), 7));
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
//| Return indicator data by handle                                  |
//| from the specified timeseries index                              |
//+------------------------------------------------------------------+
double GetIndData(const int handle_ind, const int index)
  {
   double array[1];
   ResetLastError();
   if(CopyBuffer(handle_ind, 0, index, 1, array)!=1)
     {
      PrintFormat("%s: CopyBuffer() failed. Error %d", __FUNCTION__, GetLastError());
      return EMPTY_VALUE;
     }
   return array[0];
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Trailing by indicator data specified by handle                   |
//+------------------------------------------------------------------+
void TrailingByDataInd(const int handle_ind, const int index=1, const long magic=-1,
                       const int trailing_step_pt=0, const int trailing_start_pt=0, const int trailing_offset_pt=0)
  {
//--- get the Parabolic SAR value from the specified timeseries index
   double data=GetIndData(handle_ind, index);
   
//--- if failed to obtain data, leave
   if(data==EMPTY_VALUE)
      return;
      
//--- call the simple trailing function with the StopLoss price obtained from Parabolic SAR 
   SimpleTrailingByValue(data, magic, trailing_step_pt, trailing_start_pt, trailing_offset_pt);
  }
//+------------------------------------------------------------------+
//| Create and return the Parabolic SAR handle                       |
//+------------------------------------------------------------------+
int CreateSAR(const string symbol_name, const ENUM_TIMEFRAMES timeframe, const double step_sar=0.02, const double max_sar=0.2)
  {
//--- set the indicator parameters within acceptable limits
   double step=(step_sar<0.0001 ? 0.0001 : step_sar);
   double max =(max_sar <0.0001 ? 0.0001 : max_sar);

//--- adjust the symbol and timeframe values
   ENUM_TIMEFRAMES period=(timeframe==PERIOD_CURRENT ? Period() : timeframe);
   string          symbol=(symbol_name==NULL || symbol_name=="" ? Symbol() : symbol_name);
 
//--- create indicator handle
   ResetLastError();
   int handle=iSAR(symbol, period, step, max);
   
//--- if there is an error creating the indicator, display an error message in the journal
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("Failed to create iSAR(%s, %s, %.3f, %.2f) handle. Error %d",
                  symbol, TimeframeDescription(period), step, max, GetLastError());
     } 
//--- return the result of creating the indicator handle
   return handle;
  }
//+------------------------------------------------------------------+
//| Create and return Adaptive Moving Average handle                 |
//+------------------------------------------------------------------+
int CreateAMA(const string symbol_name, const ENUM_TIMEFRAMES timeframe,
              const int ama_period=9, const int fast_ema_period=2, const int slow_ema_period=30, const int shift=0, const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
  {
//--- set the indicator parameters within acceptable limits
   int ma_period=(ama_period<1 ? 9 : ama_period);
   int fast_ema=(fast_ema_period<1 ? 2 : fast_ema_period);
   int slow_ema=(slow_ema_period<1 ? 30 : slow_ema_period);

//--- adjust the symbol and timeframe values
   ENUM_TIMEFRAMES period=(timeframe==PERIOD_CURRENT ? Period() : timeframe);
   string          symbol=(symbol_name==NULL || symbol_name=="" ? Symbol() : symbol_name);
 
//--- create indicator handle
   ::ResetLastError();
   int handle=::iAMA(symbol, period, ma_period, fast_ema, slow_ema, shift, price);
   
//--- if there is an error creating the indicator, display an error message in the journal
   if(handle==INVALID_HANDLE)
     {
      ::PrintFormat("Failed to create iAMA(%s, %s, %d, %d, %d, %s) handle. Error %d",
                    symbol, TimeframeDescription(period), ma_period, fast_ema, slow_ema,
                    ::StringSubstr(::EnumToString(price),6), ::GetLastError());
     }
//--- return the result of creating the indicator handle
   return handle;
  }
//+------------------------------------------------------------------+
//| Create and return Double Exponential Moving Average handle       |
//+------------------------------------------------------------------+
int CreateDEMA(const string symbol_name, const ENUM_TIMEFRAMES timeframe,
               const int dema_period=14, const int shift=0, const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
  {
//--- set the indicator parameters within acceptable limits
   int ma_period=(dema_period<1 ? 14 : dema_period);

//--- adjust the symbol and timeframe values
   ENUM_TIMEFRAMES period=(timeframe==PERIOD_CURRENT ? Period() : timeframe);
   string          symbol=(symbol_name==NULL || symbol_name=="" ? Symbol() : symbol_name);
 
//--- create indicator handle
   ::ResetLastError();
   int handle=::iDEMA(symbol, period, ma_period, shift, price);
   
//--- if there is an error creating the indicator, display an error message in the journal
   if(handle==INVALID_HANDLE)
     {
      ::PrintFormat("Failed to create iDEMA(%s, %s, %d, %s) handle. Error %d",
                    symbol, TimeframeDescription(period), ma_period,
                    ::StringSubstr(::EnumToString(price),6), ::GetLastError());
     }
//--- return the result of creating the indicator handle
   return handle;
  }
//+------------------------------------------------------------------+
//| Create and return Adaptive Moving Average handle                 |
//+------------------------------------------------------------------+
int CreateFRAMA(const string symbol_name, const ENUM_TIMEFRAMES timeframe,
                const int frama_period=14, const int shift=0, const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
  {
//--- set the indicator parameters within acceptable limits
   int ma_period=(frama_period<1 ? 14 : frama_period);

//--- adjust the symbol and timeframe values
   ENUM_TIMEFRAMES period=(timeframe==PERIOD_CURRENT ? Period() : timeframe);
   string          symbol=(symbol_name==NULL || symbol_name=="" ? Symbol() : symbol_name);
 
//--- create indicator handle
   ::ResetLastError();
   int handle=::iFrAMA(symbol, period, ma_period, shift, price);
   
//--- if there is an error creating the indicator, display an error message in the journal
   if(handle==INVALID_HANDLE)
     {
      ::PrintFormat("Failed to create iFrAMA(%s, %s, %d, %s) handle. Error %d",
                    symbol, TimeframeDescription(period), ma_period,
                    ::StringSubstr(::EnumToString(price),6), ::GetLastError());
     }
//--- return the result of creating the indicator handle
   return handle;
  }
//+------------------------------------------------------------------+
//| Create and return Moving Average handle                          |
//+------------------------------------------------------------------+
int CreateMA(const string symbol_name, const ENUM_TIMEFRAMES timeframe,
             const int period_ma=10, const int shift=0, const ENUM_MA_METHOD method=MODE_SMA, const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
  {
//--- set the indicator parameters within acceptable limits
   int ma_period=(period_ma<1 ? 14 : period_ma);

//--- adjust the symbol and timeframe values
   ENUM_TIMEFRAMES period=(timeframe==PERIOD_CURRENT ? Period() : timeframe);
   string          symbol=(symbol_name==NULL || symbol_name=="" ? Symbol() : symbol_name);
 
//--- create indicator handle
   ::ResetLastError();
   int handle=::iMA(symbol, period, ma_period, shift, method, price);
   
//--- if there is an error creating the indicator, display an error message in the journal
   if(handle==INVALID_HANDLE)
     {
      ::PrintFormat("Failed to create iMA(%s, %s, %d, %s, %s) handle. Error %d",
                    symbol, TimeframeDescription(period), ma_period,
                    ::StringSubstr(::EnumToString(method),5),
                    ::StringSubstr(::EnumToString(price),6), ::GetLastError());
     }
//--- return the result of creating the indicator handle
   return handle;
  }
//+------------------------------------------------------------------+
//| Create and return Triple Exponential Moving Average handle       |
//+------------------------------------------------------------------+
int CreateTEMA(const string symbol_name, const ENUM_TIMEFRAMES timeframe,
               const int tema_period=14, const int shift=0, const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
  {
//--- set the indicator parameters within acceptable limits
   int ma_period=(tema_period<1 ? 14 : tema_period);

//--- adjust the symbol and timeframe values
   ENUM_TIMEFRAMES period=(timeframe==PERIOD_CURRENT ? Period() : timeframe);
   string          symbol=(symbol_name==NULL || symbol_name=="" ? Symbol() : symbol_name);
 
//--- create indicator handle
   ::ResetLastError();
   int handle=::iTEMA(symbol, period, ma_period, shift, price);
   
//--- if there is an error creating the indicator, display an error message in the journal
   if(handle==INVALID_HANDLE)
     {
      ::PrintFormat("Failed to create iTEMA(%s, %s, %d, %s) handle. Error %d",
                    symbol, TimeframeDescription(period), ma_period,
                    ::StringSubstr(::EnumToString(price),6), ::GetLastError());
     }
//--- return the result of creating the indicator handle
   return handle;
  }
//+------------------------------------------------------------------+
//| Create and return Variable Index Dynamyc Average handle          |
//+------------------------------------------------------------------+
int CreateVIDYA(const string symbol_name, const ENUM_TIMEFRAMES timeframe,
                const int period_cmo=9, const int period_ema=12, const int shift=0, const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
  {
//--- set the indicator parameters within acceptable limits
   int ma_period =(period_cmo<1 ?  9 : period_cmo);
   int ema_period=(period_ema<1 ? 12 : period_ema);

//--- adjust the symbol and timeframe values
   ENUM_TIMEFRAMES period=(timeframe==PERIOD_CURRENT ? Period() : timeframe);
   string          symbol=(symbol_name==NULL || symbol_name=="" ? Symbol() : symbol_name);
 
//--- create indicator handle
   ::ResetLastError();
   int handle=::iVIDyA(symbol, period, ma_period, ema_period, shift, price);
   
//--- if there is an error creating the indicator, display an error message in the journal
   if(handle==INVALID_HANDLE)
     {
      ::PrintFormat("Failed to create iVIDyA(%s, %s, %d, %d, %s) handle. Error %d",
                    symbol, TimeframeDescription(period), ma_period, ema_period,
                    ::StringSubstr(::EnumToString(price),6), ::GetLastError());
     }
//--- return the result of creating the indicator handle
   return handle;
  }
//+------------------------------------------------------------------+

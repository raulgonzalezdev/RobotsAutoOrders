#property strict
#include <sqlite.mqh>

// Estructura para los datos de la orden
struct OrderData {
    string symbol;
    long ticket;
    datetime open_time;
    ENUM_POSITION_TYPE type;
    double volume;
    double open_price;
    double stop_loss;
    double take_profit;
    double close_price;
    double profit;
    string motivo; // Nuevo campo para registrar el motivo del registro
};

// Función para inicializar SQLite
int OnInit() {
    if (!sqlite_init()) {
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

// Función para cerrar SQLite
void OnDeinit(const int reason) {
    sqlite_finalize();
}

// Función para verificar si una tabla existe
bool do_check_table_exists(string db, string table) {
    int res = sqlite_table_exists(db, table);
    if (res < 0) {
        PrintFormat("Check for table existence failed with code %d", res);
        return false;
    }
    return (res > 0);
}

// Función para ejecutar una instrucción SQL
void do_exec(string db, string exp) {
    int res = sqlite_exec(db, exp);
    if (res != 0) {
        PrintFormat("Expression '%s' failed with code %d", exp, res);
    }
}

// Función para inicializar la base de datos y crear la tabla si no existe
void InitDatabase() {
    string dbPath = "AutoOrderBot.db";
    if (!do_check_table_exists(dbPath, "Orders")) {
        do_exec(dbPath,
            "CREATE TABLE IF NOT EXISTS Orders ("
            "Symbol TEXT, Ticket INTEGER, OpenTime INTEGER, "
            "Type INTEGER, Volume REAL, OpenPrice REAL, StopLoss REAL, "
            "TakeProfit REAL, ClosePrice REAL, Profit REAL, Motivo TEXT);");
    }
}

// Función para registrar una orden en la base de datos
void RegistrarOrdenEnBD(OrderData &order) {
    string dbPath = "AutoOrderBot.db";
    string sql = "INSERT INTO Orders (Symbol, Ticket, OpenTime, Type, Volume, "
                 "OpenPrice, StopLoss, TakeProfit, ClosePrice, Profit, Motivo) "
                 "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
    int cols[1];
    int handle = sqlite_query(dbPath, sql, cols);
    if (handle < 0) {
        Print("Preparing query failed; query=", sql, ", error=", -handle);
        return;
    }

    // Vincular parámetros a la declaración
    sqlite_bind_text(handle, 1, order.symbol);
    sqlite_bind_int64(handle, 2, order.ticket);
    sqlite_bind_int64(handle, 3, (long)order.open_time);
    sqlite_bind_int(handle, 4, (int)order.type);
    sqlite_bind_double(handle, 5, order.volume);
    sqlite_bind_double(handle, 6, order.open_price);
    sqlite_bind_double(handle, 7, order.stop_loss);
    sqlite_bind_double(handle, 8, order.take_profit);
    sqlite_bind_double(handle, 9, order.close_price);
    sqlite_bind_double(handle, 10, order.profit);
    sqlite_bind_text(handle, 11, order.motivo);

    // Ejecutar la declaración y verificar el resultado
   /* if (sqlite_next_row(handle) != SQLITE_DONE) {
        Print("Error al insertar datos en la base de datos");
    }*/

    sqlite_free_query(handle);
}

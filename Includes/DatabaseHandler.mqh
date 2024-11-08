#include <SQLite3/SQLite3.mqh>
#include <SQLite3/Statement.mqh>

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
void InitSQLite() {
    SQLite3::initialize();
}

// Función para cerrar SQLite
void ShutdownSQLite() {
    SQLite3::shutdown();
}

// Función para inicializar la base de datos y crear la tabla si no existe
void InitDatabase() {
#ifdef __MQL5__
    string dbPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\AutoOrderBot.db";
#else
    string dbPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL4\\Files\\AutoOrderBot.db";
#endif

    SQLite3 db(dbPath, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE);
    if (!db.isValid()) {
        Print("Error al abrir la base de datos: ", db.getErrorMsg());
        return;
    }

    // Crear la tabla de órdenes si no existe
    string sql = "CREATE TABLE IF NOT EXISTS Orders ("
                 "Symbol TEXT, Ticket INTEGER, OpenTime INTEGER, "
                 "Type INTEGER, Volume REAL, OpenPrice REAL, StopLoss REAL, "
                 "TakeProfit REAL, ClosePrice REAL, Profit REAL, Motivo TEXT);";
    Statement stmt(db, sql);

    if (!stmt.isValid()) {
        Print("Error en la creación de la tabla: ", db.getErrorMsg());
        return;
    }

    if (stmt.step() != SQLITE_DONE) {
        Print("Error al ejecutar la creación de la tabla: ", db.getErrorMsg());
    }
}

// Función para registrar una orden en la base de datos
void RegistrarOrdenEnBD(OrderData &order) {
#ifdef __MQL5__
    string dbPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\AutoOrderBot.db";
#else
    string dbPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL4\\Files\\AutoOrderBot.db";
#endif

    SQLite3 db(dbPath, SQLITE_OPEN_READWRITE);
    if (!db.isValid()) {
        Print("Error al abrir la base de datos: ", db.getErrorMsg());
        return;
    }

    // Preparar la declaración SQL para insertar una orden
    string sql = "INSERT INTO Orders (Symbol, Ticket, OpenTime, Type, Volume, "
                 "OpenPrice, StopLoss, TakeProfit, ClosePrice, Profit, Motivo) "
                 "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
    Statement stmt(db, sql);

    if (!stmt.isValid()) {
        Print("Error en la preparación de la declaración: ", db.getErrorMsg());
        return;
    }

    // Vincular parámetros a la declaración
    stmt.bind(1, order.symbol);
    stmt.bind(2, order.ticket);
    stmt.bind(3, (long)order.open_time);
    stmt.bind(4, (int)order.type);
    stmt.bind(5, order.volume);
    stmt.bind(6, order.open_price);
    stmt.bind(7, order.stop_loss);
    stmt.bind(8, order.take_profit);
    stmt.bind(9, order.close_price);
    stmt.bind(10, order.profit);
    stmt.bind(11, order.motivo);

    // Ejecutar la declaración y verificar el resultado
    if (stmt.step() != SQLITE_DONE) {
        Print("Error al insertar datos en la base de datos: ", db.getErrorMsg());
    }
}

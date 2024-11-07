# AutoOrderBot

AutoOrderBot es un sistema automatizado de trading desarrollado en MQL5 que utiliza análisis de mercado, gestión de riesgos y manejo de operaciones para ejecutar órdenes de compra y venta en el mercado financiero.

## Características

- **Análisis de Mercado**: Utiliza medias móviles para determinar tendencias alcistas.
- **Gestión de Riesgos**: Calcula el tamaño del lote basado en la volatilidad y gestiona el riesgo por operación.
- **Manejo de Operaciones**: Abre y cierra posiciones basadas en condiciones predefinidas.
- **Trailing Stop**: Opción para ajustar automáticamente el Stop Loss utilizando el indicador Parabolic SAR.
- **Base de Datos**: Registra las operaciones en una base de datos SQLite para análisis posterior.

## Requisitos

- MetaTrader 5
- Conexión a Internet
- Biblioteca SQLite3 para MQL5

## Instalación

1. **Clonar el repositorio**:
   ```bash
   git clone https://github.com/raulgonzalezdev/RobotsAutoOrders.git
   ```

2. **Copiar archivos**:
   - Copia los archivos `.mqh` y `.mq5` en la carpeta `MQL5/Experts` de tu instalación de MetaTrader 5.

3. **Configurar MetaTrader 5**:
   - Asegúrate de que la biblioteca SQLite3 esté instalada y accesible desde MetaTrader 5.

## Uso del AutoOrderBot

Para utilizar el AutoOrderBot, sigue los pasos a continuación para anexarlo a un gráfico en MetaTrader 5 y configurar los parámetros de entrada según tus necesidades de trading.

### Anexar el Bot a un Gráfico

1. **Abrir MetaTrader 5**: Inicia tu plataforma MetaTrader 5.

2. **Seleccionar un Gráfico**: Abre el gráfico del símbolo en el que deseas ejecutar el bot.

3. **Navegar a la Carpeta de Expertos**: En el panel de "Navegador", expande la carpeta "Expertos" y busca `AutoOrderBot`.

4. **Anexar al Gráfico**: Arrastra y suelta `AutoOrderBot` en el gráfico seleccionado.

### Configurar Parámetros de Entrada

Al anexar el bot al gráfico, se abrirá una ventana de configuración donde puedes ajustar los siguientes parámetros de entrada:

- **RiskPercent**: Porcentaje del capital que deseas arriesgar en cada operación. Valor predeterminado: `1.0`.
- **MagicNumber**: Número mágico para identificar las operaciones del bot. Valor predeterminado: `123456`.
- **StopLossPercent**: Porcentaje del precio de compra o venta para establecer el Stop Loss. Valor predeterminado: `2.0`.
- **TakeProfitPercent**: Porcentaje del precio de compra o venta para establecer el Take Profit. Valor predeterminado: `10.0`.
- **FixedVolume**: Si es `true`, se usará un volumen fijo de 1 lote. Si es `false`, el volumen se calculará automáticamente. Valor predeterminado: `true`.
- **UmbralCercaniaSL**: Umbral de cercanía al Stop Loss en porcentaje. Valor predeterminado: `0.2`.
- **PerdidaMaxima**: Pérdida máxima permitida para cerrar la posición. Valor predeterminado: `-100.0`.
- **PauseAfterStopLoss**: Tiempo de pausa en minutos después de cerrar una posición por Stop Loss. Valor predeterminado: `15`.
- **AllowSellOrders**: Permitir órdenes de venta en tendencias bajistas. Valor predeterminado: `false`.
- **MaxConsecutiveWins**: Número máximo de ganancias consecutivas antes de pausar. Valor predeterminado: `4`.
- **PauseAfterWins**: Tiempo de pausa en minutos después de alcanzar el número máximo de ganancias consecutivas. Valor predeterminado: `15`.
- **ProfitTarget**: Ganancia objetivo para cerrar la posición. Valor predeterminado: `20.0`.
- **UseTrailingStop**: Habilitar el uso de trailing stop basado en el indicador Parabolic SAR. Valor predeterminado: `false`.
- **SignalMA_Period**: Periodo de la media móvil para SignalMA. Valor predeterminado: `12`.
- **SignalMA_Shift**: Desplazamiento de la media móvil para SignalMA. Valor predeterminado: `6`.
- **SignalMA_Method**: Método de la media móvil para SignalMA. Valor predeterminado: `MODE_SMA`.
- **SignalMA_Applied**: Precio aplicado para SignalMA. Valor predeterminado: `PRICE_CLOSE`.
- **MoneySize_DecreaseFactor**: Factor de disminución para MoneySizeOptimized. Valor predeterminado: `3.0`.
- **MoneySize_Percent**: Porcentaje para MoneySizeOptimized. Valor predeterminado: `10.0`.

### Monitoreo de Operaciones

Una vez configurado, el bot comenzará a operar automáticamente según las condiciones del mercado y los parámetros establecidos. Las operaciones se registrarán en la base de datos SQLite para su posterior análisis.

Recuerda que siempre debes probar el bot en una cuenta demo antes de usarlo en una cuenta real para asegurarte de que se comporta como esperas.

## Estructura del Proyecto

- `AutoOrderBot.mq5`: Archivo principal que gestiona la lógica del bot.
- `Includes/DatabaseHandler.mqh`: Maneja la conexión y operaciones con la base de datos SQLite.
- `Includes/MarketAnalysis.mqh`: Realiza el análisis de mercado utilizando indicadores técnicos.
- `Includes/RiskManager.mqh`: Gestiona el riesgo y calcula el tamaño del lote.
- `Includes/TradeManager.mqh`: Maneja la apertura y cierre de operaciones.
- `Includes/TrailingStop.mqh`: Implementa la lógica para el trailing stop usando Parabolic SAR.

## Contribuciones

Las contribuciones son bienvenidas. Por favor, sigue los siguientes pasos:

1. Haz un fork del proyecto.
2. Crea una nueva rama (`git checkout -b feature/nueva-funcionalidad`).
3. Realiza tus cambios y haz commit (`git commit -am 'Añadir nueva funcionalidad'`).
4. Sube tus cambios a la rama (`git push origin feature/nueva-funcionalidad`).
5. Abre un Pull Request.

## Licencia

Este proyecto está licenciado bajo la Licencia MIT. Para más detalles, consulta el archivo `LICENSE`.

## Contacto


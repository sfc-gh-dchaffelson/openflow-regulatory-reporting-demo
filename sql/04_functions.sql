-- BOE Gaming Demo - JavaScript UDF
-- ============================================================================
-- IMPORTANT: This file MUST be deployed via stage upload due to $$ delimiters.
--
-- Deployment method:
--   ./run_sql.sh <connection> 04_functions.sql --stage-upload
--
-- Or manually:
--   snow stage copy 04_functions.sql @DEDEMO.GAMING.%BATCH_STAGING/sql -c <conn> --overwrite
--   snow sql -c <conn> -q "EXECUTE IMMEDIATE FROM @DEDEMO.GAMING.%BATCH_STAGING/sql/04_functions.sql"
--
-- Run after: 03_tables.sql (needs BATCH_STAGING table for stage)
-- ============================================================================

USE ROLE IDENTIFIER($RUNTIME_ROLE);
USE SCHEMA DEDEMO.GAMING;

CREATE OR REPLACE FUNCTION DEDEMO.GAMING.GENERATE_POKER_XML_JS(
    JSON_ARRAY VARIANT,
    P_OPERATOR_ID VARCHAR,
    P_WAREHOUSE_ID VARCHAR,
    P_BATCH_ID VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS $$
  var deviceMap = {
    "MOBILE": "MO",
    "DESKTOP": "PC",
    "PC": "PC",
    "TABLET": "TB",
    "TV": "TF",
    "OTHER": "OT"
  };

  function mapDeviceType(deviceType) {
    if (!deviceType) return "PC";
    var upper = deviceType.toUpperCase();
    return deviceMap[upper] || "OT";
  }

  var now = new Date();
  var dateStr = now.toISOString().replace(/[-:T]/g, "").substring(0, 14);

  var xml = '<?xml version="1.0" encoding="UTF-8"?>';
  xml += '<Lote xmlns="http://cnjuego.gob.es/sci/v3.3.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">';
  xml += "<Cabecera>";
  xml += "<OperadorId>" + P_OPERATOR_ID + "</OperadorId>";
  xml += "<AlmacenId>" + P_WAREHOUSE_ID + "</AlmacenId>";
  xml += "<LoteId>" + P_BATCH_ID + "</LoteId>";
  xml += "<Version>3.3</Version>";
  xml += "</Cabecera>";
  xml += '<Registro xsi:type="RegistroPoquerTorneo">';
  xml += "<Cabecera>";
  xml += "<RegistroId>REG_" + P_BATCH_ID + "</RegistroId>";
  xml += "<SubregistroId>1</SubregistroId>";
  xml += "<SubregistroTotal>1</SubregistroTotal>";
  xml += "<Fecha>" + dateStr + "</Fecha>";
  xml += "</Cabecera>";
  xml += "<Juego>";
  xml += "<JuegoId>TOUR_" + P_BATCH_ID.substring(0, 8) + "</JuegoId>";
  xml += "<JuegoDesc>Texas Holdem Demo Tournament</JuegoDesc>";
  xml += "<TipoJuego>POT</TipoJuego>";
  xml += "<FechaInicio>" + dateStr + "+0100</FechaInicio>";
  xml += "<FechaFin>" + dateStr + "+0100</FechaFin>";
  xml += "<JuegoEnRed>S</JuegoEnRed>";
  xml += "<LiquidezInternacional>N</LiquidezInternacional>";
  xml += "<Variante>TH</Variante>";
  xml += "<VarianteComercial>Texas Holdem No Limit</VarianteComercial>";
  xml += "<NumeroParticipantes>" + (JSON_ARRAY ? JSON_ARRAY.length : 0) + "</NumeroParticipantes>";
  xml += "</Juego>";

  if (JSON_ARRAY) {
    if (JSON_ARRAY.length > 0) {
      for (var i = 0; i < JSON_ARRAY.length; i++) {
        var txn = JSON_ARRAY[i];
        xml += "<Jugador>";
        xml += "<ID><OperadorId>" + P_OPERATOR_ID + "</OperadorId>";
        xml += "<JugadorId>" + (txn.PLAYER_ID || "UNKNOWN") + "</JugadorId></ID>";
        xml += "<Participacion><Linea>";
        xml += "<Cantidad>" + (txn.BET_AMOUNT || 0).toFixed(2) + "</Cantidad>";
        xml += "<Unidad>EUR</Unidad>";
        xml += "</Linea></Participacion>";
        xml += "<ParticipacionDevolucion><Linea>";
        xml += "<Cantidad>" + (txn.REFUND_AMOUNT || 0).toFixed(2) + "</Cantidad>";
        xml += "<Unidad>EUR</Unidad>";
        xml += "</Linea></ParticipacionDevolucion>";
        xml += "<Premios><Linea>";
        xml += "<Cantidad>" + (txn.WIN_AMOUNT || 0).toFixed(2) + "</Cantidad>";
        xml += "<Unidad>EUR</Unidad>";
        xml += "</Linea></Premios>";
        xml += "<IP>" + (txn.PLAYER_IP || "0.0.0.0") + "</IP>";
        xml += "<Dispositivo>" + mapDeviceType(txn.DEVICE_TYPE) + "</Dispositivo>";
        xml += "<IdDispositivo>" + (txn.DEVICE_ID || "UNKNOWN") + "</IdDispositivo>";
        xml += "</Jugador>";
      }
    }
  }

  xml += "</Registro>";
  xml += "</Lote>";

  return xml;
$$;

-- Verify
SELECT 'Function created' AS status;
SHOW USER FUNCTIONS LIKE 'GENERATE_POKER_XML_JS' IN SCHEMA DEDEMO.GAMING;

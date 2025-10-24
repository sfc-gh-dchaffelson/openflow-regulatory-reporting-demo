# Data Model Specifications

**Document Title:** Modelo de datos del sistema de monitorización de la
información
**Source Section:** Section 3 - Functional Data Model
**Extraction Date:** 2024
**Version:** Based on RD 176/2023

---

## 1. Information Types and Reporting Periodicity

### 1.1 User Registration (Registro de usuario)

**Subtypes:**
- **RUD** - Detallado (Detailed)
- **RUR** - Red (Network)
- **RUG** - Ganadores sin registro (Winners without registration)
- **RUT** - Totalizado (Totalized)

**Periodicity:**
- Daily: RUD
- Monthly: RUD, RUT, RUR, RUG

### 1.2 Gaming Account (Cuenta de juego)

**Subtypes:**
- **CJD** - Detallada (Detailed)
- **CJT** - Totalizada (Totalized)

**Periodicity:**
- Daily: CJD, CJT
- Monthly: CJD, CJT

### 1.3 Operator Account (Cuenta de operador)

**Subtypes:**
- **OPT** - Completa (Complete)
- **ORT** - Coorganizador (Co-organizer)
- **BOT** - Botes y partidas vivas (Jackpots and live games)

**Periodicity:**
- Monthly: OPT, ORT, BOT

### 1.4 Gaming Records (Registro de juego)

**Subtypes:**
- **JUC** - Juegos (Games)

**Periodicity:**
- Real-time

### 1.5 Betting Adjustments (Ajustes de apuestas)

**Subtypes:**
- **JUA** - Ajustes

**Periodicity:**
- Monthly

### 1.6 Event Catalog (Catálogo de eventos)

**Subtypes:**
- **CEV** - Eventos

**Periodicity:**
- Daily: New or modified events
- Monthly: All events

---

## 2. Reporting Obligations by Operator Type

### 2.1 Registration Manager (Gestor registro usuario)
Required reports: RUD, RUT, CJD, CJT, OPT, BOT, JUC, JUA, CEV

### 2.2 Network Affiliate (Adscrito red)
Required reports: RUD, RUT, CJD, CJT, OPT

### 2.3 Network Co-organizer (Coorganizador red)
Required reports: RUR, RUT, ORT, BOT, JUC

### 2.4 Shared Jackpot Manager (Gestor botes compartidos)
Required reports: BOT

### 2.5 Games Without Prior Registration (Juegos sin registro previo)
Required reports: RUG, OPT, BOT, JUC

---

## 3. Register Type Specifications

## 3.1 RUD - Detailed User Registration

### 3.1.1 Identification Fields

**Field Name** | **Description** | **Type**
---|---|---
JugadorId | Player identifier | cadena50
FechaActivacion | Activation date | date-aaaammdd
CambiosEnDatos | Data changes indicator | enum
RegionFiscal | Fiscal region | cadena50

**CambiosEnDatos Values:**
- A: Alta (New registration)
- N: No Variado (No changes)
- S: Si Variado (Changed)
- B: Baja (Deregistration)

### 3.1.2 Resident Player Fields

**Field Name** | **Description** | **Type**
---|---|---
NIF | National identification number | cadena10
NIE | Foreign identification number | cadena10
Nombre | First name | cadena50
Apellido1 | First surname | cadena50
Apellido2 | Second surname | cadena50
FechaNacimiento | Date of birth | date-aaaammdd
Sexo | Gender (M/F) | cadena1
Pais | Country | cadena50
Provincia | Province | cadena50
Municipio | Municipality | cadena50
CodigoPostal | Postal code | cadena10
Direccion | Address | cadena200
Email | Email address | cadena100
Telefono | Phone number | cadena20

### 3.1.3 Non-Resident Player Fields

**Field Name** | **Description** | **Type**
---|---|---
TipoDocumento | Document type | enum
NumeroDocumento | Document number | cadena50
Nombre | First name | cadena50
Apellido1 | First surname | cadena50
Apellido2 | Second surname | cadena50
FechaNacimiento | Date of birth | date-aaaammdd
Sexo | Gender (M/F) | cadena1
Pais | Country | cadena50
Email | Email address | cadena100
Telefono | Phone number | cadena20

**TipoDocumento Values:**
- ID: Identity document
- SS: Social security number
- PA: Passport
- DL: Driver's license
- OT: Other

### 3.1.4 Limit Configuration

**Field Name** | **Description** | **Type**
---|---|---
TipoLimite | Limit type | enum
PeriodoLimite | Limit period | enum
TipoJuego | Game type | cadena10
Cantidad | Amount | cantidad
UnidadLimite | Limit unit | enum
FechaActivacionLimite | Limit activation date | date-aaaammdd
FechaSolicitudCambioLimite | Limit change request date | date-aaaammdd

**TipoLimite Values:**
- Deposito (Deposit)
- Participacion (Participation)
- Gasto (Spending)
- Tiempo (Time)

**PeriodoLimite Values:**
- Diario (Daily)
- Semanal (Weekly)
- Mensual (Monthly)

**UnidadLimite Values:**
- DIA (Day)
- SEMANA (Week)
- MES (Month)
- MINUTO (Minute)
- HORA (Hour)
- EUR (Euro)

**Mandatory Requirements:**
- Deposit limits must be configured for all periods: Diario, Semanal,
Mensual

### 3.1.5 Exclusion Information

**Field Name** | **Description** | **Type**
---|---|---
Cantidad | Exclusion duration amount | cantidad
Unidad | Exclusion duration unit | cadena20
FechaActivacion | Activation date | date-aaaammdd
FechaSolicitudCambioExclusion | Exclusion change request date |
date-aaaammdd
Autocontinuacion | Auto-continuation flag (S/N) | cadena1

### 3.1.6 Special Player Profiles

**Profile Types:**
- ClientePrivilegiado (Privileged client)
- JugadorIntensivo (Intensive player)
- ParticipanteJoven (Young participant)
- ComportamientoRiesgo (Risk behavior)
- Otros (Others)

**Field Name** | **Description** | **Type**
---|---|---
PerfilJugador | Player profile type | cadena50
FechaInicio | Start date | date-aaaammdd
FechaFin | End date | date-aaaammdd

### 3.1.7 Account Status

**Field Name** | **Description** | **Type**
---|---|---
EstadoCNJ | CNJ status code | enum
EstadoOperador | Operator-defined status | cadena50
MotivoEstado | Status reason | enum

**EstadoCNJ Values:**
- A: Activo (Active)
- PV: Pendiente verificación (Pending verification)
- S: Suspendido (Suspended)
- C: Cancelado (Cancelled)
- CD: Cancelado defunción (Cancelled - deceased)
- PR: Prohibición subjetiva (Subjective prohibition)
- AE: Autoexcluido (Self-excluded)
- O: Otros (Others)

**MotivoEstado Values:**
- PeticionJugador (Player request)
- Inactividad (Inactivity)
- JuegoSeguro (Safe gaming)
- FraudeldPagos (Payment fraud)
- TyC (Terms and conditions)
- Otros (Others)

### 3.1.8 Status History

**Field Name** | **Description** | **Type**
---|---|---
EstadoCNJ | CNJ status | enum
EstadoOperador | Operator status | cadena50
Desde | Effective from date | date-aaaammdd
MotivoEstado | Status reason | enum

### 3.1.9 Verification Information

**Field Name** | **Description** | **Type**
---|---|---
VSVDI | SVDI verification (S/N) | cadena1
FVSVDI | SVDI verification date | date-aaaammdd
VDocumental | Documentary verification (S/N) | cadena1
TipoVerificacionDocumental | Documentary verification type | enum
FechaVerificacionDocumental | Documentary verification date | date-aaaammdd

**TipoVerificacionDocumental Values:**
- DOC: Document
- SLF: Selfie
- SLFV: Video selfie
- DOM: Address
- VID: Video
- VIDV: Video verification
- VIDC: Video call
- CER: Certificate
- TLF: Telephone
- OTR: Other

---

## 3.2 RUT - Totalized User Registration

**Field Name** | **Description** | **Type**
---|---|---
NumeroJugadores | Total number of players | entero8
NumeroAltas | Number of new registrations | entero8
NumeroBajas | Number of deregistrations | entero8
NumeroActividad | Number of active players | entero8
NumeroTest | Number of test accounts | entero8
NumeroJugadoresPorEstado | Players by status | entero8
NumeroJugadoresPorPerfil | Players by profile | entero8

---

## 3.3 RUR - Network User Registration

**Field Name** | **Description** | **Type**
---|---|---
JugadorId | Player identifier | cadena50
OperadorId | Operator identifier | cadena20
Login | Login username | cadena50
EstadoCNJ | CNJ status | enum
EstadoOperador | Operator status | cadena50

---

## 3.4 RUG - Winners Without Registration

**Field Name** | **Description** | **Type**
---|---|---
TipoJuego | Game type | cadena10
Premio | Prize amount | cantidad
Retencion | Withholding tax | cantidad

---

## 3.5 CJD - Detailed Gaming Account

### 3.5.1 Basic Account Information

**Field Name** | **Description** | **Type**
---|---|---
JugadorId | Player identifier | cadena50
SaldoInicial | Initial balance | cantidad
SaldoFinal | Final balance | cantidad

### 3.5.2 Deposits (Depositos)

**Field Name** | **Description** | **Type**
---|---|---
Fecha | Transaction date | date-aaaammddhhmmss
Importe | Amount | cantidad
MedioPago | Payment method | cadena50
TipoMedioPago | Payment method type code | entero3
TitularidadVerificada | Ownership verified (S/N) | cadena1
Entidad | Entity name | cadena100
IdEntidad | Entity identifier | cadena50
UltimosDigitosMedioPago | Last digits of payment method | cadena10
ResultadoOperacion | Operation result | enum
IP | IP address | cadena50
Dispositivo | Device type | enum
IdDispositivo | Device identifier | cadena100
InformacionAuxiliar | Auxiliary information | cadena1000

**ResultadoOperacion Values:**
- OK: Correcta (Successful)
- CU: Cancelada Usuario (Cancelled by user)
- CO: Cancelada Operador (Cancelled by operator)
- CM: Cancelada Pasarela (Cancelled by gateway)
- OT: Otra (Other)

**Dispositivo Values:**
- MO: Mobile
- PC: Personal computer
- TB: Tablet
- TF: Fixed terminal
- OT: Other

### 3.5.3 Withdrawals (Retiradas)

Uses the same field structure as Deposits.

### 3.5.4 Participation (Participacion)

Reported by unit and game type with the following structure:
- Amount per game type
- Breakdown by operational unit

### 3.5.5 Participation Returns (ParticipacionDevolucion)

Reported by unit and game type with the same structure as Participation.

### 3.5.6 Prizes (Premios)

Reported by unit and game type with the same structure as Participation.

### 3.5.7 Prize Adjustments (AjustePremios)

Reported by unit and game type with the same structure as Participation.

### 3.5.8 Transfers In (Trans_IN)

Reported by unit and operator identifier.

### 3.5.9 Transfers Out (Trans_OUT)

Reported by unit and operator identifier.

### 3.5.10 Other Movements (Otros)

Reported by concept with amount specification.

### 3.5.11 Commissions (Comision)

Reported by game type.

### 3.5.12 Bonuses (Bonos)

**Field Name** | **Description** | **Type**
---|---|---
Fecha | Transaction date | date-aaaammddhhmmss
FechaActivacion | Activation date | date-aaaammdd
Importe | Amount | cantidad
Concepto | Bonus concept | enum

**Concepto Values:**
- CONCESION: Grant
- CANCELACION: Cancellation
- LIBERACION: Release

### 3.5.13 Prizes in Kind (PremiosEspecie)

**Field Name** | **Description** | **Type**
---|---|---
TipoJuego | Game type | cadena10
Descripcion | Description | cadena200
Total | Total value | cantidad
Fecha | Date | date-aaaammdd

### 3.5.14 Gifts (Regalos)

**Field Name** | **Description** | **Type**
---|---|---
Descripcion | Description | cadena200
Total | Total value | cantidad
Fecha | Date | date-aaaammdd

### 3.5.15 Sign Convention

**Positive (+) movements:**
- Deposits
- Bonus grants (CONCESION)
- Prizes
- Transfers in

**Negative (-) movements:**
- Withdrawals
- Participation
- Transfers out
- Bonus cancellations (CANCELACION)

---

## 3.6 CJT - Totalized Gaming Account

Contains aggregated data from CJD without player identifier. All monetary
fields are summed across all players for the reporting period.

---

## 3.7 OPT - Complete Operator Account

### 3.7.1 Fields by Game Type

**Field Name** | **Description** | **Type**
---|---|---
TipoJuego | Game type | cadena10
Participacion | Total participation | cantidad
ParticipacionDevolucion | Participation returns | cantidad
Premios | Prizes paid | cantidad
PremiosEspecie | Prizes in kind | cantidad
Botes | Jackpot movements | estructura
AjustesRed | Network adjustments | cantidad
Otros | Other concepts | estructura
Comision | Commission | cantidad
GGR | Gross Gaming Revenue | cantidad
FechaInicioOferta | Offer start date | date-aaaammdd

### 3.7.2 Jackpot Movements (Botes)

**Field Name** | **Description** | **Type**
---|---|---
Incremento | Jackpot increase | cantidad
Decremento | Jackpot decrease | cantidad

### 3.7.3 Other Concepts (Otros)

**Concept Code** | **Description**
---|---
APA | Participation adjustments
APR | Prize adjustments
BON | Bonuses
OVL | Overlay
ADD | Added money
OTR | Others

### 3.7.4 Breakdown Structure

All amounts must be broken down by:
- Operator identifier
- Operational unit

---

## 3.8 ORT - Co-organizer Operator Account

Uses the same structure as OPT with mandatory breakdown by operator.

---

## 3.9 BOT - Jackpots and Live Games

### 3.9.1 Live Games (Partidas Vivas)

**Field Name** | **Description** | **Type**
---|---|---
SaldoInicial | Initial balance | cantidad
IncrementoPartidasVivas | Live games increase | cantidad
DecrementoPartidasVivas | Live games decrease | cantidad
SaldoFinal | Final balance | cantidad
DesgloseCompromiso | Commitment breakdown | estructura

### 3.9.2 Jackpots Summary

**Field Name** | **Description** | **Type**
---|---|---
SaldoInicial | Initial balance | cantidad
IncrementoBotes | Jackpot increase | cantidad
DecrementoBotes | Jackpot decrease | cantidad
SaldoFinal | Final balance | cantidad

### 3.9.3 Jackpots Detail

**Field Name** | **Description** | **Type**
---|---|---
BoteId | Jackpot identifier | cadena50
BoteDesc | Jackpot description | cadena200
FechaInicio | Start date | date-aaaammdd
FechaFin | End date | date-aaaammdd
SaldoInicial | Initial balance | cantidad
IncrementoBotes | Jackpot increase | cantidad
DecrementoBotes | Jackpot decrease | cantidad
SaldoFinal | Final balance | cantidad

---

## 4. Real-Time Gaming Records (JUC)

## 4.1 Other Games Session Record (RegistroOtrosJuegos)

### 4.1.1 Applicable Games

**Game Code** | **Game Type**
---|---
POC | Poker cash
BNG | Bingo
AZA | Chance games
BLJ | Blackjack
RLT | Roulette
PUN | Punto y banca
COM | Combined games

### 4.1.2 Game Fields

**Field Name** | **Description** | **Type**
---|---|---
JuegoId | Game identifier | cadena50
JuegoDesc | Game description | cadena200
TipoJuego | Game type code | cadena10
FechaInicio | Start date/time | date-aaaammddhhmmss
FechaFin | End date/time | date-aaaammddhhmmss
Participacion | Total participation | cantidad
ParticipacionDevolucion | Participation returns | cantidad
Premios | Prizes | cantidad
Botes | Jackpots | cantidad
Variante | Game variant | enum
VarianteComercial | Commercial variant | cadena50
JuegoEnVivo | Live game flag (RLT) | cadena1
JuegoEnRed | Network game flag (POC) | cadena1
LiquidezInternacional | International liquidity (POC) | cadena1
MesaId | Table identifier (POC) | cadena50
PartidasJugadas | Games played | entero8

**Variante Values:**
- POC: Poker variants (DR, ST, OM, TH)
- BLJ: Blackjack variants
- RLT: Roulette variants

### 4.1.3 Player Fields

**Field Name** | **Description** | **Type**
---|---|---
JugadorId | Player identifier | cadena50
IP | IP address | cadena50
Dispositivo | Device type | enum
IdDispositivo | Device identifier | cadena100

### 4.1.4 Session Information

**Field Name** | **Description** | **Type**
---|---|---
SesionId | Session identifier | cadena50
FechaInicioSesion | Session start | date-aaaammddhhmmss
FechaFinSesion | Session end | date-aaaammddhhmmss
FechaInicioPrimerJuego | First game start | date-aaaammddhhmmss
FechaFinUltimoJuego | Last game end | date-aaaammddhhmmss
PlanificacionSesion | Session planning | enum
SesionCompleta | Complete session flag (S/N) | cadena1
SesionNueva | New session flag (S/N) | cadena1
MotivoFinSesion | Session end reason | enum

**PlanificacionSesion Values:**
- DuracionLimite: Duration limit
- GastoLimite: Spending limit
- PeriodoExclusion: Exclusion period
- TiempoExclusion: Exclusion time

**MotivoFinSesion Values:**
- Usuario: User initiated
- Limite: Limit reached
- Conexion: Connection issue

**Trigger:** End of session

---

## 4.2 Poker Tournament Record (RegistroPoquerTorneo)

### 4.2.1 Game Information

**Game Code:** POT

**Field Name** | **Description** | **Type**
---|---|---
JuegoEnRed | Network game (S/N) | cadena1
LiquidezInternacional | International liquidity (S/N) | cadena1
Variante | Poker variant | enum
VarianteComercial | Commercial variant | cadena50
NumeroParticipantes | Number of participants | entero8
ContribucionOperadorOVL | Operator overlay contribution | cantidad
ContribucionOperadorADD | Operator added contribution | cantidad

**Variante Values:**
- DR: Draw
- ST: Stud
- OM: Omaha
- TH: Texas Hold'em

### 4.2.2 Player Information

**Field Name** | **Description** | **Type**
---|---|---
JugadorId | Player identifier | cadena50
Participacion | Participation amount | cantidad
ParticipacionDevolucion | Participation return | cantidad
Premios | Prize amount | cantidad
IP | IP address | cadena50
Dispositivo | Device type | enum
IdDispositivo | Device identifier | cadena100

**Trigger:** End of tournament

---

## 4.3 Fixed-Odds Betting Record (RegistroApuestaContrapartida)

### 4.3.1 Applicable Games

**Game Code** | **Game Type**
---|---
ADC | Sports betting - fixed odds
AHC | Horse racing - fixed odds
AOC | Other betting - fixed odds

### 4.3.2 Game Fields

**Field Name** | **Description** | **Type**
---|---|---
EnDirecto | Live betting (S/N) | cadena1
TipoApuesta | Bet type | enum
NumeroEventos | Number of events | entero3
Eventos | Event details | estructura

**TipoApuesta Values:**
- Simple: Single bet
- Multiple: Multiple bet
- Combinada: Combined bet
- Xy: System bet
- Trixie: Trixie system
- Patent: Patent system
- Yankee: Yankee system
- Lucky15: Lucky 15 system
- Lucky31: Lucky 31 system
- Lucky63: Lucky 63 system
- Heinz: Heinz system
- SuperHeinz: Super Heinz system
- Goliat: Goliath system
- Otro: Other

### 4.3.3 Event Structure

**Field Name** | **Description** | **Type**
---|---|---
EventoId | Event identifier | cadena50
Hecho | Event outcome | cadena200
FechaHecho | Event date | date-aaaammddhhmmss

### 4.3.4 Player Fields

**Field Name** | **Description** | **Type**
---|---|---
JugadorId | Player identifier | cadena50
SaldoCuenta | Account balance | cantidad
Participacion | Stake amount | cantidad
ParticipacionDevolucion | Stake return | cantidad
Premios | Prize amount | cantidad
TicketApuesta | Bet ticket identifier | cadena50
Cuota | Odds | cantidad
CashOut | Cash out details | estructura
IP | IP address | cadena50
Dispositivo | Device type | enum
IdDispositivo | Device identifier | cadena100

### 4.3.5 Cash Out Structure

**Field Name** | **Description** | **Type**
---|---|---
ImporteCashOut | Cash out amount | cantidad
FechaCashOut | Cash out date | date-aaaammddhhmmss

**Note:** Multiple cash out entries may exist per bet.

**Trigger:** Bet closed (settled or cancelled)

---

## 4.4 Mutual Betting Record (RegistroApuestaMutua)

### 4.4.1 Applicable Games

**Game Code** | **Game Type**
---|---
ADM | Sports betting - mutual
AHM | Horse racing - mutual
ADX | Sports betting - exchange
AOX | Other betting - exchange

### 4.4.2 Game Fields

**Field Name** | **Description** | **Type**
---|---|---
TipoApuesta | Bet type | enum
NumeroEventos | Number of events | entero3
Eventos | Event details | estructura
Cruces | Exchange crosses | estructura

### 4.4.3 Exchange Crosses Structure

**Field Name** | **Description** | **Type**
---|---|---
Reto | Challenge details | cadena200
Ticket | Ticket identifier | cadena50
LayBack | Lay/Back indicator | cadena10

### 4.4.4 Player Fields

**Field Name** | **Description** | **Type**
---|---|---
JugadorId | Player identifier | cadena50
Participacion | Stake amount | cantidad
ParticipacionDevolucion | Stake return | cantidad
Premios | Prize amount | cantidad
Botes | Jackpot amount | cantidad
TicketApuesta | Bet ticket identifier | cadena50
FechaApuesta | Bet date | date-aaaammddhhmmss
Cuota | Odds | cantidad
CashOut | Cash out details | estructura
IP | IP address | cadena50
Dispositivo | Device type | enum
IdDispositivo | Device identifier | cadena100

**Trigger:** Bet closed (settled or cancelled)

---

## 4.5 Contest Record (RegistroConcurso)

### 4.5.1 Game Information

**Game Code:** COC

### 4.5.2 Game Fields

**Field Name** | **Description** | **Type**
---|---|---
NumeroParticipaciones | Number of participations | entero8
NumeroPremiados | Number of winners | entero8
NumeroLlamadas | Number of calls | entero8
PrecioMinutoLlamada | Price per minute | cantidad
ImporteMaximoLlamada | Maximum call amount | cantidad
ParticipacionLlamadas | Call participation amount | cantidad
STALlamadas | Call STA amount | cantidad
NumeroSMS | Number of SMS | entero8
PrecioSMS | SMS price | cantidad
ParticipacionSMS | SMS participation amount | cantidad
STASSMS | SMS STA amount | cantidad

### 4.5.3 Player Fields

**Field Name** | **Description** | **Type**
---|---|---
JugadorId | Player identifier | cadena50
Participacion | Participation amount | cantidad
ParticipacionDevolucion | Participation return | cantidad
Premios | Prize amount | cantidad

**Trigger:** End of contest

---

## 4.6 Lottery Record (RegistroLoteria)

### 4.6.1 Applicable Games - Online Lotteries

**Game Code** | **Game Type**
---|---
PDM | State lottery - online
PHM | Horse racing lottery - online
PLN | National lottery - online
PLP | Primitiva lottery - online
PEU | Euromillions - online
PBL | Bonoloto - online
PGP | El Gordo - online
PLT | Loteria Nacional - online
PED | Eurodreams - online
PCP | Cupón ONCE - online
PSO | Sorteo Oro - online
PTX | Triplex - online
PMD | Mi Día - online
PEJ | El Joker - online
PRK | Rasca - online

### 4.6.2 Applicable Games - Presential Lotteries

**Game Code** | **Game Type**
---|---
OLN | National lottery - presential
OLP | Primitiva lottery - presential
OEU | Euromillions - presential
OBL | Bonoloto - presential
OGP | El Gordo - presential
OLT | Loteria Nacional - presential
OED | Eurodreams - presential
OCP | Cupón ONCE - presential
OSO | Sorteo Oro - presential
OTX | Triplex - presential
OMD | Mi Día - presential
OEJ | El Joker - presential
ORK | Rasca - presential

### 4.6.3 Game Fields

**Field Name** | **Description** | **Type**
---|---|---
NumeroBoletos | Number of tickets | entero8

### 4.6.4 Player Fields

**Field Name** | **Description** | **Type**
---|---|---
JugadorId | Player identifier | cadena50
Participacion | Participation amount | cantidad
ParticipacionDevolucion | Participation return | cantidad
Premios | Prize amount | cantidad
Botes | Jackpot amount | cantidad

**Trigger:** Draw completed

**Special Note:** Presential games report aggregated totals without
individual player detail.

---

## 4.7 Pre-drawn Lottery Record (RegistroLoteriaPresorteada)

### 4.7.1 Game Fields

**Field Name** | **Description** | **Type**
---|---|---
NumeroBoletos | Number of tickets | entero8

### 4.7.2 Player Fields

**Field Name** | **Description** | **Type**
---|---|---
JugadorId | Player identifier | cadena50
Sesion | Session information | estructura
Participacion | Participation amount | cantidad
ParticipacionDevolucion | Participation return | cantidad
Premios | Prize amount | cantidad
Botes | Jackpot amount | cantidad
IP | IP address | cadena50
Dispositivo | Device type | enum
IdDispositivo | Device identifier | cadena100

**Trigger:** End of session

---

## 5. Betting Adjustments (JUA)

**Field Name** | **Description** | **Type**
---|---|---
EventoId | Event identifier | cadena50
TicketApuesta | Bet ticket identifier | cadena50
JugadorId | Player identifier | cadena50
FechaAjuste | Adjustment date | date-aaaammdd
MotivoAjuste | Adjustment reason | cadena200
ImporteAjuste | Adjustment amount | cantidad

**Periodicity:** Monthly

---

## 6. Event Catalog (CEV)

### 6.1 Mandatory Fields

**Field Name** | **Description** | **Type**
---|---|---
EventoId | Event identifier | cadena50
DescripcionEvento | Event description | cadena200
EventoEspecial | Special event flag (S/N) | cadena1
FechaInicio | Start date | date-aaaammddhhmmss
FechaFin | End date | date-aaaammddhhmmss
Codigo | Event category code | entero3
OtroCodigoEspecificar | Other code specification | cadena100
Competicion | Competition name | cadena200
CompeticionInternacional | International competition (S/N) | cadena1
PaisCompeticion | Competition country | cadena50
SexoCompeticion | Competition gender (M/F/O) | cadena1
CategoriaCompeticion | Competition category | cadena50
FaseCompeticion | Competition phase | cadena50
Actualizado | Updated flag (S/N) | cadena1
FechaAltaEvento | Event registration date | date-aaaammdd

### 6.2 Event Category Codes

**Code Range** | **Description**
---|---
1-84 | Standard sport and event categories
901-902 | Special categories
998-999 | Other categories

### 6.3 Periodicity

- **Daily:** New or modified events only
- **Monthly:** All events in catalog

---

## 7. Game Type Codes

**Code** | **Game Type**
---|---
ADC | Sports betting - fixed odds
ADM | Sports betting - mutual
ADX | Sports betting - exchange
AHC | Horse racing - fixed odds
AHM | Horse racing - mutual
AOC | Other betting - fixed odds
AOX | Other betting - exchange
AZA | Chance games
BL
+------------------------------------------------------------------------------+


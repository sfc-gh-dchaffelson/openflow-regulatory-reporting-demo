"""
BOE Gaming Pipeline Monitor - Multi-Tab Narrative View

A progressive walkthrough of the regulatory compliance pipeline:
Postgres (external) → CDC → Dynamic Table → Stream → Batches → SFTP

Deploy to Snowflake via: snow streamlit deploy
"""

import streamlit as st
import json
import _snowflake
from snowflake.snowpark.context import get_active_session

# Page config
st.set_page_config(
    page_title="BOE Gaming Pipeline",
    page_icon=None,
    layout="wide",
    initial_sidebar_state="collapsed"
)

# Minimal styling - Snowflake blue accent, larger tabs
st.markdown("""
<style>
    /* Primary button color */
    .stButton > button[kind="primary"] {
        background-color: #29B5E8;
        border-color: #29B5E8;
    }
    /* Tab labels */
    button[data-baseweb="tab"] {
        font-size: 1.1rem !important;
    }
    .stTabs button {
        font-size: 1.1rem !important;
    }
    /* Active tab styling */
    button[data-baseweb="tab"][aria-selected="true"] {
        color: #29B5E8 !important;
    }
    /* Table header contrast */
    .stDataFrame th {
        color: #1A1A2E !important;
        font-weight: 600 !important;
    }
</style>
""", unsafe_allow_html=True)

# Get Snowflake session
session = get_active_session()

# Cortex Agent Configuration
CORTEX_API_ENDPOINT = "/api/v2/cortex/agent:run"
CORTEX_API_TIMEOUT = 50000  # milliseconds
SEMANTIC_MODEL = "@DEDEMO.GAMING.CORTEX_MODELS/semantic_models/gaming_pipeline_analytics_semantic_model.yaml"


def cortex_agent_call(query: str, conversation_history: list = None):
    """Call Cortex Agent API with semantic model"""

    # Build messages array - start fresh with just the query
    messages = [
        {
            "role": "user",
            "content": [{"type": "text", "text": query}]
        }
    ]

    payload = {
        "model": "claude-opus-4-5",
        "messages": messages,
        "tools": [
            {
                "tool_spec": {
                    "type": "cortex_analyst_text_to_sql",
                    "name": "analyst"
                }
            }
        ],
        "tool_resources": {
            "analyst": {
                "semantic_model_file": SEMANTIC_MODEL
            }
        }
    }

    try:
        resp = _snowflake.send_snow_api_request(
            "POST",
            CORTEX_API_ENDPOINT,
            {},
            {},
            payload,
            None,
            CORTEX_API_TIMEOUT,
        )

        if resp["status"] != 200:
            return {"error": f"HTTP {resp['status']}: {resp.get('reason', 'Unknown error')}", "raw": str(resp)}

        return json.loads(resp["content"])

    except Exception as e:
        return {"error": str(e)}


def process_agent_response(response):
    """Extract text and SQL from Cortex Agent response"""
    text = ""
    sql = ""
    debug_info = []

    if not response:
        return "No response received", "", "Empty response"

    if isinstance(response, str):
        return response, "", "String response"

    if "error" in response:
        raw_info = response.get("raw", "")
        return response["error"], "", f"Error response: {raw_info}"

    try:
        if isinstance(response, list):
            debug_info.append(f"List response with {len(response)} events")
            for event in response:
                if isinstance(event, dict):
                    event_type = event.get('event', 'no-event-field')
                    debug_info.append(f"Event: {event_type}")

                    # Handle errors
                    if event_type == "error":
                        error_msg = event.get('data', {}).get('message', 'Unknown error')
                        return f"Error: {error_msg}", "", "\n".join(debug_info)

                    # Handle message deltas
                    elif event_type == "message.delta":
                        delta = event.get('data', {}).get('delta', {})
                        for content_item in delta.get('content', []):
                            content_type = content_item.get('type')
                            debug_info.append(f"  Content type: {content_type}")

                            if content_type == "tool_results":
                                tool_results = content_item.get('tool_results', {})
                                for result in tool_results.get('content', []):
                                    if result.get('type') == 'json':
                                        json_data = result.get('json', {})
                                        text += json_data.get('text', '')
                                        if json_data.get('sql'):
                                            sql = json_data.get('sql')

                            elif content_type == 'text':
                                text += content_item.get('text', '')

                    # Handle complete messages
                    elif 'role' in event and event['role'] == 'assistant':
                        for content_item in event.get('content', []):
                            if content_item.get('type') == 'text':
                                text += content_item.get('text', '')

        elif isinstance(response, dict):
            debug_info.append(f"Dict response with keys: {list(response.keys())}")
            if 'choices' in response:
                for choice in response['choices']:
                    if 'message' in choice:
                        text += choice['message'].get('content', '')

    except Exception as e:
        return f"Error processing response: {e}", "", "\n".join(debug_info)

    return text, sql, "\n".join(debug_info)

# App title
st.title("BOE Gaming Regulatory Pipeline")

# Global refresh
col_title, col_refresh = st.columns([4, 1])
with col_refresh:
    if st.button("Refresh All", type="primary"):
        st.experimental_rerun()

# Create tabs for narrative progression
tab_overview, tab_cdc, tab_dt, tab_stream, tab_batches, tab_obs, tab_logs, tab_cortex = st.tabs([
    "Overview",
    "CDC Replication",
    "Dynamic Table",
    "Stream",
    "Batches",
    "Observability",
    "Logs",
    "Ask Cortex"
])


# =============================================================================
# TAB 1: OVERVIEW
# =============================================================================
with tab_overview:
    st.header("Pipeline Overview")
    st.caption("End-to-end view of the regulatory data pipeline from source to delivery")

    # Pipeline stage counts
    st.subheader("Pipeline Stage Counts")

    try:
        stage_counts = session.sql("""
            SELECT 'CDC Source' as STAGE, 1 as STAGE_ORDER, COUNT(*) as COUNT FROM DEDEMO.TOURNAMENTS.POKER
            UNION ALL SELECT 'Dynamic Table', 2, COUNT(*) FROM DEDEMO.GAMING.DT_POKER_FLATTENED
            UNION ALL SELECT 'Stream Pending', 3, COUNT(*) FROM DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM
            UNION ALL SELECT 'Batches Created', 4, COUNT(*) FROM DEDEMO.GAMING.REGULATORY_BATCHES
            UNION ALL SELECT 'Batches Uploaded', 5, SUM(CASE WHEN STATUS = 'UPLOADED' THEN 1 ELSE 0 END) FROM DEDEMO.GAMING.REGULATORY_BATCHES
            ORDER BY STAGE_ORDER
        """).collect()

        # Display as horizontal metrics
        cols = st.columns(5)
        stage_icons = ["📥", "🔄", "⏳", "📦", "✅"]
        for i, row in enumerate(stage_counts):
            with cols[i]:
                st.metric(
                    label=f"{stage_icons[i]} {row['STAGE']}",
                    value=f"{row['COUNT']:,}"
                )
    except Exception as e:
        st.error(f"Error loading stage counts: {e}")


    # Key metrics row
    st.subheader("Key Metrics")

    m1, m2, m3, m4 = st.columns(4)

    with m1:
        try:
            result = session.sql("""
                SELECT COUNT(*) as cnt FROM DEDEMO.GAMING.REGULATORY_BATCHES
                WHERE STATUS = 'UPLOADED' AND DATE(UPLOAD_TIMESTAMP) = CURRENT_DATE()
            """).collect()[0]['CNT']
            st.metric("Uploaded Today", f"{result:,}")
        except:
            st.metric("Uploaded Today", "N/A")

    with m2:
        try:
            result = session.sql("""
                SELECT SUM(TRANSACTION_COUNT) as total
                FROM DEDEMO.GAMING.REGULATORY_BATCHES
            """).collect()[0]['TOTAL']
            st.metric("Total Transactions Processed", f"{int(result or 0):,}")
        except:
            st.metric("Total Transactions Processed", "N/A")

    with m3:
        try:
            result = session.sql("""
                SELECT AVG_SEC FROM DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS
                WHERE STAGE = 'TOTAL END-TO-END'
            """).collect()
            if result and result[0]['AVG_SEC']:
                avg_sec = float(result[0]['AVG_SEC'])
                st.metric("Avg End-to-End Latency", f"{avg_sec:.1f} sec")
            else:
                st.metric("Avg End-to-End Latency", "N/A")
        except:
            st.metric("Avg End-to-End Latency", "N/A")

    with m4:
        try:
            result = session.sql("""
                SELECT COUNT(*) as cnt FROM DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY
                WHERE HOUR > DATEADD(hour, -1, CURRENT_TIMESTAMP())
                AND LOG_LEVEL = 'ERROR'
            """).collect()[0]['CNT']
            if result == 0:
                st.metric("Errors (Last Hour)", "0", delta="Healthy", delta_color="normal")
            else:
                st.metric("Errors (Last Hour)", f"{result}", delta="Needs attention", delta_color="inverse")
        except:
            st.metric("Errors (Last Hour)", "N/A")


    # Data freshness (all times displayed in UTC)
    st.subheader("Data Freshness (UTC)")

    f1, f2, f3 = st.columns(3)

    with f1:
        try:
            # Source timestamp is already UTC, no conversion needed
            result = session.sql("""
                SELECT TO_VARCHAR(
                    MAX(CREATED_TIMESTAMP),
                    'YYYY-MM-DD HH24:MI:SS'
                ) as ts FROM DEDEMO.TOURNAMENTS.POKER
            """).collect()[0]['TS']
            st.metric("Latest Source Transaction", result if result else "N/A")
        except:
            st.metric("Latest Source Transaction", "N/A")

    with f2:
        try:
            # Batch timestamp needs timezone conversion to UTC
            result = session.sql("""
                SELECT TO_VARCHAR(
                    CONVERT_TIMEZONE('UTC', MAX(BATCH_TIMESTAMP)),
                    'YYYY-MM-DD HH24:MI:SS'
                ) as ts FROM DEDEMO.GAMING.REGULATORY_BATCHES
            """).collect()[0]['TS']
            st.metric("Latest Batch Created", result if result else "N/A")
        except:
            st.metric("Latest Batch Created", "N/A")

    with f3:
        try:
            # Upload timestamp needs timezone conversion to UTC
            result = session.sql("""
                SELECT TO_VARCHAR(
                    CONVERT_TIMEZONE('UTC', MAX(UPLOAD_TIMESTAMP)),
                    'YYYY-MM-DD HH24:MI:SS'
                ) as ts FROM DEDEMO.GAMING.REGULATORY_BATCHES
                WHERE STATUS = 'UPLOADED'
            """).collect()[0]['TS']
            st.metric("Latest SFTP Upload", result if result else "N/A")
        except:
            st.metric("Latest SFTP Upload", "N/A")


# =============================================================================
# TAB 2: CDC REPLICATION
# =============================================================================
with tab_cdc:
    st.header("CDC Replication")
    st.caption("External Postgres transactions replicated to Snowflake via OpenFlow CDC connector")

    # Replication metrics
    st.subheader("Replication Metrics")

    c1, c2, c3, c4 = st.columns(4)

    with c1:
        try:
            result = session.sql("""
                SELECT COUNT(*) as cnt FROM DEDEMO.TOURNAMENTS.POKER
            """).collect()[0]['CNT']
            st.metric("Total Replicated Records", f"{result:,}")
        except:
            st.metric("Total Replicated Records", "N/A")

    with c2:
        try:
            result = session.sql("""
                SELECT COUNT(*) as cnt FROM DEDEMO.TOURNAMENTS.POKER
                WHERE CREATED_TIMESTAMP > DATEADD(hour, -1, CURRENT_TIMESTAMP())
            """).collect()[0]['CNT']
            st.metric("Records (Last Hour)", f"{result:,}")
        except:
            st.metric("Records (Last Hour)", "N/A")

    with c3:
        try:
            result = session.sql("""
                SELECT ROUND(AVG(TIMESTAMPDIFF(second, CREATED_TIMESTAMP, _SNOWFLAKE_INSERTED_AT)), 1) as avg_lag
                FROM DEDEMO.TOURNAMENTS.POKER
                WHERE CREATED_TIMESTAMP > DATEADD(hour, -1, CURRENT_TIMESTAMP())
            """).collect()[0]['AVG_LAG']
            st.metric("Avg CDC Latency", f"{result:.1f} sec" if result else "N/A")
        except:
            st.metric("Avg CDC Latency", "N/A")

    with c4:
        try:
            result = session.sql("""
                SELECT MAX(_SNOWFLAKE_INSERTED_AT) as ts FROM DEDEMO.TOURNAMENTS.POKER
            """).collect()[0]['TS']
            st.metric("Last Replication", str(result)[:19] if result else "N/A")
        except:
            st.metric("Last Replication", "N/A")


    # CDC data with Snowflake metadata
    st.subheader("Replicated Data with CDC Metadata")
    st.caption("Shows raw JSONB from source plus Snowflake replication timestamps")

    try:
        cdc_df = session.sql("""
            SELECT
                TRANSACTION_ID,
                CREATED_TIMESTAMP as SOURCE_TIMESTAMP,
                _SNOWFLAKE_INSERTED_AT as REPLICATED_AT,
                TIMESTAMPDIFF(second, CREATED_TIMESTAMP, _SNOWFLAKE_INSERTED_AT) as REPLICATION_LAG_SEC,
                TRANSACTION_DATA
            FROM DEDEMO.TOURNAMENTS.POKER
            ORDER BY CREATED_TIMESTAMP DESC
            LIMIT 25
        """).to_pandas()

        if not cdc_df.empty:
            st.dataframe(cdc_df, use_container_width=True, height=400)
        else:
            st.caption("No CDC data available yet")
    except Exception as e:
        st.error(f"Error loading CDC data: {e}")


# =============================================================================
# TAB 3: DYNAMIC TABLE
# =============================================================================
with tab_dt:
    st.header("Dynamic Table")
    st.caption("Automatic transformation: JSONB flattened to structured columns with 1-minute refresh lag")

    # DT metrics
    st.subheader("Dynamic Table Status")

    d1, d2, d3 = st.columns(3)

    with d1:
        try:
            result = session.sql("""
                SELECT COUNT(*) as cnt FROM DEDEMO.GAMING.DT_POKER_FLATTENED
            """).collect()[0]['CNT']
            st.metric("Total Records", f"{result:,}")
        except:
            st.metric("Total Records", "N/A")

    with d2:
        st.metric("Target Lag", "1 minute")

    with d3:
        try:
            # Query DT metadata - use collect() then access as dict
            rows = session.sql("""
                SHOW DYNAMIC TABLES LIKE 'DT_POKER_FLATTENED' IN SCHEMA DEDEMO.GAMING
            """).collect()
            if rows:
                row_dict = rows[0].as_dict()
                state = row_dict.get('scheduling_state', row_dict.get('SCHEDULING_STATE', 'ACTIVE'))
                st.metric("Refresh State", state if state else "ACTIVE")
            else:
                st.metric("Refresh State", "ACTIVE")
        except Exception as e:
            # Fallback - DT exists and is working if we can query it
            st.metric("Refresh State", "ACTIVE")


    # Before: Raw JSONB
    st.subheader("Before: Raw JSONB from CDC")
    st.caption("Source data as replicated from Postgres - nested JSON structure")

    try:
        before_df = session.sql("""
            SELECT TRANSACTION_ID, TRANSACTION_DATA
            FROM DEDEMO.TOURNAMENTS.POKER
            ORDER BY CREATED_TIMESTAMP DESC
            LIMIT 5
        """).to_pandas()
        st.dataframe(before_df, use_container_width=True)
    except Exception as e:
        st.error(f"Error: {e}")


    # After: Flattened columns
    st.subheader("After: Flattened Columns")
    st.caption("Dynamic Table automatically extracts JSON fields to typed columns")

    try:
        dt_df = session.sql("""
            SELECT
                TRANSACTION_ID,
                CREATED_TIMESTAMP,
                TOURNAMENT_ID,
                TOURNAMENT_NAME,
                VARIANT,
                PLAYER_ID,
                BET_AMOUNT,
                WIN_AMOUNT,
                REFUND_AMOUNT,
                DEVICE_TYPE
            FROM DEDEMO.GAMING.DT_POKER_FLATTENED
            ORDER BY CREATED_TIMESTAMP DESC
            LIMIT 25
        """).to_pandas()

        if not dt_df.empty:
            st.dataframe(dt_df, use_container_width=True, height=400)
        else:
            st.caption("No data in dynamic table yet")
    except Exception as e:
        st.error(f"Error loading dynamic table: {e}")


# =============================================================================
# TAB 4: STREAM PROCESSING
# =============================================================================
with tab_stream:
    st.header("Stream Processing")
    st.caption("Stream consumption and batch processing activity")

    # Processing throughput metrics
    st.subheader("Processing Throughput")

    s1, s2, s3, s4 = st.columns(4)

    with s1:
        try:
            result = session.sql("""
                SELECT SUM(TRANSACTION_COUNT) as total
                FROM DEDEMO.GAMING.REGULATORY_BATCHES
                WHERE BATCH_TIMESTAMP > DATEADD(hour, -1, CURRENT_TIMESTAMP())
            """).collect()[0]['TOTAL']
            st.metric("Transactions (Last Hour)", f"{int(result or 0):,}")
        except:
            st.metric("Transactions (Last Hour)", "N/A")

    with s2:
        try:
            result = session.sql("""
                SELECT COUNT(*) as cnt
                FROM DEDEMO.GAMING.REGULATORY_BATCHES
                WHERE BATCH_TIMESTAMP > DATEADD(hour, -1, CURRENT_TIMESTAMP())
            """).collect()[0]['CNT']
            st.metric("Batches (Last Hour)", f"{result:,}")
        except:
            st.metric("Batches (Last Hour)", "N/A")

    with s3:
        try:
            result = session.sql("""
                SELECT ROUND(AVG(TRANSACTION_COUNT), 0) as avg_size
                FROM DEDEMO.GAMING.REGULATORY_BATCHES
            """).collect()[0]['AVG_SIZE']
            st.metric("Avg Batch Size", f"{int(result or 0):,}")
        except:
            st.metric("Avg Batch Size", "N/A")

    with s4:
        try:
            result = session.sql("""
                SELECT COUNT(*) as cnt FROM DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM
            """).collect()[0]['CNT']
            if result == 0:
                st.metric("Currently Pending", "0", delta="Fully consumed", delta_color="off")
            else:
                st.metric("Currently Pending", f"{result:,}")
        except:
            st.metric("Currently Pending", "N/A")


    # Processing activity over time
    st.subheader("Batch Processing Activity - Last 24 Hours (UTC)")

    try:
        import altair as alt

        activity_df = session.sql("""
            SELECT
                CONVERT_TIMEZONE('UTC', DATE_TRUNC('hour', BATCH_TIMESTAMP)) as HOUR_UTC,
                COUNT(*) as BATCHES_CREATED,
                SUM(TRANSACTION_COUNT) as TRANSACTIONS_PROCESSED
            FROM DEDEMO.GAMING.REGULATORY_BATCHES
            WHERE BATCH_TIMESTAMP > DATEADD(day, -1, CURRENT_TIMESTAMP())
            GROUP BY DATE_TRUNC('hour', BATCH_TIMESTAMP)
            ORDER BY DATE_TRUNC('hour', BATCH_TIMESTAMP)
        """).to_pandas()

        if not activity_df.empty:
            chart = alt.Chart(activity_df).mark_line(point=True).encode(
                x=alt.X('HOUR_UTC:T', title='Time (UTC)', axis=alt.Axis(format='%d %H:%M')),
                y=alt.Y('TRANSACTIONS_PROCESSED:Q', title='Transactions')
            ).properties(height=300)
            st.altair_chart(chart, use_container_width=True)

            # Format for display
            display_df = activity_df.copy()
            display_df['HOUR_UTC'] = display_df['HOUR_UTC'].dt.strftime('%Y-%m-%d %H:%M')
            st.dataframe(display_df, use_container_width=True)
        else:
            st.caption("No batch activity in the last 24 hours")
    except Exception as e:
        st.warning(f"Unable to load activity data: {e}")



# =============================================================================
# TAB 5: BATCHES
# =============================================================================
with tab_batches:
    st.header("Regulatory Batches")
    st.caption("XML batches generated for submission: signed with XAdES-BES, encrypted with AES-256")

    # Batch metrics
    st.subheader("Batch Processing Status (All Time)")

    b1, b2, b3, b4 = st.columns(4)

    try:
        batch_stats = session.sql("""
            SELECT
                COUNT(*) as TOTAL,
                SUM(CASE WHEN STATUS = 'GENERATED' THEN 1 ELSE 0 END) as PENDING,
                SUM(CASE WHEN STATUS = 'UPLOADED' THEN 1 ELSE 0 END) as UPLOADED,
                SUM(TRANSACTION_COUNT) as TOTAL_TXN
            FROM DEDEMO.GAMING.REGULATORY_BATCHES
        """).collect()[0]

        with b1:
            st.metric("Total Batches", f"{batch_stats['TOTAL']:,}")
        with b2:
            st.metric("Pending Upload", f"{batch_stats['PENDING']:,}")
        with b3:
            st.metric("Uploaded", f"{batch_stats['UPLOADED']:,}")
        with b4:
            st.metric("Transactions", f"{int(batch_stats['TOTAL_TXN'] or 0):,}")
    except:
        with b1:
            st.metric("Total Batches", "N/A")
        with b2:
            st.metric("Pending Upload", "N/A")
        with b3:
            st.metric("Uploaded", "N/A")
        with b4:
            st.metric("Transactions", "N/A")

    # Today's activity
    st.subheader("Today's Activity (UTC)")

    t1, t2, t3 = st.columns(3)

    try:
        today_stats = session.sql("""
            SELECT
                COUNT(*) as BATCHES_TODAY,
                SUM(CASE WHEN STATUS = 'UPLOADED' THEN 1 ELSE 0 END) as UPLOADED_TODAY,
                SUM(TRANSACTION_COUNT) as TXN_TODAY
            FROM DEDEMO.GAMING.REGULATORY_BATCHES
            WHERE DATEADD(hour, 8, BATCH_TIMESTAMP) >= DATE_TRUNC('day', CURRENT_TIMESTAMP())
        """).collect()[0]

        with t1:
            st.metric("Batches Today", f"{today_stats['BATCHES_TODAY']:,}")
        with t2:
            st.metric("Uploaded Today", f"{today_stats['UPLOADED_TODAY']:,}")
        with t3:
            st.metric("Transactions Today", f"{int(today_stats['TXN_TODAY'] or 0):,}")
    except:
        with t1:
            st.metric("Batches Today", "N/A")
        with t2:
            st.metric("Uploaded Today", "N/A")
        with t3:
            st.metric("Transactions Today", "N/A")


    # Recent batches
    st.subheader("Recent Batches")

    try:
        batches_df = session.sql("""
            SELECT
                BATCH_ID,
                STATUS,
                TRANSACTION_COUNT,
                BATCH_TIMESTAMP,
                UPLOAD_TIMESTAMP,
                GENERATED_FILENAME,
                OPERATOR_ID,
                WAREHOUSE_ID
            FROM DEDEMO.GAMING.REGULATORY_BATCHES
            ORDER BY BATCH_TIMESTAMP DESC
            LIMIT 20
        """).to_pandas()

        if not batches_df.empty:
            st.dataframe(batches_df, use_container_width=True)
        else:
            st.caption("No batches created yet")
    except Exception as e:
        st.error(f"Error loading batches: {e}")


    # XML preview
    st.subheader("Generated XML Preview")
    st.caption("Sample of regulatory XML format (XSD-compliant for DGOJ)")

    try:
        xml_sample = session.sql("""
            SELECT BATCH_ID, GENERATED_XML
            FROM DEDEMO.GAMING.REGULATORY_BATCHES
            WHERE GENERATED_XML IS NOT NULL
            ORDER BY BATCH_TIMESTAMP DESC
            LIMIT 1
        """).collect()

        if xml_sample and xml_sample[0]['GENERATED_XML']:
            batch_id = xml_sample[0]['BATCH_ID']
            xml_content = xml_sample[0]['GENERATED_XML']

            st.markdown(f"**Batch:** `{batch_id}`")

            # Pretty-print the XML
            try:
                import xml.dom.minidom as minidom
                dom = minidom.parseString(xml_content)
                pretty_xml = dom.toprettyxml(indent="  ")
                # Remove the XML declaration line that minidom adds
                pretty_lines = pretty_xml.split('\n')
                if pretty_lines[0].startswith('<?xml'):
                    pretty_lines = pretty_lines[1:]
                # Remove empty lines
                pretty_lines = [line for line in pretty_lines if line.strip()]
                # Limit to first 60 lines
                if len(pretty_lines) > 60:
                    preview_text = '\n'.join(pretty_lines[:60])
                    preview_text += f"\n\n<!-- ... {len(pretty_lines) - 60} more lines ... -->"
                else:
                    preview_text = '\n'.join(pretty_lines)
            except:
                # Fallback if XML parsing fails - just show raw with line breaks
                preview_text = xml_content[:3000]
                if len(xml_content) > 3000:
                    preview_text += "\n\n<!-- ... truncated ... -->"

            st.code(preview_text, language="xml")
        else:
            st.caption("No XML content available yet")
    except Exception as e:
        st.warning(f"Unable to load XML preview: {e}")


# =============================================================================
# TAB 6: OBSERVABILITY
# =============================================================================
with tab_obs:
    st.header("Pipeline Health Summary")
    st.caption("Key operational metrics - use Ask Cortex tab for deeper analysis")

    # Health status indicators
    st.subheader("System Health")

    h1, h2, h3, h4 = st.columns(4)

    with h1:
        try:
            result = session.sql("""
                SELECT COUNT(*) as cnt FROM DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY
                WHERE HOUR > DATEADD(hour, -1, CURRENT_TIMESTAMP())
                AND LOG_LEVEL = 'ERROR'
            """).collect()[0]['CNT']
            if result == 0:
                st.metric("Errors (1h)", "None", delta="Healthy", delta_color="normal")
            else:
                st.metric("Errors (1h)", f"{result}", delta="Review needed", delta_color="inverse")
        except:
            st.metric("Errors (1h)", "N/A")

    with h2:
        try:
            result = session.sql("""
                SELECT AVG_SEC FROM DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS
                WHERE STAGE = 'CDC Replication'
            """).collect()[0]['AVG_SEC']
            if result:
                latency = float(result)
                if latency < 30:
                    st.metric("CDC Latency", f"{latency:.0f}s", delta="Normal", delta_color="normal")
                else:
                    st.metric("CDC Latency", f"{latency:.0f}s", delta="Elevated", delta_color="inverse")
            else:
                st.metric("CDC Latency", "N/A")
        except:
            st.metric("CDC Latency", "N/A")

    with h3:
        try:
            result = session.sql("""
                SELECT COUNT(*) as cnt FROM DEDEMO.GAMING.REGULATORY_BATCHES
                WHERE STATUS = 'UPLOADED'
                AND UPLOAD_TIMESTAMP > DATEADD(hour, -1, CURRENT_TIMESTAMP())
            """).collect()[0]['CNT']
            st.metric("Uploads (1h)", f"{result}")
        except:
            st.metric("Uploads (1h)", "N/A")

    with h4:
        try:
            result = session.sql("""
                SELECT COUNT(*) as cnt FROM DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM
            """).collect()[0]['CNT']
            st.metric("Stream Backlog", f"{result}")
        except:
            st.metric("Stream Backlog", "N/A")


    # Latency summary - simplified
    st.subheader("End-to-End Latency (Last Hour)")

    l1, l2 = st.columns(2)

    with l1:
        try:
            result = session.sql("""
                SELECT AVG_SEC FROM DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS
                WHERE STAGE = 'TOTAL END-TO-END'
            """).collect()[0]['AVG_SEC']
            if result:
                st.metric("Average", f"{float(result):.0f} seconds")
            else:
                st.metric("Average", "Calculating...")
        except:
            st.metric("Average", "N/A")

    with l2:
        try:
            result = session.sql("""
                SELECT MAX_SEC FROM DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS
                WHERE STAGE = 'TOTAL END-TO-END'
            """).collect()[0]['MAX_SEC']
            if result:
                st.metric("Maximum", f"{float(result):.0f} seconds")
            else:
                st.metric("Maximum", "Calculating...")
        except:
            st.metric("Maximum", "N/A")


    # Processing volume timeline
    st.subheader("Transaction Volume - Last 24 Hours (UTC)")

    try:
        import altair as alt

        timeline_df = session.sql("""
            SELECT
                CONVERT_TIMEZONE('UTC', DATE_TRUNC('hour', BATCH_TIMESTAMP)) as HOUR_UTC,
                SUM(TRANSACTION_COUNT) as TRANSACTIONS
            FROM DEDEMO.GAMING.REGULATORY_BATCHES
            WHERE BATCH_TIMESTAMP > DATEADD(day, -1, CURRENT_TIMESTAMP())
            GROUP BY DATE_TRUNC('hour', BATCH_TIMESTAMP)
            ORDER BY DATE_TRUNC('hour', BATCH_TIMESTAMP)
        """).to_pandas()

        if not timeline_df.empty:
            chart = alt.Chart(timeline_df).mark_bar().encode(
                x=alt.X('HOUR_UTC:T', title='Time (UTC)', axis=alt.Axis(format='%d %H:%M')),
                y=alt.Y('TRANSACTIONS:Q', title='Transactions')
            ).properties(height=300)
            st.altair_chart(chart, use_container_width=True)
        else:
            st.caption("No batch activity in the last 24 hours")
    except Exception as e:
        st.warning(f"Unable to load timeline: {e}")


    # Pointer to Cortex for deeper analysis
    st.caption("For detailed analysis of errors, latency patterns, or anomalies, use the Ask Cortex tab.")


# =============================================================================
# TAB 7: LOGS
# =============================================================================
with tab_logs:
    st.header("Pipeline Logs")
    st.caption("Recent log entries from OpenFlow pipeline components")

    # Error summary section
    st.subheader("Recent Errors")
    try:
        errors_df = session.sql("""
            SELECT
                CONVERT_TIMEZONE('UTC', HOUR) as TIME_UTC,
                PROCESS_GROUP,
                ERROR_COUNT,
                UNIQUE_ERRORS
            FROM DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY
            WHERE LOG_LEVEL = 'ERROR'
            AND HOUR > DATEADD(day, -7, CURRENT_TIMESTAMP())
            ORDER BY HOUR DESC
            LIMIT 20
        """).to_pandas()

        if not errors_df.empty:
            st.dataframe(errors_df, use_container_width=True)
        else:
            st.success("No errors in the last 7 days")
    except Exception as e:
        st.warning(f"Unable to load error summary: {e}")


    # Warnings section
    st.subheader("Recent Warnings")
    try:
        warnings_df = session.sql("""
            SELECT
                CONVERT_TIMEZONE('UTC', HOUR) as TIME_UTC,
                PROCESS_GROUP,
                ERROR_COUNT as WARNING_COUNT,
                UNIQUE_ERRORS as UNIQUE_WARNINGS
            FROM DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY
            WHERE LOG_LEVEL = 'WARN'
            AND HOUR > DATEADD(day, -7, CURRENT_TIMESTAMP())
            ORDER BY HOUR DESC
            LIMIT 20
        """).to_pandas()

        if not warnings_df.empty:
            st.dataframe(warnings_df, use_container_width=True)
        else:
            st.success("No warnings in the last 7 days")
    except Exception as e:
        st.warning(f"Unable to load warnings: {e}")


    # Log viewer section
    st.subheader("Log Viewer")

    log_col1, log_col2 = st.columns(2)
    with log_col1:
        log_level_filter = st.selectbox(
            "Log Level",
            ["All", "ERROR", "WARN", "INFO"],
            index=0
        )
    with log_col2:
        log_limit = st.selectbox(
            "Show entries",
            [50, 100, 200],
            index=0
        )

    try:
        level_clause = ""
        if log_level_filter != "All":
            level_clause = f"AND LOG_LEVEL = '{log_level_filter}'"

        logs_df = session.sql(f"""
            SELECT
                CONVERT_TIMEZONE('UTC', EVENT_TIMESTAMP) as TIME_UTC,
                LOG_LEVEL,
                COALESCE(PROCESS_GROUP, LOGGER) as COMPONENT,
                MESSAGE
            FROM DEDEMO.GAMING.OPENFLOW_LOGS
            WHERE EVENT_TIMESTAMP > DATEADD(day, -7, CURRENT_TIMESTAMP())
            {level_clause}
            ORDER BY EVENT_TIMESTAMP DESC
            LIMIT {log_limit}
        """).to_pandas()

        if not logs_df.empty:
            st.dataframe(logs_df, use_container_width=True)
        else:
            st.caption("No log entries found matching the filter")
    except Exception as e:
        st.warning(f"Unable to load logs: {e}")


# =============================================================================
# TAB 8: ASK CORTEX
# =============================================================================
with tab_cortex:
    st.header("Ask Cortex Analyst")
    st.caption("Natural language queries against the gaming pipeline operational data")

    # Helper function to run query and display results
    def run_cortex_query(question):
        st.markdown(f"**Question:** {question}")

        with st.spinner("Analyzing with Cortex Agent..."):
            try:
                response = cortex_agent_call(question, None)
                text, sql, _ = process_agent_response(response)

                if text:
                    st.markdown(f"**Answer:** {text}")

                    if sql:
                        try:
                            result_df = session.sql(sql).to_pandas()
                            if not result_df.empty:
                                st.dataframe(result_df, use_container_width=True)
                        except Exception as sql_err:
                            st.warning(f"Could not execute query: {sql_err}")

                        with st.expander("View Generated SQL"):
                            st.code(sql, language="sql")
                else:
                    st.warning("Unable to process that question. Please try rephrasing.")

            except Exception as e:
                st.error(f"Error: {e}")

    # Sample questions - clicking runs immediately
    st.subheader("Sample Questions")
    sample_questions = [
        "How many batches were processed today?",
        "What is the average latency for each pipeline stage?",
        "Show me batch processing performance over the last week",
        "Are there any errors in the last 24 hours?",
        "What is the total number of transactions processed?"
    ]

    # Track which sample was clicked
    clicked_sample = None

    cols = st.columns(3)
    for i, q in enumerate(sample_questions[:3]):
        with cols[i]:
            if st.button(q, key=f"sample_{i}", use_container_width=True):
                clicked_sample = q

    cols2 = st.columns(2)
    for i, q in enumerate(sample_questions[3:]):
        with cols2[i]:
            if st.button(q, key=f"sample_{i+3}", use_container_width=True):
                clicked_sample = q


    # Custom question input
    st.subheader("Or Ask Your Own Question")

    col_input, col_btn = st.columns([4, 1])
    with col_input:
        custom_question = st.text_input(
            "Question:",
            placeholder="Ask about batches, latency, errors, transactions...",
            label_visibility="collapsed"
        )
    with col_btn:
        ask_clicked = st.button("Ask", type="primary", use_container_width=True)


    # Run query based on what was clicked
    if clicked_sample:
        run_cortex_query(clicked_sample)
    elif ask_clicked and custom_question:
        run_cortex_query(custom_question)
    else:
        st.caption("Click a sample question above or type your own question to get started.")


# Footer
st.caption("BOE Gaming Regulatory Pipeline Monitor | Data refreshes on tab selection")

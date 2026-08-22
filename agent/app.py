"""
Revenue Intelligence Platform - conversational data agent, Streamlit UI.

Run locally:
    streamlit run app.py

Constants and the system prompt are imported from main.py so there is one
definition of each.
"""

import asyncio
import json
import logging
import threading
import uuid
from concurrent.futures import TimeoutError as FutureTimeout

import streamlit as st
from langchain.agents import create_agent
from langchain_google_vertexai import ChatVertexAI
from langgraph.checkpoint.memory import InMemorySaver
from toolbox_core import auth_methods
from toolbox_langchain import ToolboxClient

from main import LOCATION, PROJECT_ID, SYSTEM_PROMPT, TOOLBOX_URL, TOOLSET

REQUEST_TIMEOUT_SECONDS = 120

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

st.set_page_config(page_title="Revenue Intelligence Platform by Promise Ezeike", page_icon="📊")


# ---------------------------------------------------------------------------
# Async runtime.
#
# Streamlit runs each active session's script on its own thread, and asyncio
# event loops cannot safely be driven from more than one thread. So a single
# dedicated thread owns one persistent loop for the whole process, and every
# session submits work to it with run_coroutine_threadsafe rather than calling
# run_until_complete on a loop belonging to another thread.
#
# The agent, tools and Toolbox client stay genuine singletons, which is safe
# because they are only ever driven from the loop that created them.
# ---------------------------------------------------------------------------
async def _build_agent():
    auth_token_provider = auth_methods.get_google_id_token(TOOLBOX_URL)
    client = ToolboxClient(
        TOOLBOX_URL,
        client_headers={"Authorization": auth_token_provider},
    )
    tools = await client.aload_toolset(TOOLSET)

    model = ChatVertexAI(
        model="gemini-2.5-flash",
        project=PROJECT_ID,
        location=LOCATION,
        temperature=0,
    )

    agent = create_agent(
        model,
        tools,
        system_prompt=SYSTEM_PROMPT,
        # NOTE: InMemorySaver is documented as debugging/testing only.
        # Conversation history is lost on restart and never evicted. Fine for
        # a single-instance demo; swap for a persistent checkpointer before
        # anyone relies on this.
        checkpointer=InMemorySaver(),
    )
    # The client is returned so a reference survives; the tools depend on it.
    return agent, client, len(tools)


@st.cache_resource(show_spinner="Connecting to the mart layer...")
def get_runtime():
    loop = asyncio.new_event_loop()
    threading.Thread(
        target=loop.run_forever, daemon=True, name="agent-event-loop"
    ).start()
    agent, client, tool_count = asyncio.run_coroutine_threadsafe(
        _build_agent(), loop
    ).result()
    return agent, client, loop, tool_count


def extract_text(content) -> str:
    """Gemini returns content as either a string or a list of blocks."""
    if isinstance(content, list):
        return "".join(
            b.get("text", "") for b in content if isinstance(b, dict)
        )
    return content or ""


def extract_tool_calls(messages) -> list[dict]:
    """
    Read the tools that were actually invoked from the message history.

    Deliberately not the model's own account of what it did. Every AIMessage
    carries a tool_calls list with the tool name and the arguments passed, so
    for run_query this holds the SQL that genuinely executed against BigQuery.
    """
    calls = []
    for message in messages:
        for call in getattr(message, "tool_calls", None) or []:
            calls.append(
                {"name": call.get("name", "unknown"), "args": call.get("args", {})}
            )
    return calls


def render_tool_calls(calls: list[dict]) -> None:
    if not calls:
        return
    label = f"Show what ran ({len(calls)} tool call{'s' if len(calls) != 1 else ''})"
    with st.expander(label):
        for call in calls:
            st.caption(call["name"])
            sql = call["args"].get("sql")
            if sql:
                st.code(sql, language="sql")
            elif call["args"]:
                st.code(json.dumps(call["args"], indent=2), language="json")


def ask(agent, loop, question: str, thread_id: str):
    """Submit a question to the agent's loop and wait for the answer."""
    future = asyncio.run_coroutine_threadsafe(
        agent.ainvoke(
            {"messages": [{"role": "user", "content": question}]},
            config={"configurable": {"thread_id": thread_id}},
        ),
        loop,
    )
    try:
        result = future.result(timeout=REQUEST_TIMEOUT_SECONDS)
    except FutureTimeout:
        # future.result() only stops this thread waiting; the coroutine keeps
        # running on the background loop. Calling future.cancel() directly is
        # not reliable here -- it runs on this thread, not the loop's own
        # thread, and asyncio's docs (and CPython issue #105836) note this can
        # leave the underlying Task running regardless. Schedule the
        # cancellation onto the owning loop instead so it actually reaches it.
        loop.call_soon_threadsafe(future.cancel)
        raise
    return (
        extract_text(result["messages"][-1].content),
        extract_tool_calls(result["messages"]),
    )


# ---------------------------------------------------------------------------
# Session state
# ---------------------------------------------------------------------------
if "thread_id" not in st.session_state:
    st.session_state.thread_id = str(uuid.uuid4())
if "history" not in st.session_state:
    st.session_state.history = []

agent, _client, loop, tool_count = get_runtime()

st.title("Revenue Intelligence Platform by Promise Ezeike")
st.caption("Ask about revenue, churn, or the sales funnel.")

with st.sidebar:
    st.subheader("About")
    st.write(
        "Answers come from three dbt mart models in BigQuery: revenue, "
        "customer churn and sales funnel. Every row has passed 95 automated "
        "dbt tests before it reaches this layer."
    )
    st.write(
        f"The agent has {tool_count} read-only tools. It inspects a table's "
        "documented column meanings before writing any SQL, and will say so "
        "when the data cannot answer a question."
    )
    if st.button("Clear conversation"):
        st.session_state.thread_id = str(uuid.uuid4())
        st.session_state.history = []
        st.rerun()

# Replay history on each rerun
for entry in st.session_state.history:
    with st.chat_message(entry["role"]):
        st.markdown(entry["content"])
        if entry["role"] == "assistant":
            render_tool_calls(entry.get("tool_calls", []))

# ---------------------------------------------------------------------------
# Handle a new question
# ---------------------------------------------------------------------------
question = st.chat_input("e.g. which tier has the highest average churn risk?")

if question:
    st.session_state.history.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(question)

    with st.chat_message("assistant"):
        with st.spinner("Working..."):
            try:
                answer, tool_calls = ask(
                    agent, loop, question, st.session_state.thread_id
                )
            except FutureTimeout:
                logger.warning("Agent timed out on question: %s", question)
                answer = (
                    "That took too long to answer. Try narrowing the question, "
                    "for example to a single tier or a shorter period."
                )
                tool_calls = []
            except Exception:  # noqa: BLE001
                logger.exception("Agent invocation failed")
                answer = (
                    "Something went wrong answering that. Please try again, or "
                    "rephrase the question."
                )
                tool_calls = []

        st.markdown(answer)
        render_tool_calls(tool_calls)

    st.session_state.history.append(
        {"role": "assistant", "content": answer, "tool_calls": tool_calls}
    )
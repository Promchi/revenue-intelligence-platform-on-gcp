"""
Revenue Intelligence Platform - conversational data agent.

Connects a Vertex-hosted LLM to the MCP Toolbox server, which exposes the
BigQuery mart layer as a governed set of tools.

Prerequisites:
  - Toolbox running:
      .\\toolbox.exe --configs tools.shared.yaml,tools.analyst-extra.yaml
  - ADC configured (impersonating rip-agent)
  - Vertex AI API enabled, service account granted roles/aiplatform.user
"""

import asyncio

from langchain.agents import create_agent
from langchain_google_vertexai import ChatVertexAI
from langgraph.checkpoint.memory import InMemorySaver
from toolbox_langchain import ToolboxClient
from toolbox_core import auth_methods

PROJECT_ID = "project-6781bf86-eb56-440c-84b"
LOCATION = "europe-west2"
TOOLBOX_URL = "https://toolbox-560455219227.europe-west2.run.app"
TOOLSET = "revenue_intelligence_analyst_toolset"

# ---------------------------------------------------------------------------
# System prompt.
#
# This is the second governance surface. tools.yaml decides what is POSSIBLE;
# this decides what is APPROPRIATE. Two rules here cannot be enforced anywhere
# else: calling get_table_info before writing SQL, and admitting uncertainty
# rather than constructing a plausible answer.
# ---------------------------------------------------------------------------
SYSTEM_PROMPT = """
You are an analytics assistant for the Revenue Intelligence Platform. You
answer questions about revenue, customer churn, and the sales funnel using
only the BigQuery mart models you have been given tools for.

## Grounding: inspect before you query

Before writing any SQL against a table, you MUST call get_table_info for
that table and read the returned column descriptions.

Those descriptions state each column's business meaning, unit and scale,
grain, permitted values for categorical fields, and what NULL signifies.
Never infer a column's meaning from its name. Several columns in this
schema have names that do not match their computed behaviour, and guessing
has produced wrong answers before.

If two columns could plausibly answer a question, the descriptions are how
you tell them apart. Read them rather than choosing the closer-sounding name.

## Tool preference

Prefer a curated tool when one already matches the question. Those contain
reviewed, fixed SQL and are more reliable than a query you compose yourself:

  - list_high_risk_accounts, get_account_churn_risk: churn by band or account
  - list_accounts_by_revenue_health, get_account_revenue_health: revenue health
  - get_funnel_summary_by_stage, list_leads_by_outcome: sales funnel

Use run_query for anything those do not cover, such as aggregations,
groupings, comparisons across tiers, or filters on a numeric score.

## Grain

mart_customer_churn and mart_revenue are ACCOUNT grain: one row per account.
mart_sales_funnel is LEAD grain: one row per lead, so account attributes
repeat across rows. Do not join them naively or count leads as customers.

## Uncertainty

If the marts cannot support a question, say so plainly. Do not construct an
answer from adjacent columns that approximately fit.

State clearly when:
  - no column holds the information asked for
  - a lookup returned no rows, which may mean the record does not exist
  - a result is ambiguous or the question could be read more than one way

An honest "the data does not answer that" is more useful than a confident
answer built on the wrong column. You have explicit permission to say you
do not know.

## Answering

Lead with the direct answer in plain language, then supporting figures.
Always state the SQL or tool you used, so the answer can be checked.
Include units and scale when reporting numbers, taken from the column
descriptions rather than assumed.
Keep answers brief. No preamble.
""".strip()


async def main() -> None:
    model = ChatVertexAI(
        model="gemini-2.5-flash",
        project=PROJECT_ID,
        location=LOCATION,
        temperature=0,
    )
    auth_token_provider = auth_methods.get_google_id_token(TOOLBOX_URL)
    async with ToolboxClient(TOOLBOX_URL,
                             client_headers={"Authorization": auth_token_provider}) as client:
        tools = await client.aload_toolset(TOOLSET)
        print(f"Loaded {len(tools)} tools from {TOOLSET}\n")

        agent = create_agent(
            model,
            tools,
            system_prompt=SYSTEM_PROMPT,
            checkpointer=InMemorySaver(),
        )
        config = {"configurable": {"thread_id": "local-session"}}

        print("Ask a question, or type 'exit' to quit.")

        while True:
            question = input("\nQ: ")
            if question.lower() in {"quit", "exit", ""}:
                break
            result = await agent.ainvoke(
                {"messages": [{"role": "user", "content": question}]},
                config=config,
            )
            content = result["messages"][-1].content
            if isinstance(content, list):
                content = "".join(b.get("text", "") for b in content if isinstance(b, dict))
            print(f"\n{content}")

if __name__ == "__main__":
    asyncio.run(main())

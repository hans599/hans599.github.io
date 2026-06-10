---
title: LangGraph实战
date: 2026-06-09
tags: LangGraph
mathjax: true
---


# 前言：为什么需要LangGraph？

## 手写ReAct的问题
实现一个简单的“思考-行动-观察”（ReAct）循环似乎并不难，但随着业务复杂度的提升，手写方式会暴露三个核心痛点：

- 状态管理混乱：在多轮工具调用和推理步骤中，消息历史、中间结果、上下文等信息散落在各处，难以统一管理和持久化。

- 复杂流程难以维护：当需要引入循环、条件分支、并行执行或人工介入时，手写的 while 循环和 if-else 会迅速演变成难以调试的“意大利面式”代码。

- 没有现成的调试工具：Agent 的执行过程像一个“黑盒”，你很难清晰地看到它在每一步的思考、工具调用和状态变化，问题排查非常痛苦。


## LangGraph是什么


LangGraph 是一个基于图结构的 Agent 编排框架。它将 Agent 的每一步（如思考、调用工具、输出结果）抽象为图中的一个节点（Node），将执行路径的流转抽象为边（Edge）。

- 状态图（StateGraph）：内置了全局状态管理，每个节点都基于当前状态进行更新，状态变化可追溯。

- 循环与分支：天然支持 if-else 条件分支和 for/while 循环，完美契合 Agent 所需的“多步推理直至完成任务”的模式。

- 可观测性：原生支持与 [LangSmith](https://docs.langchain.com/langsmith/home)集成，可以可视化每个节点的输入、输出和执行耗时，让 Agent 执行过程“白盒化”。（ LangSmith 可以监控和调试背后的 LLM 调用）

官方文档：[LangChain Docs](https://docs.langchain.com/)  ，以下是官方对LangGraph的介绍：  

LangGraph 的层级非常低，且完全专注于智能体编排。在使用 LangGraph 之前，建议你先熟悉一些用于构建智能体的基本组件，从模型和工具开始。

在整个文档中，我们通常会使用 LangChain 的组件来集成模型和工具，但使用 LangGraph 并不强制要求你同时使用 LangChain。如果你刚开始接触智能体，或者想要一个更高级别的抽象，我们建议你使用 LangChain 自带的智能体（agents），它们为常见的 LLM 和工具调用循环提供了预置架构。

LangGraph 专注于智能体编排中重要的底层能力：持久化执行、流式处理、人机协同（human-in-the-loop）等等。


# LangGraph核心概念速览

## State
State 是一个共享的、可变的字典对象，在整个图（Graph）的执行过程中，所有节点都可以读取和更新它。

- 核心作用：让不同节点之间能够“记住”之前发生了什么。例如：LLM 生成的响应、工具调用的结果、对话历史等，都存放在 State 中。

- 实现方式：通常用一个 TypedDict 或 Pydantic 模型来定义 State 的结构，LangGraph 会自动处理状态的合并与更新。

```py
# 示例：定义一个简单的 State
class AgentState(TypedDict):
    messages: list        # 存储对话历史和中间消息
    next_step: str        # 控制下一步走向
    retry_count: int      # 记录重试次数
```

## Node
Node 是图中的一个顶点，代表一个具体的执行步骤。它本质上是一个 函数，接收当前 State，返回一个更新字典。

常见节点类型：

| 节点类型 | 功能 | 示例 |
| :--- | :--- | :--- |
| **LLM节点** | 调用大语言模型生成响应 | `call_llm(state)` |
| **Tool节点** | 执行一个或多个工具函数 | `execute_tools(state)` |
| **路由节点** | 仅做判断，不修改业务数据 | `should_continue(state)` |
| **预处理/后处理节点** | 清洗数据、格式化输出 | `format_output(state)` |

```py
# 节点函数示例
def call_llm(state: AgentState):
    response = llm.invoke(state["messages"])
    return {"messages": state["messages"] + [response]}
```


## Edge
Edge 是节点之间的连线，定义了“上一个节点结束后，接下来去哪个节点”。

普通边：固定走向
从一个节点出发，无条件地跳转到另一个指定节点。

```py
graph.add_edge("node_A", "node_B")   # A 执行完 → 总是去 B
```


条件边：根据结果分支
从一个节点出发，根据当前 State 的值或节点返回的结果，动态选择下一个节点。

```py
# 根据 LLM 返回的 next_step 字段决定去向
graph.add_conditional_edges(
    "call_llm",
    lambda state: state["next_step"],   # 路由函数
    {
        "continue": "execute_tools",    # 如果是 "continue" → 去工具节点
        "end": "__end__"                # 如果是 "end" → 结束流程
    }
)

```

## 图解工作流程

```
                     ┌─────────────────┐
                     │   START（入口）   │
                     └────────┬────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │   Node: call_llm │  ← 读取 State 中的 messages
                     │   （调用LLM思考）  │     决定是否需要调用工具
                     └────────┬────────┘
                              │
                    ┌─────────┴─────────┐
                    │  条件边: 需要工具?  │
                    └─────────┬─────────┘
                              │
              ┌───────────────┴───────────────┐
              │ 是                              │ 否
              ▼                                 ▼
    ┌─────────────────┐              ┌─────────────────┐
    │ Node: tools     │              │    Node: output  │
    │  （执行工具）     │              │   （输出最终答案） │
    └────────┬────────┘              └────────┬────────┘
              │                                 │
              │ （将工具结果追加到 State）          │
              │                                 │
              ▼                                 ▼
    ┌─────────────────┐              ┌─────────────────┐
    │     普通边       │              │      END        │
    │ （回到 call_llm） │              │   （流程结束）    │
    └─────────────────┘              └─────────────────┘
    
```


流程说明：

1. START → call_llm：开始执行，LLM 节点基于当前 State 进行推理。

2. 条件边：检查 LLM 的输出。

    - 如果 LLM 需要调用工具（如查询天气、搜索知识），走向 tools 节点。

    - 如果 LLM 已经得出最终答案，走向 output 节点。

3. tools：执行具体的工具函数（如 API 调用），将结果追加到 State 的 messages 中。

4. 普通边：执行完工具后，无条件返回 call_llm 节点，让 LLM 基于工具结果继续推理。

5. output：输出最终答案，流程结束。

核心特点：通过这种“LLM → 工具 → LLM → 工具 → LLM → 结束”的循环结构，LangGraph 让 Agent 能够自主、多步地完成复杂任务，而手写代码很难优雅地维护这种带状态循环的逻辑。



# 实战演练

## LLM模型准备

可以采用API的形式调用在线的大模型的接口，也可以本地通过ollama调用离线的。本着学习的目的，这里用本地实现。

下载ollama客户端：[https://ollama.com/download](https://ollama.com/download)

安装完成后，在cmd中输入命令安装模型，例如

``` 
# deepseek
ollama pull deepseek-r1:1.5b

# 千问
ollama pull qwen2.5:3b    # 推荐
```

## 安装python依赖

```cmd
pip install langgraph langchain-openai
```


## 定义工具（Tool）


LangChain工具，用`@tool`装饰器
```py
@tool
def roll_dice(sides: int = 6) -> str:
    """掷骰子，sides表示骰子的面数（默认6面）"""
    result = random.randint(1, sides)
    return f"🎲 掷了一个{sides}面骰子，结果：{result}"

@tool
def calculator(expression: str) -> str:
    """计算数学表达式，例如 '20 - 15' 或 'sqrt(16)' 或 '(10+5)*2'"""
    allowed_names = {k: v for k, v in math.__dict__.items() if not k.startswith("_")}
    allowed_names.update({"abs": abs, "round": round})
    try:
        result = eval(expression, {"__builtins__": {}}, allowed_names)
        return f"🧮 {expression} = {result}"
    except Exception as e:
        return f"计算错误：{e}"



if __name__ == "__main__":
    # 测试调用
    print(roll_dice.invoke({"sides": 20}))
    print(calculator.invoke({"expression": "(10+5)*2"}))
    
```

添加 Emoji 是为了区分 LLM 调用了工具，而不是它自身的语言输出，输出结果如下：
```
🎲 掷了一个20面骰子，结果：1
🧮 (10+5)*2 = 30
```

## 构建多工具Agent

```py
from langchain_core.tools import tool
from langchain_core.messages import BaseMessage, HumanMessage, AIMessage
from langchain_openai import ChatOpenAI
from langgraph.graph import StateGraph, END, add_messages
from langgraph.prebuilt import ToolNode
from typing import TypedDict, Annotated, List
import random
import math

import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# 导入自定义 LOG 函数
from utils import LOG

# ========== 2. 配置 ==========
OLLAMA_BASE_URL = "http://localhost:11434/v1"
OLLAMA_API_KEY = "ollama"
OLLAMA_MODEL = "qwen2.5:3b"  
TEMPERATURE = 0

LOG("配置加载完成", "INFO")

# ========== 3. 定义工具 ==========
@tool
def roll_dice(sides: int = 6) -> str:
    """掷骰子，sides表示骰子的面数（默认6面）"""
    result = random.randint(1, sides)
    LOG(f"掷骰子工具被调用，sides={sides}, result={result}", "DEBUG")
    return f"🎲 掷了一个{sides}面骰子，结果：{result}"

@tool
def calculator(expression: str) -> str:
    """计算数学表达式，例如 '20 - 15' 或 'sqrt(16)' 或 '(10+5)*2'"""
    allowed_names = {k: v for k, v in math.__dict__.items() if not k.startswith("_")}
    allowed_names.update({"abs": abs, "round": round})
    try:
        result = eval(expression, {"__builtins__": {}}, allowed_names)
        LOG(f"计算器工具被调用，expression={expression}, result={result}", "DEBUG")
        return f"🧮 {expression} = {result}"
    except Exception as e:
        LOG(f"计算错误：{e}", "ERROR")
        return f"计算错误：{e}"

tools = [roll_dice, calculator]
LOG(f"工具加载完成，共 {len(tools)} 个工具", "INFO")

# ========== 4. 定义状态结构 ==========
class AgentState(TypedDict):
    messages: Annotated[List[BaseMessage], add_messages]

LOG("状态结构定义完成", "DEBUG")

# ========== 5. 初始化 LLM 并绑定工具 ==========
llm = ChatOpenAI(
    base_url=OLLAMA_BASE_URL,
    api_key=OLLAMA_API_KEY,
    model=OLLAMA_MODEL,
    temperature=TEMPERATURE
)
llm_with_tools = llm.bind_tools(tools)
LOG(f"LLM 初始化完成，模型：{OLLAMA_MODEL}", "INFO")

# ========== 6. 定义图节点函数 ==========
def call_llm(state: AgentState):
    """LLM 节点：调用模型生成响应"""
    LOG("进入 LLM 节点", "DEBUG")
    response = llm_with_tools.invoke(state["messages"])
    
    # 判断是否调用了工具
    if hasattr(response, "tool_calls") and response.tool_calls:
        LOG(f"LLM 决策：调用工具 {response.tool_calls[0]['name']}", "INFO")
    else:
        LOG("LLM 决策：直接回答", "INFO")
    
    return {"messages": [response]}

def should_continue(state: AgentState):
    """路由函数：判断是否需要调用工具"""
    last_message = state["messages"][-1]
    if hasattr(last_message, "tool_calls") and last_message.tool_calls:
        LOG("路由决策：需要调用工具 → 前往 tools 节点", "DEBUG")
        return "tools"
    LOG("路由决策：无需调用工具 → 结束流程", "DEBUG")
    return "end"

# ========== 7. 构建并编译图 ==========
workflow = StateGraph(AgentState)

# 添加节点
workflow.add_node("llm", call_llm)
workflow.add_node("tools", ToolNode(tools))

# 设置入口
workflow.set_entry_point("llm")

# 添加边
workflow.add_conditional_edges("llm", should_continue, {
    "tools": "tools",
    "end": END
})
workflow.add_edge("tools", "llm")

# 编译
app = workflow.compile()

# ========== 8. 测试运行 ==========
if __name__ == "__main__":
    test_queries = [
        "帮我掷个骰子",
        "帮我算一下 127 * 38 等于多少",
        # 不会调用工具的问题（直接回答）
        "你好，你叫什么名字？",
        "什么是人工智能？",
        "谢谢你的帮助",
    ]
    
    config = {"configurable": {"thread_id": "test_user"}}
    LOG(f"测试配置创建完成，thread_id: test_user", "INFO")
    
    for idx, query in enumerate(test_queries, 1):
        print(f"\n{'='*50}\n用户: {query}\n")
        
        for step in app.stream(
            {"messages": [HumanMessage(content=query)]},
            config=config
        ):
            for node_name, output in step.items():
                if "messages" in output:
                    last_msg = output["messages"][-1]
                    
                    # 打印工具调用
                    if hasattr(last_msg, "tool_calls") and last_msg.tool_calls:
                        for tc in last_msg.tool_calls:
                            print(f"🔧 调用工具: {tc['name']}")
                    
                    # 打印内容（区分节点）
                    if hasattr(last_msg, "content") and last_msg.content:
                        if node_name == "llm":
                            print(f"🤖 Agent: {last_msg.content}")
                        elif node_name == "tools":
                            print(f"📦 工具结果: {last_msg.content}")
    
    LOG("所有测试完成", "INFO")
                        
```


输出结果
```
==================================================
用户: 帮我掷个骰子

[DEBUG] 02-langgraph.py:68 - 进入 LLM 节点
[INFO] 02-langgraph.py:73 - LLM 决策：调用工具 roll_dice
[DEBUG] 02-langgraph.py:83 - 路由决策：需要调用工具 → 前往 tools 节点
🔧 调用工具: roll_dice
[DEBUG] 02-langgraph.py:30 - 掷骰子工具被调用，sides=6, result=4
📦 工具结果: 🎲 掷了一个6面骰子，结果：4
[DEBUG] 02-langgraph.py:68 - 进入 LLM 节点
[INFO] 02-langgraph.py:75 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:85 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 你掷的这个6面骰子的结果是4。

==================================================
用户: 帮我算一下 127 * 38 等于多少

[DEBUG] 02-langgraph.py:68 - 进入 LLM 节点
[INFO] 02-langgraph.py:73 - LLM 决策：调用工具 calculator
[DEBUG] 02-langgraph.py:83 - 路由决策：需要调用工具 → 前往 tools 节点
🔧 调用工具: calculator
[DEBUG] 02-langgraph.py:40 - 计算器工具被调用，expression=127 * 38, result=4826
📦 工具结果: 🧮 127 * 38 = 4826
[DEBUG] 02-langgraph.py:68 - 进入 LLM 节点
[INFO] 02-langgraph.py:75 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:85 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 计算结果是 4826。

==================================================
用户: 你好，你叫什么名字？

[DEBUG] 02-langgraph.py:68 - 进入 LLM 节点
[INFO] 02-langgraph.py:75 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:85 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 你好！我叫Qwen，你的专属助手。有什么我可以帮助你的吗？

==================================================
用户: 什么是人工智能？

[DEBUG] 02-langgraph.py:68 - 进入 LLM 节点
[INFO] 02-langgraph.py:75 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:85 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 人工智能（Artificial Intelligence，简称AI）是指由人类制造出来的具有一定智能的机器。这些机器能够执行通常需要人类智能才能完成的任务，比如学习、推理、问题解决、感知环境、规划和交流等。

简单来说，人工智能就是让计算机系统表现出类似于人类智能的行为，包括但不限于通过数据处理来模拟人类的认知过程。随着技术的发展，AI已经在许多领域取得了显著的进展，如自然语言处理、图像识别、自动驾驶汽车以及复杂的决策支持系统等。

目前，人工智能主要分为弱人工智能（也称为狭义人工智能）和强人工智能（或称通用人工智能）。前者专注于解决特定任务的问题，而后者则旨在创建能够像人类一样进行广泛智能活动的人工智能。

==================================================
用户: 谢谢你的帮助

[DEBUG] 02-langgraph.py:68 - 进入 LLM 节点
[INFO] 02-langgraph.py:75 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:85 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 不客气，有什么我可以帮忙的吗？如果你有任何问题或需要计算什么数学表达式，或是想要掷骰子，都可以随时告诉我。
[INFO] 02-langgraph.py:150 - 所有测试完成
```


## 关键点总结
| 问题                       | 答案                                                                   |
| :------------------------- | :-------------------------------------------------------------------- |
| 谁决定要不要用工具？        | **LLM（大语言模型）**，不是 LangGraph                                  |
| LangGraph 做什么？          | 提供工具描述（`bind_tools`）、执行工具（`ToolNode`）、路由控制（条件边） |
| 如何判断 LLM 想用工具？     | 检查 `AIMessage` 中是否有 `tool_calls` 字段                            |
| 为什么 LLM 能做出正确判断？ | 因为工具的 **docstring（描述文档）** 告诉了 LLM 每个工具的用途          |

这就是为什么写好工具的 docstring 非常重要——LLM 靠它来理解工具的用途，从而做出正确的调用决策。
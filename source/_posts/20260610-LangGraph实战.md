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

<!-- more --> 


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


os.environ["NO_PROXY"] = "localhost,127.0.0.1"
os.environ["no_proxy"] = "localhost,127.0.0.1"

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
        for tc in response.tool_calls:
            LOG(f"🔍 原始工具调用: name={tc['name']}, args={tc['args']}", "INFO")
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
        "帮我连续掷两次骰子，然后计算他们的和是多少？",   # 连续调用
        # 不会调用工具的问题（直接回答）
        "你好，你叫什么名字？",
        "什么是人工智能？",                       
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

输出
```
==================================================
用户: 帮我掷个骰子

[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:77 - LLM 决策：调用工具 roll_dice
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=roll_dice, args={'sides': 6}
[DEBUG] 02-langgraph.py:89 - 路由决策：需要调用工具 → 前往 tools 节点
🔧 调用工具: roll_dice
[DEBUG] 02-langgraph.py:34 - 掷骰子工具被调用，sides=6, result=4
📦 工具结果: 🎲 掷了一个6面骰子，结果：4
[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:81 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:91 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 你掷的这个6面骰子的结果是4。

==================================================
用户: 帮我算一下 127 * 38 等于多少

[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:77 - LLM 决策：调用工具 calculator
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=calculator, args={'expression': '127 * 38'}
[DEBUG] 02-langgraph.py:89 - 路由决策：需要调用工具 → 前往 tools 节点
🔧 调用工具: calculator
[DEBUG] 02-langgraph.py:44 - 计算器工具被调用，expression=127 * 38, result=4826
📦 工具结果: 🧮 127 * 38 = 4826
[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:81 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:91 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 计算结果是 4826。

==================================================
用户: 帮我连续掷两次骰子，然后计算他们的和是多少？

[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:77 - LLM 决策：调用工具 roll_dice
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=roll_dice, args={}
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=roll_dice, args={}
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=calculator, args={'expression': '{{dice_roll1}} + {{dice_roll2}}'}
[DEBUG] 02-langgraph.py:89 - 路由决策：需要调用工具 → 前往 tools 节点
🔧 调用工具: roll_dice
🔧 调用工具: roll_dice
🔧 调用工具: calculator
[DEBUG] 02-langgraph.py:34 - 掷骰子工具被调用，sides=6, result=1
[DEBUG] 02-langgraph.py:34 - 掷骰子工具被调用，sides=6, result=3
[ERROR] 02-langgraph.py:47 - 计算错误：name 'dice_roll1' is not defined
📦 工具结果: 计算错误：name 'dice_roll1' is not defined
[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:77 - LLM 决策：调用工具 roll_dice
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=roll_dice, args={}
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=roll_dice, args={}
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=calculator, args={'expression': '{{dice_roll1}} + {{dice_roll2}}'}
[DEBUG] 02-langgraph.py:89 - 路由决策：需要调用工具 → 前往 tools 节点
🔧 调用工具: roll_dice
🔧 调用工具: roll_dice
🔧 调用工具: calculator
🤖 Agent: It seems there was an issue with the variable names used in the calculation step. Let's correct that and recalculate the sum of the two dice rolls.

I'll first roll the dice again to get the results.

[DEBUG] 02-langgraph.py:34 - 掷骰子工具被调用，sides=6, result=3
[DEBUG] 02-langgraph.py:34 - 掷骰子工具被调用，sides=6, result=2
[ERROR] 02-langgraph.py:47 - 计算错误：name 'dice_roll1' is not defined
📦 工具结果: 计算错误：name 'dice_roll1' is not defined
[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:77 - LLM 决策：调用工具 roll_dice
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=roll_dice, args={}
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=calculator, args={'expression': '{{dice_roll1}} + {{dice_roll2}}'}
[DEBUG] 02-langgraph.py:89 - 路由决策：需要调用工具 → 前往 tools 节点
🔧 调用工具: roll_dice
🔧 调用工具: calculator
🤖 Agent: It appears there's still an issue with the variable names. Let me correct that and calculate the sum of the two dice rolls.

I'll roll the dice again to get the results.

[DEBUG] 02-langgraph.py:34 - 掷骰子工具被调用，sides=6, result=1
[ERROR] 02-langgraph.py:47 - 计算错误：name 'dice_roll1' is not defined
📦 工具结果: 计算错误：name 'dice_roll1' is not defined
[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:77 - LLM 决策：调用工具 calculator
[INFO] 02-langgraph.py:79 - 🔍 原始工具调用: name=calculator, args={'expression': '1 + 3'}
[DEBUG] 02-langgraph.py:89 - 路由决策：需要调用工具 → 前往 tools 节点
🔧 调用工具: calculator
🤖 Agent: It seems there's a persistent issue with the variable names. Let me manually calculate the sum of the two dice rolls that were rolled.

The first roll was 1 and the second roll was 3, so their sum is:

[DEBUG] 02-langgraph.py:44 - 计算器工具被调用，expression=1 + 3, result=4
📦 工具结果: 🧮 1 + 3 = 4
[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:81 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:91 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: The sum of the two dice rolls (1 and 3) is 4. Thank you for your patience! If you have any other questions or need further assistance, feel free to ask.

==================================================
用户: 你好，你叫什么名字？

[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:81 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:91 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 你好！我叫Qwen，你的专属助手。有什么我可以帮助你的吗？

==================================================
用户: 什么是人工智能？

[DEBUG] 02-langgraph.py:72 - 进入 LLM 节点
[INFO] 02-langgraph.py:81 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:91 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 人工智能（Artificial Intelligence，简称AI）是指由人类制造出来的具有一定智能的机器。这些机器能够执行通常需要人类智能才能完成的任务，比如学习、推理、问题解决、感知环境、规划和交流等。

简单来说，人工智能就是让计算机系统表现出类似于人类智能的行为，包括但不限于通过数据处理来模拟人类的认知过程。随着技术的发展，AI已经在许多领域取得了显著的进展，如自然语言处理、图像识别、自动驾驶汽车以及复杂的决策支持系统等。

目前，人工智能主要分为弱人工智能（也称为狭义人工智能）和强人工智能（或称通用人工智能）。前者专注于解决特定任务的问题，而后者则旨在创建能够像人类一样进行广泛智能活动的人工智能。
[INFO] 02-langgraph.py:151 - 所有测试完成

```  
  
根据输出结果可知，当用户问“帮我连续掷两次骰子，然后计算他们的和是多少？”时，模型大概进行了五个阶段：

| 阶段  | 发生了什么                                        | 结果         |
| :---- | :----------------------------------------------- | :----------- |
| 第1轮 | LLM 用占位符 `'{{dice_roll1}} + {{dice_roll2}}'` | ❌ 计算失败 |
| 第2轮 | LLM 重复同样错误                                  | ❌ 再次失败 |
| 第3轮 | LLM 开始调整，但还是用了占位符                     | ❌ 仍然失败 |
| 第4轮 | LLM 放弃了占位符，直接用具体数字 `'1 + 3'`         | ✅ 计算成功 |
| 第5轮 | LLM 输出最终答案                                  | ✅ 正确回答 |

怎么优化呢？第一，换个大点的模型，理解能力更强；第二，加几个专用工具，把常见计算包好；第三，在 SystemMessage 里写清楚规则，让模型按套路出牌。
  
整个过程虽然有些坎坷，但这毕竟是“小”模型的正常表现。从中可以看出，Agent 具备一定的智能性和容错性：我们无需手动编写循环，它就能自主完成“感知—思考—行动”的闭环。  
  



## 关键点总结
| 问题                       | 答案                                                                   |
| :------------------------- | :-------------------------------------------------------------------- |
| 谁决定要不要用工具？        | **LLM（大语言模型）**，不是 LangGraph                                  |
| LangGraph 做什么？          | 提供工具描述（`bind_tools`）、执行工具（`ToolNode`）、路由控制（条件边） |
| 如何判断 LLM 想用工具？     | 检查 `AIMessage` 中是否有 `tool_calls` 字段                            |
| 为什么 LLM 能做出正确判断？ | 因为工具的 **docstring（描述文档）** 告诉了 LLM 每个工具的用途          |

这就是为什么写好工具的 docstring 非常重要——LLM 靠它来理解工具的用途，从而做出正确的调用决策。



# 添加记忆模块


## 为什么要加记忆：支持多轮对话
在之前的代码中，虽然同一轮程序运行内 Agent 能通过 State 累积记住对话，但一旦程序重启，所有记忆就会丢失。

没有持久化记忆的问题：
```py

👤 你: 你好 我叫张三  

[DEBUG] 02-langgraph.py:73 - 进入 LLM 节点
[INFO] 02-langgraph.py:82 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:92 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 你好，张三！很高兴认识你。有什么我可以帮助你的吗？


# 程序重启后，再次运行

👤 你: 我叫什么

[DEBUG] 02-langgraph.py:73 - 进入 LLM 节点
[INFO] 02-langgraph.py:82 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:92 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 您似乎没有提供足够的信息来确定您的名字。您可以告诉我更多关于您的事情以便我能更好地帮助您吗？比如，您来自哪里，或者有什么特别的兴趣爱好？请提供更多细节，这样我可以更准确地回答您的问题。
```


记忆模块的核心价值：

- 跨会话记忆：程序重启后仍能记住历史对话

- 多用户隔离：不同用户（thread_id）的记忆互不干扰

- 状态恢复：可以从任意历史节点恢复执行


##   使用 MemorySaver
LangGraph 提供了多种 Checkpointer 实现，最基础的是 MemorySaver。它的核心原理是：在每个节点执行后，自动保存当前 State 的快照到内存字典中。

```
┌─────────────────────────────────────────────────────────────┐
│                        用户请求                               │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Pregel 执行引擎                                             │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐                 │
│  │ LLM节点 │ →  │ 工具节点 │ →  │ LLM节点 │ → 输出          │
│  └────┬────┘    └────┬────┘    └────┬────┘                 │
│       ↓              ↓              ↓                        │
│  ┌────────────────────────────────────────────────┐         │
│  │         MemorySaver.storage                     │         │
│  │  ┌──────────────────────────────────────────┐  │         │
│  │  │ "thread_id_1": {                         │  │         │
│  │  │   "checkpoint_1": {state_snapshot},      │  │         │
│  │  │   "checkpoint_2": {state_snapshot},      │  │         │
│  │  │   ...                                     │  │         │
│  │  │ }                                         │  │         │
│  │  └──────────────────────────────────────────┘  │         │
│  └────────────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

- 安装与导入

```py
from langgraph.checkpoint.memory import MemorySaver
```

- 使用方法

```
# 1. 创建记忆存储对象
memory = MemorySaver()

# 2. 编译图时传入 checkpointer 参数
app = workflow.compile(checkpointer=memory)
```


注意：MemorySaver 是内存存储，程序重启后记忆会丢失。如需持久化，可使用 SqliteSaver：
```py

# pip install langgraph-checkpoint-sqlite
from langgraph.checkpoint.sqlite import SqliteSaver

memory = SqliteSaver.from_conn_string("checkpoints.db")
app = workflow.compile(checkpointer=memory)
```


完整代码如下：
```py
from langchain_core.tools import tool
from langchain_core.messages import BaseMessage, HumanMessage, AIMessage
from langchain_openai import ChatOpenAI
from langgraph.graph import StateGraph, END, add_messages
from langgraph.prebuilt import ToolNode
from langgraph.checkpoint.memory import MemorySaver
from typing import TypedDict, Annotated, List
import random
import math
from langgraph.checkpoint.sqlite import SqliteSaver
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


os.environ["NO_PROXY"] = "localhost,127.0.0.1"
os.environ["no_proxy"] = "localhost,127.0.0.1"

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
        for tc in response.tool_calls:
            LOG(f"🔍 原始工具调用: name={tc['name']}, args={tc['args']}", "INFO")
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
# 创建记忆存储
DB_PATH = ".checkpoints.db"
with SqliteSaver.from_conn_string(DB_PATH) as memory:
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

    # 编译并启用记忆
    app = workflow.compile(checkpointer=memory)
    LOG(f"Graph 编译完成，已启用 SQLite 记忆功能 (数据库: {DB_PATH})", "INFO")

    # ========== 8. 交互式对话 ==========
    # 使用相同的 thread_id，记忆会自动保留
    config = {"configurable": {"thread_id": "test_user"}}
    LOG(f"测试配置创建完成，thread_id: test_user", "INFO")
    
    print("\n" + "=" * 50)
    print("🤖 LangGraph Agent 已启动")
    print("💡 支持工具：掷骰子(roll_dice)、计算器(calculator)")
    print("💡 输入 'exit' 或 'quit' 退出，输入 'clear' 清空对话历史")
    print("💡 注意：现在已启用 SQLite 记忆功能，对话历史会持久化保存")
    print("=" * 50 + "\n")
    
    while True:
        # 获取用户输入
        user_input = input("👤 你: ").strip()
        
        # 退出条件
        if user_input.lower() in ["exit", "quit"]:
            print("🤖 Agent: 再见！")
            break
        
        # 清空历史：重新生成新的 thread_id
        if user_input.lower() == "clear":
            config = {"configurable": {"thread_id": "test_user_clear"}}
            print("🤖 Agent: 对话历史已清空（新会话）")
            continue
        
        # 跳过空输入
        if not user_input:
            continue
        
        print()
        
        # 流式处理用户输入
        for step in app.stream(
            {"messages": [HumanMessage(content=user_input)]},
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
        
        print()
    
    LOG("对话结束", "INFO")
    
```



测试输出

```
👤 你: 我叫张三

[DEBUG] 02-langgraph.py:73 - 进入 LLM 节点
[INFO] 02-langgraph.py:82 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:92 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 您好，张三。有什么可以帮助您的吗？如果您有任何问题或需要解答的数学表达式，请告诉我。


# 程序重启
👤 你: 我叫什么

[DEBUG] 02-langgraph.py:73 - 进入 LLM 节点
[INFO] 02-langgraph.py:82 - LLM 决策：直接回答
[DEBUG] 02-langgraph.py:92 - 路由决策：无需调用工具 → 结束流程
🤖 Agent: 您刚才提到您自己名字是“张三”。所以，您现在称呼自己为“张三”。如果您有其他问题或需要帮助，请随时告知。
```
生成了个文件：
```
checkpoints.db
checkpoints.db-shm
checkpoints.db-wal
```

| 文件名              | 作用                                                       | 是否必需 |
| :----------------- | :-------------------------------------------------------- | :------- |
| checkpoints.db     | 主数据库文件，存储实际的 checkpoint 数据（对话历史、状态等） | 必需     |
| checkpoints.db-shm | 共享内存文件，用于 WAL 模式下的索引加速                      | 辅助     |
| checkpoints.db-wal | 预写日志文件，暂存未提交的事务，提高写入性能                 | 辅助     |


可以看到，保持了记忆性。其实，就相当于深度模型训练的checkpoint，加载之后可以接着训练，实现了持久化记忆和断点续传。


可以用数据库软件打开查看表结构，例如DB Browser for SQLite，表结构分析如下；

```
┌─────────────────────────────────────────────────────────────────┐
│                        checkpoints 表                            │
├─────────────────────────────────────────────────────────────────┤
│ thread_id="test_user"                                           │
│   ├── checkpoint_id="A" (parent=NULL)   ← 第一个快照            │
│   ├── checkpoint_id="B" (parent="A")    ← 第二个快照            │
│   └── checkpoint_id="C" (parent="B")    ← 第三个快照            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 关联
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     checkpoint_writes 表                         │
├─────────────────────────────────────────────────────────────────┤
│ thread_id="test_user", checkpoint_id="B"                        │
│   ├── 待写入的 channel: "messages"                              │
│   └── 待写入的 channel: "agent_state"                           │
└─────────────────────────────────────────────────────────────────┘
```

关键设计思想

| 字段                  | 示例值            | 含义                                 |
| :------------------- | :--------------- | :----------------------------------- |
| thread_id            | test_user        | 用户会话标识                          |
| checkpoint_id        | 1f165477-5354... | 每个 checkpoint 唯一 ID              |
| parent_checkpoint_id | 1f165477-5353... | 形成链式结构，指向上一状态            |
| type                 | msggck           | Messages Checkpoint 类型             |
| metadata.source      | input / loop     | input=用户输入触发，loop=内部循环触发 |
| metadata.step        | -1, 0, 1, 2...   | 当前执行的步骤数                      |



# 调试与常见问题
| 问题                | 解决方法                             |
| :------------------ | :----------------------------------- |
| 不知道内部发生了什么 | 用 `stream()` 遍历输出每个节点        |
| 工具调用失败         | 返回友好错误提示，添加重试机制        |
| LLM 用了占位符       | 调低 `temperature`，优化 Prompt 描述 |
| LLM 参数名错误       | 在 `docstring` 中明确说明参数格式     |
| 多步推理失败         | 升级模型或添加复合工具                |
| 输出了奇怪的格式     | 添加 `SystemMessage` 引导            |


推荐配置（小模型）

```py
# 1. 温度设为 0
TEMPERATURE = 0

# 2. 添加系统提示
system_prompt = SystemMessage(content="你是AI助手，严格遵守规则...")

# 3. 工具描述要详细明确
@tool
def roll_dice(sides: int = 6) -> str:
    """【重要】只用于生成随机数，返回格式固定为：🎲 掷了一个X面骰子，结果：Y"""

# 4. 使用更精细的日志
# 5. 考虑升级到 7B 模型获得更好体验
```

温度系数
| temperature | 效果 | 适用场景 |
| :--- | :--- | :--- |
| 0 | 最确定，每次都一样 | 工具调用、结构化输出 |
| 0.3-0.5 | 有一定多样性 | 一般对话 |
| 0.7-1.0 | 创意性高 | 写作、头脑风暴 |



# 总结
LangGraph对比手写ReAct的核心优势：

1. **声明式流程编排**：用节点和边描述逻辑，而非用 `if-else` 嵌套
2. **自动状态管理**：State 在节点间自动传递和合并
3. **原生循环支持**：工具 → LLM → 工具的循环天然支持
4. **内置记忆机制**：`MemorySaver` / `SqliteSaver` 轻松实现多轮对话
5. **可观测性强**：`stream()` 能看到每一步的执行细节

通过本教程，你已经掌握了：
- LangGraph 核心概念：State、Node、Edge、Conditional Edge
- 工具定义与使用：@tool 装饰器、docstring 的重要性
- Agent 构建流程：从单工具到多工具的完整实现
- 记忆模块：MemorySaver 实现多轮对话
- 调试技巧：stream() 遍历、错误处理、Prompt 优化
- 扩展方向：RAG、人工审批、Web API （Fast API）


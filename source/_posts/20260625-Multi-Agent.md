---
title: Multi-Agent
date: 2026-06-25
tags: Skills
mathjax: true
---


# Mutli-Agent的定义

多智能体系统是一种配置，其中两个或以上的 LLM 驱动型智能体协同工作，每个智能体拥有独立的角色、工具和记忆，以完成单个智能体无法独立处理的任务。这些智能体通过明确的交接、共享状态或群组聊天协调器（决定由谁发言）进行协调。每个智能体拥有独立的子追踪、交接跨度，并产生一个联合结果。像 CrewAI、AutoGen、Google ADK、LangGraph、OpenAI Agents SDK、Mastra、Strands、Pydantic-AI 和 Microsoft AutoGen Studio 等框架以不同的方式实现了这一模式。



<!-- more --> 

目前，多智能体架构已成为智能体产品的默认选择。有趣的问题不再是“我是否应该构建多智能体系统？”，而是“如何追踪跨越四个角色的 40 个跨度的运行？”、“如何在评估单个智能体和联合结果时兼顾两者？”以及“当在已有的三智能体团队中添加第四个智能体时，如何防止成本和延迟失控？”等等...


参考：[https://futureagi.com/glossary/multi-agent-system/](https://futureagi.com/glossary/multi-agent-system/)

## 单 Agent 的瓶颈
一个单体 Agent 带着二十个工具和十项职责，最终会面临：
- 系统提示词臃肿：所有工具定义和规则塞进一个上下文
- 工具选择脆弱：模型在大量工具中做出正确选择的概率下降
- 上下文溢出：长对话轨迹中，上下文窗口很快被撑爆
将工作拆分给多个专家——研究员、写作者、审查员——通常在准确性上优于单体，且调试难度大大降低


## 三股力量的推动


第一，推理模型的成本压力。推理模型（如 o-series、Claude 的 extended thinking）每轮输出 10-40K Token。让一个模型同时做规划、编码、审查，既浪费上下文也浪费成本。专业化分工——小模型做规划，推理模型只做难点——显著降低开销。

第二，MCP 标准化了工具访问。MCP 协议让一个五 Agent 团队共享十个 MCP Server 变得容易，而不是一个季度的工程。

第三，基准测试验证了多 Agent 的有效性。Agent 基准（τ-bench、SWE-Bench Verified、GAIA L3）奖励"规划 + 执行 + 审查"的拆分模式，而Multi-Agent 系统恰好能完美地落地这个流程。



# Multi-Agent 系统的常见协作模式

业界实践中，有五种协作模式反复出现：


- 管理者-工作者模式（Manager-Worker）

一个 Orchestrator（编排者）将任务分解并委托给多个 Specialist Agent（专家智能体）。这是客户支持和研究产品中最常见的模式。

典型应用：客服系统（分流 Agent + 解决 Agent）、研究工具（OpenAI Deep Research、Perplexity Pro 每查询运行 5+ 个专家 Agent）


- 流水线模式（Assembly-Line）

Agent 按顺序传递中间产物，形成流水线。常见于内容生产和文档分析。

典型应用：研究员 → 写作者 → 审查员（CrewAI 的典型模式）


- 辩论模式（Debate）

两个 Agent 争论，一个裁判 Agent 做最终决定。常见于安全关键型工作流。

典型应用：法律审查、安全决策

- 规划-执行-审查三元组（Planner-Executor-Critic）

这是 ReAct 的扩展版本，编码 Agent 的典型模式。

典型应用：Cursor、Claude Code、Aider 等编码 Agent
 
- 群体模式（Swarm）

多个 Agent 并行工作，一个 Reducer（归约器）聚合结果。常见于研究和分析任务。


# 主流框架对比


| 框架                                  | 协调形态            | 最佳场景                   | 特点                                                                |
| :----------------------------------- | :------------------ | :------------------------ | :----------------------------------------------------------------- |
| **LangGraph**                        | 显式图 + 状态管理   | 复杂条件控制流             | 图结构，状态由框架管理                                              |
| **CrewAI**                           | 命名角色 + 顺序任务 | 流水线（研究→写→审查）     | 任务中心，角色分明                                                  |
| **AutoGen**                          | 群聊 + 管理者       | 分支式讨论                 | 自由对话，管理者决定谁发言                                           |
| **OpenAI Agents SDK**                | 交接优先            | OpenAI 模型间的专家委托    | 面向 SDK，第一类子 Agent 分发                                       |
| **Microsoft Agent Framework (MAF)**  | 工作流 + 图编排     | 生产级、企业级多智能体系统 | AutoGen + Semantic Kernel 官方继任者，统一了研究灵活性与企业级可靠性 |

补充说明：AutoGen 已于 2025 年底进入维护模式，不再接收新功能，官方推荐新用户和项目转向 MAF。MAF 继承了 AutoGen 的对话式多智能体协作模式，并补齐了工程化短板，如内置检查点、可观测性、对 MCP 的原生支持等，专为生产环境设计。
教程可以看：[https://github.com/microsoft/agent-framework/tree/main/python/samples/01-get-started](https://github.com/microsoft/agent-framework/tree/main/python/samples/01-get-started)


# Multi-Agent 系统面临的挑战

Multi-Agent 在工程层面已经成熟，但学界揭示了一些更深层的问题。

- 外部组织病
当 Agent 被成批放出去干活时，会出现资源竞争和协调失效。

Cursor 的长程编码 Agent 研究发现：20 个 Agent 同时工作时，吞吐量会下降到相当于 1 到 3 个 Agent。Agent 会持有锁太久、忘记释放锁、在不必加锁时加锁。更麻烦的是，Agent 会开始挑"安全的活"——不愿碰大型、复杂、易冲突的任务，而是去改注释、补边角、整理格式。

解法：Cursor 后来改成层级结构——root planner 理解全局、拆解任务，sub-planner 管理子任务，worker 只负责局部任务，完成后写交接报告。外部系统要管的不是谁去干活，而是信息流如何组织。


- 群体认知病
Agent 不只是并发执行系统，它们还是交流系统。

信息隐藏问题：Yuxuan Li 等人的研究发现，在分布式信息条件下，Multi-Agent 的推理准确率仅为 30.1%。但如果把完整信息直接给单个 Agent，准确率是 80.7%。讨论只围着已经摆到桌面上的信息转，每个人手里的关键碎片没有被逼出来。

从众压力：MAEBE 研究发现，Agent 在群体中会改变判断。Claude 中有 62.8% 的收敛被归因为"同伴压力"——Agent 明确说"考虑到其他人的观点""基于多数意见"而改变了答案。

旁观者效应：Shehata 和 Li 的研究发现，多 Agent 场景下，单个 Agent 会降低自己的认知投入——默认"别人会补上""群体会修正"。这不是被说服，而是在多 Agent 场景里卸下了自己的推理责任。


- 如何应对？

Harness（外部协调系统）能约束 Agent 的手——权限、上下文、文件、日志——但难以约束 Agent 的"胆"和"判断"。

可行的策略：

1. 信息显式化：让每个 Agent 显式汇报自己知道什么、不知道什么、和别人不同在哪里

2. 隔离决策：关键判断由独立 Agent 做出，避免群体偏见

3. 人工兜底：在关键节点保留人工干预和审查的能力



- 进阶方向

1. 可观测性：为每个 Agent 的轨迹独立追踪，评估每个角色的成功率

2. 成本管控：设置硬步数上限（如 max_steps = 12），用语义缓存处理幂等的子 Agent 调用

3. 跨框架追踪：当你的系统横跨 Mastra TypeScript 编排器和 Python LangGraph 子 Agent 时，保持统一的追踪轨迹




# 代码示例 - AutoGen

- 框架
```
用户问题
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    通用助手 (中转站)                             │
│  1. 理解用户意图                                                │
│  2. 判断问题类型                                                │
│  3. 选择合适的专家工具并调用                                     │
└─────────────────────────────────────────────────────────────────┘
    │                    │                    │
    ▼                    ▼                    ▼
┌─────────┐      ┌─────────┐      ┌─────────┐
│数学专家  │      │化学专家  │      │(可扩展) │
│(工具)    │      │(工具)    │      │         │
└─────────┘      └─────────┘      └─────────┘
    │                    │                    │
    └────────────────────┼────────────────────┘
                         ▼
               ┌─────────────────┐
               │  整合结果返回用户 │
               └─────────────────┘
```

- 代码
- 
```py
# 参考源码： https://github.com/microsoft/autogen
import asyncio

from autogen_agentchat.agents import AssistantAgent
from autogen_agentchat.tools import AgentTool
from autogen_agentchat.ui import Console
from autogen_ext.models.openai import OpenAIChatCompletionClient
from autogen_ext.models.openai._model_info import ModelFamily

# ========== 禁用代理（解决 502） ==========
import os
os.environ["NO_PROXY"] = "localhost,127.0.0.1"
os.environ["no_proxy"] = "localhost,127.0.0.1"
for key in ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"]:
    os.environ.pop(key, None)


async def main() -> None:
    # ========== 使用本地 Ollama ==========
    model_client = OpenAIChatCompletionClient(
    model="qwen3.5:4b",                # 确保与 `ollama list` 中的名称完全一致
    base_url="http://localhost:11434/v1",
    api_key="ollama",
    model_info={
        "vision": False,               # 纯文本模型设为 False
        "function_calling": True,      # 核心：开启工具调用，否则 AgentTool 无法工作
        "json_output": True,           # Qwen 支持结构化 JSON 输出
        "family": ModelFamily.UNKNOWN,    # 指定模型家族为 Qwen
    },
)

    # model_client = OpenAIChatCompletionClient(
    #             model="deepseek-r1:1.5b",
    #             base_url="http://localhost:11434/v1",
    #             api_key="placeholder",
    #             model_info={
    #                 "vision": False,
    #                 "function_calling": False,  # The model does not support function calling.
    #                 "json_output": False,
    #                 "family": ModelFamily.R1,
    #                 "structured_output": True,
    #             },
    #         )

    # ---------- 数学专家 Agent ----------
    math_agent = AssistantAgent(
        "math_expert",
        model_client=model_client,
        system_message="你是一个数学专家，擅长解决数学问题。",
        description="数学专家助手",
        model_client_stream=True,
    )
    math_agent_tool = AgentTool(math_agent, return_value_as_last_message=True)

    # ---------- 化学专家 Agent ----------
    chemistry_agent = AssistantAgent(
        "chemistry_expert",
        model_client=model_client,
        system_message="你是一个化学专家，擅长解决化学问题。",
        description="化学专家助手",
        model_client_stream=True,
    )
    chemistry_agent_tool = AgentTool(chemistry_agent, return_value_as_last_message=True)

    # ---------- 通用助理 Agent（带工具） ----------
    agent = AssistantAgent(
        "assistant",
        system_message="你是一个通用助理。当需要数学或化学知识时，请使用相应的专家工具。",  #  由规则
        model_client=model_client,
        model_client_stream=True,
        tools=[math_agent_tool, chemistry_agent_tool],
        max_tool_iterations=10,
    )

    # ---------- 运行 ----------
    print("\n" + "=" * 60)
    print("🔬 多专家 Agent 系统 (基于 AutoGen + Ollama)")
    print("   - 数学专家: qwen3.5:4b")
    print("   - 化学专家: qwen3.5:4b")
    print("   - 通用助理: qwen3.5:4b")
    print("=" * 60 + "\n")

    await Console(agent.run_stream(task="∫ x² dx 的不定积分结果是什么？"))
    await Console(agent.run_stream(task="水的分子量是多少？"))
    await Console(agent.run_stream(task="中国古代四大发明有哪些？"))
    
    
if __name__ == "__main__":
    asyncio.run(main())
```

- 运行结果


```
============================================================
🔬 多专家 Agent 系统 (基于 AutoGen + Ollama)
   - 数学专家: qwen3.5:4b
   - 化学专家: qwen3.5:4b
   - 通用助理: qwen3.5:4b
============================================================

---------- TextMessage (user) ----------
∫ x² dx 的不定积分结果是什么？
---------- ToolCallRequestEvent (assistant) ----------
[FunctionCall(id='call_u95subrs', arguments='{"task":"请计算不定积分 ∫ x² dx 的结果。我需要用幂函数的积分公式来解决这个问题。x的指数是多少？应该应用什么样的公式？最终的求解结果是什么，并且不要忘记加上积分常数C吗？"}', name='math_expert')]
---------- TextMessage (user) ----------
请计算不定积分 ∫ x² dx 的结果。我需要用幂函数的积分公式来解决这个问题。x的指数是多少？应该应用什么样的公式？最终的求解结果是什么，并且不要忘记加上积分常数C吗？
---------- ModelClientStreamingChunkEvent (math_expert) ----------
你好！作为一名数学专家，我很乐意为你解答这个问题。计算不定积分 $\int x^2 \, dx$ 的过程如下：

### 1. 确定指数 ($x$ 的指数是多少？)
在待积函数 $f(x) = x^2$ 中，变量 $x$ 的底数是常数项为 **2**。因此，这里的 $n=2$。由于 $n \neq -1$，可以应用幂函数的积分公式。

### 2. 应用的公式 (应该应用什么样的公式？)
你需要使用**不定积分的幂函数公式**（Power Rule for Integration）。该通用表达为：
$$ \int x^n \, dx = \frac{x^{n+1}}{n+1} + C $$
其中 $n$ 是常数且 $n \neq -1$。

### 3. 具体计算步骤 (最终的求解结果是什么？)
根据上述公式，我们将 $x^2$ 对应到 $x^n$：
*   **代入** $n = 2$；
*   **应用规则**：将指数加 1（即 $2 + 1 = 3$），然后将整体除以新增加的整数数。

计算过程如下：
$$ \int x^2 \, dx = \frac{x^{2+1}}{2+1} + C $$
$$ = \frac{x^3}{3} + C $$

### 4. 最终结果 (不要忘记加上积分常数 $C$)
是的，必须记住不定积分的结果包含一个任意常数 **$C$**。因此：

**最终答案：**
$$ \int x^2 \, dx = \frac{1}{3}x^3 + C $$
---------- ToolCallExecutionEvent (assistant) ----------
[FunctionExecutionResult(content='你好！作为一名数学专家，我很乐意为你解答这个问题。计算不定积分 $\\int x^2 \\, dx$ 的过程如下：\n\n### 1. 确定指数 ($x$ 的指数是多少？)\n在待积函数 $f(x) = x^2$ 中，变量 $x$ 的底数是常数项为 **2**。因此，这里的 $n=2$。由于 $n \\neq -1$，可以应用幂函数的积分公式。\n\n### 2. 应用的公式 (应该应用什么样的公式？)\n你需要使用**不定积分的幂函数公式**（Power Rule for Integration）。该通用表达为：\n$$ \\int x^n \\, dx = \\frac{x^{n+1}}{n+1} + C $$\n其中 $n$ 是常数且 $n \\neq -1$。\n\n### 3. 具体计算步骤 (最终的求解结果是什么？)\n根据上述公式，我们将 $x^2$ 对应到 $x^n$：\n*   **代入** $n = 2$；\n*   **应用规则**：将指数加 1（即 $2 + 1 = 3$），然后将整体除以新增加的整数数。\n\n计算过程如下：\n$$ \\int x^2 \\, dx = \\frac{x^{2+1}}{2+1} + C $$\n$$ = \\frac{x^3}{3} + C $$\n\n### 4. 最终结果 (不要忘记加上积分常数 $C$)\n是的，必须记住不定积分的结果包含一个任意常数 **$C$**。因此：\n\n**最终答案：**\n$$ \\int x^2 \\, dx = \\frac{1}{3}x^3 + C $$', name='math_expert', call_id='call_u95subrs', is_error=False)]
---------- ModelClientStreamingChunkEvent (assistant) ----------
你好！关于不定积分 ∫ x² dx，我已经帮你计算好了详细的步骤：

### 🔗 **应用公式**（幂函数积分规则）
对于 $\int x^n \, dx = \frac{x^{n+1}}{n+1} + C$ 

在这里 $n=2$ 且满足条件。

---

### 🧮 **具体计算过程：**
$$\int x^2 \, dx = \frac{x^{2+1}}{2+1} + C$$  
$$ 
= \frac{x^3}{3} + C
 $$

✅**最终答案：** $\displaystyle \int x^2 \, dx = \boxed{\frac{1}{3}x^3 + C}$  

记得别忘了积分常数 $C$ 哦！如有其他数学题目，随时告诉我 😊
---------- TextMessage (user) ----------
水的分子量是多少？
---------- ToolCallRequestEvent (assistant) ----------
[FunctionCall(id='call_hsecqm7h', arguments='{"task":"请计算水的分子量（摩尔质量）。已知组成水分子的元素是氢(H)和氧(O)，我需要知道它们的相对原子质量和分子结构，然后进行计算得出结果是多少克每摩尔？"}', name='chemistry_expert')]
---------- TextMessage (user) ----------
请计算水的分子量（摩尔质量）。已知组成水分子的元素是氢(H)和氧(O)，我需要知道它们的相对原子质量和分子结构，然后进行计算得出结果是多少克每摩尔？
---------- ModelClientStreamingChunkEvent (chemistry_expert) ----------
你好！我是化学专家。很高兴能为你解答关于水（$H_2O$）的分子量及摩尔质量的计算问题。

以下是详细的分析过程、分子结构描述以及最终的数值推导：

### 1. 确定元素的相对原子质量 (Relative Atomic Mass)
在进行计算之前，我们需要查阅元素周期表或相关科学常数标准来获取氢（Hydrogen, H）和氧（Oxygen, O）的近似相对原子质量。根据 IUPAC（国际纯粹与应用化学联合会）的标准数据：

*   **氢 (H)** 的平均相对原子质量约为：**1.008**
    *   （在许多基础教学环境中，为了计算简便常取整数 `1`）
*   **氧 (O)** 的平均相对原子质量约为：**15.999**（通常简化为 **16**）

### 2. 水的分子结构描述
了解了组成元素后，我们来看水分子的微观结构和化学式：

*   **化学式**: $H_2O$
    *   这意味着一个水分子由 **2个氢原子** 和 **1个氧原子** 构成。
*   **空间构型 (Spatial Geometry)**:
    *   根据VSEPR理论（价层电子对互斥模型），氧原子的中心结构呈现出 **“V”形或弯曲状**。氧气分子中的碳氧键角约为 $104.5^\circ$。这是因为氧原子周围有2个成键电子对和2个孤对电子，为了最小化排斥力而采取这种构型（通常被认为是 $\sp^3\text{杂化}$）。
*   **化学键**:
    *   氢与氧之间通过**共价键 (Covalent Bond)** 结合。由于电负性的差异，水分子是一个极性很强的溶剂结构。

### 3. 计算过程 (Calculation)

水的分子量（相对分子质量，$M_r$）在数值上等于各原子的相对原子质量之和。摩尔质量 ($m(M)$) 的数值与 $M_r$ 相等，但单位不同为 $\text{g/mol}$。

**公式：**
$$ M(\text{H}_2\text{O}) = [ n \times m(\text{H}) ] + [ p \times m(\text{O}) ] $$

其中：
*   $n$ 和 $p$ 分别为氢原子和氧原子的数量。

**分步计算：**

1.  **氢部分贡献** ($2 \times H$):
    $$ 2 \times 1.008 = 2.016 $$
2.  **氧部分贡献** ($1 \times O$):
    $$ 1 \times 15.999 \approx 16.00$$
*   *(注：若使用简化整数 $H=1, O=16$，则氢的部分为 $2$, 总加和部分仍非常接近)*

**总计：**
$$ M(\text{H}_2\text{O}) = 2.016 + 15.999 \approx 18.015 $$

### 4. 最终结果 (Final Result)

根据国际标准数据，水的摩尔质量为：

*   **数值**: $\quad$ 约为 $18.015\text{ g/mol}$
    *   （在大多数通用物理化学计算中，为了方便常近似为 **$\mathbf{18 \, \text{g/mol}}$**）

***

### 专家总结：
水的分子量（摩尔质量）**是 18.015 克/每摩尔 ($\text{g/mol}$)**。如果你是在初高中化学练习中，通常会直接使用简化数值 **$18\text{ g/mol}$**。
---------- ToolCallExecutionEvent (assistant) ----------
[FunctionExecutionResult(content='你好！我是化学专家。很高兴能为你解答关于水（$H_2O$）的分子量及摩尔质量的计算问题。\n\n以下是详细的分析过程、分子结构描述以及最终的数值推导：\n\n### 1. 确定元素的相对原子质量 (Relative Atomic Mass)\n在进行计算之前，我们需要查阅元素周期表或相关科学常数标准来获取氢（Hydrogen, H）和氧（Oxygen, O）的近似相对原子质量。根据 IUPAC（国际纯粹与应用化学联合会）的标准数据：\n\n*   **氢 (H)** 的平均相对原子质量约为：**1.008**\n    *   （在许多基础教学环境中，为了计算简便常取整数 `1`）\n*   **氧 (O)** 的平均相对原子质量约为：**15.999**（通常简化为 **16**）\n\n### 2. 水的分子结构描述\n了解了组成元素后，我们来看水分子的微观结构和化学式：\n\n*   **化学式**: $H_2O$\n    *   这意味着一个水分子由 **2个氢原子** 和 **1个氧原子** 构成。\n*   **空间构型 (Spatial Geometry)**:\n    *   根据VSEPR理论（价层电子对互斥模型），氧原子的中心结构呈现出 **“V”形或弯曲状**。氧气分子中的碳氧键角约为 $104.5^\\circ$。这是因为氧原子周围有2个成键电子对和2个孤对电子，为了最小化排斥力而采取这种构型（通常被认为是 $\\sp^3\\text{杂化}$）。\n*   **化学键**:\n    *   氢与氧之间通过**共价键 (Covalent Bond)** 结合。由于电负性的差异，水分子是一个极性很强的溶剂结构。\n\n### 3. 计算过程 (Calculation)\n\n水的分子量（相对分子质量，$M_r$）在数值上等于各原子的相对原子质量之和。摩尔质量 ($m(M)$) 的数值与 $M_r$ 相等，但单位不同为 $\\text{g/mol}$。\n\n**公式：**\n$$ M(\\text{H}_2\\text{O}) = [ n \\times m(\\text{H}) ] + [ p \\times m(\\text{O}) ] $$\n\n其中：\n*   $n$ 和 $p$ 分别为氢原子和氧原子的数量。\n\n**分步计算：**\n\n1.  **氢部分贡献** ($2 \\times H$):\n    $$ 2 \\times 1.008 = 2.016 $$\n2.  **氧部分贡献** ($1 \\times O$):\n    $$ 1 \\times 15.999 \\approx 16.00$$\n*   *(注：若使用简化整数 $H=1, O=16$，则氢的部分为 $2$, 总加和部分仍非常接近)*\n\n**总计：**\n$$ M(\\text{H}_2\\text{O}) = 2.016 + 15.999 \\approx 18.015 $$\n\n### 4. 最终结果 (Final Result)\n\n根据国际标准数据，水的摩尔质量为：\n\n*   **数值**: $\\quad$ 约为 $18.015\\text{ g/mol}$\n    *   （在大多数通用物理化学计算中，为了方便常近似为 **$\\mathbf{18 \\, \\text{g/mol}}$**）\n\n***\n\n### 专家总结：\n水的分子量（摩尔质量）**是 18.015 克/每摩尔 ($\\text{g/mol}$)**。如果你是在初高中化学练习中，通常会直接使用简化数值 **$18\\text{ g/mol}$**。', name='chemistry_expert', call_id='call_hsecqm7h', is_error=False)]
---------- ModelClientStreamingChunkEvent (assistant) ----------
好的！根据计算结果：

### 💧 **水的分子量** 

- **标准值：** 水分子的摩尔质量约为 **$18.015 \text{ g/mol}$**（g/mol） 
- **常用近似值：** $18 \text{ g/mol}$ （在普通化学练习中经常使用此简化数值）

---

### ✨ **拆解计算方式：**
| 元素 | 相对原子质量 | 数量/系数 | 总贡献质量 ($\approx$) |
| :----------- | :----------: | --- | :---------------------: |
| 氢 (H)      | ≈ $1.008 \text{ g/mol}$   | ×2    | $\mathbf{\approx} \phantom{x x}{2.016\,\text{g/mol}}$ |
| 氧 (O)       | ≈ $15.999 \text{ g/mol}$          | ×1     | **$\approx \;\;15.999\dots{\mathbf g}\dots/\mathsf{mol}$**   |

将两者相加：$M(\mathrm{H}_2\mathrm{O}) = 2.016 + 15.999 ≈ 18.015 \text{ g/mol}$。
---------- TextMessage (user) ----------
中国古代四大发明有哪些？
---------- ModelClientStreamingChunkEvent (assistant) ----------
中国古代**四大发明**是指对中国和世界产生重大影响的四项技术成就，它们分别是：

### 📜 **1. 造纸术（纸张的制作）**
- **改进者：** 东汉时期蔡伦改进了传统的麻纸制作方法
- **意义：** 使文字记录更便捷、成本更低，促进了文化的传播和知识的积累

---

### 🔮 **2. 指南针**  
- **起源：** 战国时期的“司南”是最早的磁性指南北装置
- **发展：** 唐宋时期制成能定向的磁罗盘，用于航海
- **意义：** 为远洋航行提供了重要导航技术，推动大航海时代的到来

---

### 💥 **3. 火药**  
- **发明者：** 唐代炼丹家在炼药过程中意外发现其特性并加以应用
- **发展：** 唐末五代时期开始用于军事战争（如火箭、火炮）
- **影响：** 改变了战争形式，对世界历史进程产生深远冲击

---

### 🖨️ **4. 印刷术**  
- **雕版印刷：** 隋唐时期由王仁昫等人在敦煌等地发明并开始推广
- **活字印刷：** 北宋时期的毕昇首创泥巴活字印刷方式（《梦溪笔谈》中曾有记载）
- **影响：** 大大提高了信息传播效率，对知识普及和文明进程有革命性作用

---

### 🌏 **历史评价**  
这四大发明对中国古代社会产生了巨大推动作用。17世纪德国大哲学家恩格斯曾评价：火药、指南针和对数这三种伟大的发明确定了世界三大发现（如地理大发现和科学进步），是"现代文明的基础和里程碑”。它们也对外传播，深刻影响了人类文明的进程！

如果你对其中某一项发明想了解更详细的历史背景或应用案例，欢迎继续提问 😊

```

 - 解析

| 角色              | 职责                                             | 在你的代码中                                       |
| :---------------- | :---------------------------------------------- | :------------------------------------------------ |
| 通用助手 (中转站) | 接收用户问题 → 判断类型 → 调用对应专家 → 整合结果 | `agent = AssistantAgent("assistant", ...)`        |
| 数学专家          | 专门处理数学问题                                 | `math_agent` 被包装为 `math_agent_tool`           |
| 化学专家          | 专门处理化学问题                                 | `chemistry_agent` 被包装为 `chemistry_agent_tool` |


```txt
用户: ∫ x² dx 的不定积分结果是什么？
    │
    ▼
中转站 (assistant): 判断这是数学问题
    │
    ▼
中转站: 调用 math_expert 工具
    │
    ▼
数学专家: 计算积分 → 返回结果
    │
    ▼
中转站: 整合结果 → 返回用户
```

化学问题也是类似的步骤。


- 总结


| 概念 | 角色 |
| :--- | :--- |
| 通用助手 | 路由器/调度器/结果整合器 |
| 专家工具 | 具体业务执行者 |
| tools 列表 | 中转站可用的专家清单 |
| system_message | 路由规则（告诉中转站什么时候用什么专家） |
| max_tool_iterations | 限制中转站最多调用几轮（防止死循环） |


# 推荐资源


框架：LangGraph (Python)、CrewAI、AutoGen  (github有教程)

可观测性：traceAI (多 Agent 专用)  [https://github.com/future-agi/traceAI](https://github.com/future-agi/traceAI)

阅读：FutureAGI 的 Multi-Agent 指南[multi-agent-system](https://futureagi.com/glossary/multi-agent-system/)


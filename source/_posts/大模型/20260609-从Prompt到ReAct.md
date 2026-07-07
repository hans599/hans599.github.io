---
title: 从Prompt到ReAct
date: 2026-06-09
tags: ReAct
mathjax: true
---

大语言模型（LLM）展示出了惊人的语言理解与生成能力，但其本质仍是一个“静态”的知识系统：它缺乏实时信息获取、工具调用与自主规划的能力。为了让模型从“会说话”进化到“能做事”，研究者们引入了智能体（Agent）的概念。Agent 通过观察环境、调用工具、执行动作并反思结果，来动态地完成复杂任务。本文将从一个简单的 Prompt 工程出发，逐步引出经典的 ReAct 范式，并最终手写一个极简的 Agent 循环，展示 LLM 如何在实际任务中进行“思考”与“行动”。


<!-- more --> 

# 前言：为什么需要Agent？

## LLM 的局限性

- **无法调用工具**：不能主动查询天气、搜索知识、调用计算器等外部工具
- **无记忆机制**：每次对话是独立的，无法跨会话记住用户偏好或历史信息
- **单次推理**：只做一次前向传播，无法根据中间结果调整或反思

## Agent 能做什么？

- **感知（Perception）**：接收用户指令和环境反馈
- **思考（Thought）**：分析当前状态，规划下一步行动
- **行动（Action）**：调用工具（搜索、代码执行、API 请求等）或输出回答
- **循环（Loop）**：重复“思考 → 行动 → 观察”的过程，直到任务完成




# Prompt工程
## Zero-shot vs Few-shot

Zero-shot：直接给出指令，不给示例。

```py

response = client.chat(
    messages=[{"role": "user", "content": "将以下句子翻译成英文：今天天气很好。"}]
)
```

Few-shot：在指令前给出几个示例，让模型理解格式和模式。
```py
prompt = """将中文翻译成英文：
例子：
"你好" -> "Hello"
"谢谢" -> "Thank you"
"晚安" -> "Good night"

现在翻译："今天天气很好"
"""
```

## Chain-of-Thought（CoT）：让模型展示推理过程  


CoT 的核心思想：不直接要答案，让模型先输出推理步骤。

案例：鸡兔同笼问题
问题：笼子里有鸡和兔共35个头，94只脚，问鸡兔各几只？


无 CoT（直接问）：
```py
prompt = "笼子里有鸡和兔共35个头，94只脚，鸡兔各几只？"
```

有 CoT（引导推理）：
```py
prompt = """笼子里有鸡和兔共35个头，94只脚，鸡兔各几只？
让我们一步步思考：
1. 设鸡有x只，兔有y只。
2. 头数：x + y = 35
3. 脚数：2x + 4y = 94
4. 由第2步得 x = 35 - y
5. 代入第3步：2(35 - y) + 4y = 94
6. 70 - 2y + 4y = 94 → 70 + 2y = 94 → 2y = 24 → y = 12
7. 则 x = 35 - 12 = 23
所以答案是：鸡23只，兔12只。"""
```


好的 Prompt 是 Agent 的基石：Agent 的"思考"（Thought）本质上就是 CoT 的延伸，"工具调用"则是在 Few-shot 示例中让模型学会特定输出格式。


# ReAct范式：让LLM学会“思考+行动”

## ReAct的核心思想


ReAct（Reasoning + Acting）由 Yao et al. [ReAct: Synergizing Reasoning and Acting in Language Models, ICLR 2023](https://arxiv.org/abs/2210.03629) 提出，核心思想是TAO 循环（Thought → Action → Observation）：让 LLM 交替做 “推理（Thought）” 和 “行动（Action）”，并根据环境反馈（Observation）循环迭代，用推理指导行动、用行动修正推理，解决纯推理幻觉和纯行动短视问题。


流程图示：
```text
┌─────────────────────────────────────────────────────────┐
│                     用户输入                              │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  Thought: 我现在需要做什么？下一步应该调用哪个工具？       │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  Action: 调用工具（如 search、calculate、get_weather）    │
│         传入具体参数                                      │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  Observation: 工具返回的结果                              │
└─────────────────────────────────────────────────────────┘
                            ↓
                    ┌───────┴───────┐
                    │   任务完成？   │
                    └───────┬───────┘
                        Yes ↓      ↓ No
                    ┌──────────┐  ┌─────────────────────┐
                    │ 输出答案  │  │ 继续循环：Thought → │
                    │  结束    │  │ Action → Observation│
                    └──────────┘  └─────────────────────┘
```

一个典型的三步循环示例：
```py
用户：今天北京天气怎么样？适合户外运动吗？

Thought: 我需要先获取北京的天气信息，然后根据天气判断是否适合运动。
Action: get_weather(city="北京")
Observation: 北京今日晴，气温18-28℃，风力2级，空气质量良。

Thought: 天气晴朗，气温舒适，风力小，空气质量良好，适合户外运动。
Action: finish(answer="北京今天天气晴好，气温18-28℃，非常适合户外运动。")
```

## ReAct vs CoT的区别

| 维度           | CoT (Chain-of-Thought) | ReAct (Reasoning + Acting)          |
| :------------- | :--------------------- | :---------------------------------- |
| 核心思想       | 通过推理步骤得出答案     | 推理 + 行动交替，与环境交互           |
| 是否调用工具   | 否，纯文本推理          | 是，可调用外部工具                   |
| 信息来源       | 仅模型内部知识          | 模型知识 + 外部环境反馈              |
| 适用场景       | 数学推理、逻辑题        | 需要实时信息、多步操作的任务          |
| 典型输出格式   | 推理过程 → 答案         | Thought → Action → Observation 循环 |
| 可处理实时问题 | 不能（如“今天天气”）    | 能（通过搜索/API）                   |
| 错误恢复能力   | 弱（一步错步步错）      | 强（观察可纠正后续推理）              |

从 CoT （只会想） 到 WebGPT （只会做），再到 ReAct （边想边做），可以看作是大模型从“思想者”向“行动派”，最终成为“有执行力的战略家”的演进路径


# 手写一个最简ReAct循环


```py
"""
最简 ReAct 循环 - 使用 DummyLLMClient 测试
"""

import datetime
import math
import re
import json
from typing import Dict, Any, List

# ==================== 工具定义 ====================

def get_current_time() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def calculator(expression: str) -> str:
    try:
        allowed_names = {
            "abs": abs, "round": round, "min": min, "max": max,
            "sum": sum, "pow": pow, "int": int, "float": float,
            "sqrt": math.sqrt, "pi": math.pi
        }
        result = eval(expression, {"__builtins__": {}}, allowed_names)
        return str(round(result, 10) if isinstance(result, float) else str(result))
    except Exception as e:
        return f"错误: {e}"

TOOLS = {
    "get_current_time": get_current_time,
    "calculator": calculator
}

# ==================== Prompt 模板 ====================

SYSTEM_PROMPT = """你可以使用工具：
- get_current_time: 获取当前时间，无需参数
- calculator: 计算表达式，参数格式 {{"expression": "1+1"}}

输出格式：
Thought: 思考
Action: 工具名
Action Input: 参数

或者直接回答：
Action: finish
Action Input: 答案
"""

def build_prompt(question: str, history: List[Dict] = None) -> List[Dict]:
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    if history:
        messages.extend(history)
    messages.append({"role": "user", "content": question})
    return messages

# ==================== 解析器 ====================

def parse_output(text: str):
    """解析 LLM 输出，提取 action 和 action_input"""
    action_match = re.search(r"Action:\s*(\w+)", text)
    action = action_match.group(1) if action_match else ""
    
    input_match = re.search(r"Action Input:\s*(.+?)(?=\n\s*(?:Thought|Action):|\n*$)", text, re.DOTALL)
    action_input = {}
    if input_match:
        try:
            action_input = json.loads(input_match.group(1).strip())
        except:
            action_input = input_match.group(1).strip()
    
    return action, action_input

# ==================== 主循环 ====================

def react_loop(question: str, llm_client, max_steps: int = 3):
    """ReAct 主循环"""
    history = []
    
    for step in range(1, max_steps + 1):
        print(f"\n[Step {step}]")
        
        messages = build_prompt(question, history)
        response = llm_client.chat(messages)
        output = response["content"]
        print(f"[LLM 输出]\n{output}\n")
        
        action, action_input = parse_output(output)
        print(f"Action: {action}")
        
        if action == "finish":
            answer = action_input if isinstance(action_input, str) else str(action_input)
            print(f"答案: {answer}")
            return answer
        
        if action in TOOLS:
            try:
                if isinstance(action_input, dict):
                    result = TOOLS[action](**action_input)
                else:
                    result = TOOLS[action](action_input) if action_input else TOOLS[action]()
                print(f"Observation: {result}")
                history.append({"role": "assistant", "content": output})
                history.append({"role": "user", "content": f"Observation: {result}"})
            except Exception as e:
                print(f"执行失败: {e}")
                history.append({"role": "assistant", "content": output})
                history.append({"role": "user", "content": f"错误: {e}"})
        else:
            print(f"未知工具: {action}")
            history.append({"role": "assistant", "content": output})
            history.append({"role": "user", "content": f"工具 '{action}' 不存在"})
    
    return "超过最大步数"

# ==================== Mock LLM 客户端（分步响应） ====================

class MockReactClient:
    """模拟 LLM 客户端，支持多步交互"""
    
    def __init__(self):
        self.step_counter = {}
    
    def chat(self, messages):
        # 根据消息历史判断当前步骤
        history_len = len(messages)
        key = str(messages[-1].get("content", ""))[:50]
        
        # 提取用户问题
        question = ""
        for msg in messages:
            if msg.get("role") == "user" and not msg.get("content", "").startswith("Observation:"):
                question = msg.get("content", "")
        
        # 检查历史中是否有 Observation（第二步）
        has_observation = False
        for msg in messages:
            if msg.get("role") == "user" and msg.get("content", "").startswith("Observation:"):
                has_observation = True
                break
        
        # 根据问题和是否有观察结果返回不同响应
        if has_observation:
            # 已有工具结果，返回最终答案
            return {"content": """Thought: 我已经获取到结果，可以回答用户了。
Action: finish
Action Input: 根据工具计算，结果是 5。"""}

        # 第一步：判断需要什么工具
        if "时间" in question or "几点" in question:
            return {"content": """Thought: 用户想知道当前时间，需要调用 get_current_time 工具。
Action: get_current_time
Action Input: {}"""}
        
        elif "计算" in question or "算术" in question or "+" in question:
            # 提取表达式
            if "2+3" in question:
                expr = "2+3"
            elif "123+456" in question:
                expr = "123+456"
            else:
                expr = "2+3*4"
            return {"content": f"""Thought: 这是一个数学计算问题，需要使用 calculator 工具。
Action: calculator
Action Input: {{"expression": "{expr}"}}"""}
        
        else:
            return {"content": """Thought: 这个问题不需要调用工具，直接回答。
Action: finish
Action Input: 这是模拟回复。请问还有其他问题吗？"""}

# ==================== 测试用例 ====================

def run_test(question: str, name: str = ""):
    """运行单个测试用例"""
    print("\n" + "="*50)
    print(f"测试用例: {name or question}")
    print("="*50)
    client = MockReactClient()
    result = react_loop(question, client, max_steps=3)
    print(f"\n>>> 最终结果: {result}")
    return result

if __name__ == "__main__":
    # 测试用例1：数学计算
    run_test("2+3等于多少", "数学计算-简单加法")
    
    # 测试用例2：时间查询
    run_test("现在几点了？", "时间查询")
    
    # 测试用例3：复合运算
    run_test("计算 (123+456) 等于多少", "数学计算-三位数加法")
    
    # 测试用例4：不需要工具的问题
    run_test("你好，请介绍一下你自己", "普通对话")
    
```


运行结果
```
==================================================
测试用例: 数学计算-简单加法
==================================================

[Step 1]
[LLM 输出]
Thought: 这是一个数学计算问题，需要使用 calculator 工具。
Action: calculator
Action Input: {"expression": "2+3"}

Action: calculator
Observation: 5

[Step 2]
[LLM 输出]
Thought: 我已经获取到结果，可以回答用户了。
Action: finish
Action Input: 根据工具计算，结果是 5。

Action: finish
答案: 根据工具计算，结果是 5。

>>> 最终结果: 根据工具计算，结果是 5。

==================================================
测试用例: 时间查询
==================================================

[Step 1]
[LLM 输出]
Thought: 用户想知道当前时间，需要调用 get_current_time 工具。
Action: get_current_time
Action Input: {}

Action: get_current_time
Observation: 2026-06-10 09:52:44

[Step 2]
[LLM 输出]
Thought: 我已经获取到结果，可以回答用户了。
Action: finish
Action Input: 根据工具计算，结果是 5。

Action: finish
答案: 根据工具计算，结果是 5。

>>> 最终结果: 根据工具计算，结果是 5。

==================================================
测试用例: 数学计算-三位数加法
==================================================

[Step 1]
[LLM 输出]
Thought: 这是一个数学计算问题，需要使用 calculator 工具。
Action: calculator
Action Input: {"expression": "123+456"}

Action: calculator
Observation: 579

[Step 2]
[LLM 输出]
Thought: 我已经获取到结果，可以回答用户了。
Action: finish
Action Input: 根据工具计算，结果是 5。

Action: finish
答案: 根据工具计算，结果是 5。

>>> 最终结果: 根据工具计算，结果是 5。

==================================================
测试用例: 普通对话
==================================================

[Step 1]
[LLM 输出]
Thought: 这个问题不需要调用工具，直接回答。
Action: finish
Action Input: 这是模拟回复。请问还有其他问题吗？

Action: finish
答案: 这是模拟回复。请问还有其他问题吗？

>>> 最终结果: 这是模拟回复。请问还有其他问题吗？
```


# 总结
ReAct 是一种让 LLM 实现 Agent 行为的有效范式，但真实的Agent 还包括记忆、规划、反思等更多能力。本篇实现了一个基于 ReAct 的最简 Agent，是入门 Agent 开发的良好起点。
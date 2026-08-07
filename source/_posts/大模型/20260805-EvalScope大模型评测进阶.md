---
title: EvalScope大模型评测进阶
date: 2026-08-05
tags: [智能体, 评测, Agent, 基准]
categories: 大模型
mathjax: true
---


评测能力正在成为AI从业者的核心竞争壁垒之一。不会评测，就无法判断模型是真进步还是假把式；不会评测，在众多模型面前只能是“盲选”。EvalScope作为魔搭社区官方推出的模型评测框架，为这一需求提供了从入门到进阶的完整工具链。

主页：[introduction.html#](https://evalscope.readthedocs.io/zh-cn/v0.8.1/get_started/introduction.html#) 

<!-- more -->

# EvalScope


EvalScope是ModelScope社区官方推出的模型评测与性能基准测试框架，内置了多个常用测试基准和评测指标，如MMLU、CMMLU、C-Eval、GSM8K、ARC、HellaSwag、TruthfulQA、MATH和HumanEval等。它支持多种类型的模型评测，包括大语言模型（LLM）、多模态大模型、Embedding模型和Reranker模型。

 具体的实践以及参数都可以参照官网的教程来。博客仅做简单的介绍。

EvalScope的核心优势体现在三个层面：

- 统一接入机制：兼容多个系列模型的Generate和Chat接口，无论是API调用的模型还是本地运行的模型，都能通过统一的接口进行评测。

- 多后端支持：除了自身的Native评测框架，还集成了OpenCompass和VLMEvalKit作为评测后端，可以轻松发起多模态评测任务。

- 全链路支持：通过与ms-swift训练框架的无缝集成，实现了从模型训练、部署到评测、报告查看的一站式开发流程。


以评测Qwen2.5-0.5B-Instruct模型在GSM8K数据集上的表现为例，一条命令即可完成：

```
evalscope eval \
 --model Qwen/Qwen2.5-0.5B-Instruct \
 --datasets gsm8k \
 --limit 10
```

执行后，EvalScope会自动下载模型和数据集，运行评测并输出结构化的结果表格

```
+-----------------------+----------------+-----------------+-----------------+---------------+-------+---------+
| Model                 | Dataset Name   | Metric Name     | Category Name   | Subset Name   |   Num |   Score |
+=======================+================+=================+=================+===============+=======+=========+
| Qwen2.5-0.5B-Instruct | gsm8k          | AverageAccuracy | default         | main          |     5 |     0.4 |
+-----------------------+----------------+-----------------+-----------------+---------------+-------+---------+
```

**评测模式扩展**

EvalScope支持从本地模型到API服务的多种评测场景。对于已部署的模型服务，只需指定服务地址即可评测：
```
evalscope eval \
 --model qwen2.5 \
 --api-url http://127.0.0.1:8801/v1 \
 --api-key EMPTY \
 --eval-type openai_api \
 --datasets gsm8k \
 --limit 10
```

通过--repeats参数可以指定重复生成次数，并使用不同的聚合方式（如mean_and_vote_at_k）来提升评测的鲁棒性。



# LLM-as-a-Judge评测

当面对主观性任务（如开放式问答、创意写作）时，传统的准确率指标无法有效评估模型输出质量。LLM-as-a-Judge的核心思路是：用一个强大的模型来评价目标模型的输出质量。

EvalScope的裁判模型评测支持两种方式：

1. 自动选择裁判策略：根据数据集类型自动匹配合适的裁判模型

2. 自定义裁判模型配置：指定特定的模型作为裁判


以评测中文简单问答（chinese_simpleqa）为例：
```py
import os
from evalscope import TaskConfig, run_task
from evalscope.constants import JudgeStrategy

task_cfg = TaskConfig(
    model='qwen2.5-7b-instruct',
    api_url='https://dashscope.aliyuncs.com/compatible-mode/v1',
    api_key=os.getenv('DASHSCOPE_API_KEY'),
    eval_type='openai_api',
    datasets=['chinese_simpleqa'],
    limit=5,
    judge_strategy=JudgeStrategy.AUTO,
    judge_model_args={
        'model_id': 'qwen2.5-72b-instruct',
        'api_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'api_key': os.getenv('DASHSCOPE_API_KEY'),
    }
)

run_task(task_cfg=task_cfg)
```


EvalScope支持Agent评测，允许模型在受控的多轮工具调用循环中完成评测任务，并把完整交互过程录制下来供回放与复盘。

Agent评测提供两种模式 

| 模式             | 适用场景                                                                          |
| :--------------- | :------------------------------------------------------------------------------- |
| 内置AgentLoop    | 给常规基准（GSM8K、AIME等）套上多轮工具调用循环，评测模型自身的工具使用能力            |
| 外部Agent Bridge | 直接评测Claude Code、OpenCode等成品Agent CLI，EvalScope把CLI的LLM请求转发到评测模型 |


启用Agent评测后，每条样本都会附带一条Trace，通过Web界面可以按步骤回放完整交互过程，包括每一步的模型回复（含推理过程、延迟与token用量）、工具调用与观察结果、沙箱内执行的命令以及系统提醒与异常。

# 思考效率评测


对于推理类模型（如DeepSeek-R1、QwQ-32B），EvalScope提供了思考效率评测能力，从六个维度评估模型表现：

- 推理token数：模型推理过程中的总token数

- 首次正确token数：从起始位置到第一个正确答案位置的token数

- 剩余反思token数：首次正确答案到推理结束的token数

- token效率：首次正确token数占总token数的比例

- 子思维链数量：推理过程中的思维跳转次数

- 准确率：正确样本占比

评测结果显示，o1/R1类推理模型存在两种极端现象：

- Underthinking（思考不足）：模型频繁进行思路跳转，无法集中注意力深入思考

- Overthinking（过度思考）：模型在简单问题上生成过长的思维链，浪费计算资源

例如，对于"2+3=？"这样的问题，某些长推理模型可能会消耗超过900个token来探索多种解题策略。这凸显了如何在保证答案质量的同时提高思考效率的关键问题。



# EvalSope+OpenCompass实战 

参考：[opencompass_backend.html](https://evalscope.readthedocs.io/zh-cn/v0.8.1/user_guides/backend/opencompass_backend.html)



## 环境准备

``` bash
# 安装opencompass依赖
pip install evalscope[opencompass] -U
```


## 数据准备

linux
```bash
# ModelScope下载
wget -O eval_data.zip https://www.modelscope.cn/datasets/swift/evalscope_resource/resolve/master/eval.zip

# 或使用github下载
wget -O eval_data.zip https://github.com/open-compass/opencompass/releases/download/0.2.2.rc1/OpenCompassData-complete-20240207.zip

# 解压
unzip eval_data.zip
```


windows
```bash 
curl -L -o eval_data.zip https://www.modelscope.cn/datasets/swift/evalscope_resource/resolve/master/eval.zip

unzip eval_data.zip
```


## 部署模型服务



ms-swift部署

参考：[ms-swift](https://github.com/modelscope/ms-swift)

```bash
pip install ms-swift -U
```

部署
```bash
CUDA_VISIBLE_DEVICES=0 swift deploy --model_type qwen2-0_5b-instruct --port 8000
```
如果没有模型，会自动下载到`C:\Users\<你的用户名>\.cache\huggingface\hub\`


如果有下载好的本地模型也可以，不过要额外指定需要参数
```bash
# CPU部署
swift deploy --model E:/xxxx/models/qwen2-0_5b-instruct --model_type qwen2 --template qwen --infer_backend transformers --torch_dtype float32 --port 8000
```


部署完成之后测试一下api
```
curl http://127.0.0.1:8000/v1/models
```

## 模型评测
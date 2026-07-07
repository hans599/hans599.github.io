---
title: PagedAttention 原理与具体实现
date: 2026-07-07
tags: PageAttention
mathjax: true
categories: 
  - 大模型   
---


# KV Cache的内存管理困境



KV Cache 的大小会随着序列长度和并发请求数迅速增长。以 OPT-13B 模型为例，单个 token 的 KV Cache 占用约 800KB（2 × 5120 × 40 × 2 bytes）。若生成完整的 2048 个 token，单个请求的 KV Cache 就高达约 1.6GB。而且在 Parallel Sampling 或 Beam Search 等场景中，多个生成分支共享相同的 prompt，理论上可以共享其 KV Cache。然而传统系统将每个分支的 KV Cache 存放在独立连续空间中，物理上无法共享，只能冗余复制。




<!-- more --> 


传统推理系统（如 FasterTransformer、Orca）采用预分配策略：请求开始时，按最大可能序列长度分配一整块连续内存。这造成三类浪费：

```
┌─────────────────────────────────────────────────────────────┐
│  请求A (预留 2048 tokens)       │ 预留  │  请求B (512)   │
│  ┌──────────────────────────────┼───────┼───────────────┤
│  │  实际使用   │  内部碎片      │  ...  │ 外部碎片      │
│  └──────────────────────────────┴───────┴───────────────┘
└─────────────────────────────────────────────────────────────┘
```
- 预留但未用空间（Reserved）：后续会使用，但当前不可用

- 内部碎片（Internal Fragmentation）：实际 token 数远小于预留长度，剩余空间永久浪费

- 外部碎片（External Fragmentation）：不同请求大小不一，内存块间产生不可用空隙

vLLM论文（[vLLM: An Efficient Inference Engine for Large Language Models](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2025/Archive/EECS-2025-192.pdf#12#3)）数据显示，传统系统中真正用于存放 KV Cache 的有效内存占比最低仅 20.4 - 38.2%。


<!-- more --> 


# PagedAttention 核心思想：借鉴操作系统虚拟内存
PagedAttention 的核心思想，来自操作系统的虚拟内存分页机制（Virtual Memory & Paging）。在 OS 中，虚拟内存将地址空间划分为固定大小的"页"（Page），映射到物理内存中的任意位置，从而实现非连续分配，有效解决碎片和共享问题。

PagedAttention 将这一思路引入 KV Cache 管理：
```
传统方式（连续内存）：
┌──────────────────────────────────────────────────────┐
│  Request A (预留 2048)  │  空闲  │  Request B      │
└──────────────────────────────────────────────────────┘

PagedAttention（分页管理）：
┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐
│ A1 │ B1 │ A2 │ C1 │ B2 │ A3 │ C2 │ B3 │ C3 │ A4 │
└────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘
```

PagedAttention 将每个请求的 KV Cache 划分为固定大小的 KV block，每个 block 存储固定数量（默认 16）个 token 的 Key 和 Value 向量。这些 block 可以存储在非连续的物理内存中，通过 Block Table 维护逻辑块到物理块的映射，类似 OS 中的页表。


## 三大核心设计

### 按需分配，消除碎片


由于所有 block 大小相同，分配和回收不会产生外部碎片；按需分配避免了预分配造成的内部碎片。



### 逻辑-物理映射（Block Table）
```
逻辑视图（连续）：
┌──────────┬──────────┬──────────┬──────────┐
│ Block 0  │ Block 1  │ Block 2  │ Block 3  │
└──────────┴──────────┴──────────┴──────────┘
      │          │          │          │
      ▼          ▼          ▼          ▼
物理视图（可能不连续）：
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ 7  │ 1  │ 3  │ 5  │ 2  │ 8  │ 4  │ 6  │
└────┴────┴────┴────┴────┴────┴────┴────┘

Block Table:
┌──────────┬──────────┐
│ Logical  │ Physical │
│ Block 0  │ Block 7  │
│ Block 1  │ Block 1  │
│ Block 2  │ Block 3  │
│ Block 3  │ Block 5  │
└──────────┴──────────┘
```

### Copy-on-Write 共享
PagedAttention 允许多个序列共享同一个物理 block。当某个分支需要写入新 token 时，使用 Copy-on-Write（写时复制） 机制：只有在该分支需要修改共享 block 时，才将其复制到新的物理位置。




# CUDA 内核实现详解

vLLM 的 PagedAttention CUDA 内核位于 csrc/attention/attention_kernels.cu，本节基于官方设计文档进行解读。
[https://docs.vllm.ai/en/v0.22.1/design/paged_attention/#query](https://docs.vllm.ai/en/v0.22.1/design/paged_attention/#query)


 ##  核心概念

| 概念                        | 说明                                                                                                                |
| :------------------------- | :------------------------------------------------------------------------------------------------------------------ |
| **Sequence（序列）**       | 代表一个客户端请求。内核中每个序列只有一个查询 token，`num_seqs` 等于批处理 token 总数。                               |
| **Context（上下文）**      | 序列中已生成的 token，如 `["What", "is", "your"]`。                                                                  |
| **Vec**                    | 一次获取和计算的一组元素。Q/K 数据的 `VEC_SIZE` 使每个线程组一次获取 16 字节数据。                                     |
| **Thread Group（线程组）** | `THREAD_GROUP_SIZE` 个线程，一次获取并计算一个 Q token 和一个 K token。                                              |
| **Block（KV 块）**         | 存储固定数量（`BLOCK_SIZE`）token 在一个 head 上的 K/V 数据。                                                        |
| **Warp**                   | 32 个线程的组，在 SM 上同步执行；每个 warp 一次处理一个 Q token 与一个完整 block 的 K token。                          |
| **Thread Block（线程块）** | 一组可访问相同共享内存的线程，每个 thread block 处理一个 Q token 与整个上下文的 K token。                              |
| **Grid**                   | 形状为 `(num_heads, num_seqs, max_num_partitions)`，每个 thread block 处理一个 head、一个 sequence、一个 partition。 |


## 内存布局与访问模式


**Query数据加载：**

每个 thread group 获取一个 query token 数据。每个线程通过 q_ptr 指向全局内存，相邻线程读取相邻内存，实现内存合并（memory coalescing） 以提升性能。

```cpp
const scalar_t* q_ptr = q + seq_idx * q_stride + head_idx * HEAD_SIZE;
__shared__ Q_vec q_vecs[THREAD_GROUP_SIZE][NUM_VECS_PER_THREAD];
```

**Key数据加载：**

与 q_ptr 不同，k_ptr 在不同迭代中指向不同 key token。每个线程通过 k_cache 在分配的 block、head 和 token 处定位 key 数据，读取到寄存器内存 k_vecs 中（因只会被一个线程访问一次）。


## QK 点积与 Softmax

QK 点积与 Softmax：

```
┌─────────────────────────────────────────────────────────────┐
│  伪代码：QK 点积与 Softmax                                  │
│                                                             │
│  1. 获取查询数据，存入 q_vecs（共享内存）                    │
│                                                             │
│  2. 外层循环：遍历不同 token 的 k_ptrs                      │
│     ├── 内层循环：准备 k_vecs（寄存器内存）                 │
│     └── 执行 q_vecs 与每个 k_vecs 的点积                   │
│                                                             │
│  3. 跨线程组归约（reduction）→ 得到完整点积结果             │
│                                                             │
│  4. 整个线程块内进行 Softmax 归一化                         │
└─────────────────────────────────────────────────────────────┘
```

关键设计：每个线程只获取部分 Q/K 数据，但通过跨 thread group 的归约（reduction），得到的是整个 Q 和 K 之间的完整点积结果。例如 HEAD_SIZE=128，THREAD_GROUP_SIZE=2 时，每个线程的 k_vecs 含 64 个元素，但返回的 qk 是 128 个查询元素和 128 个键元素之间的完整点积。


# 自动前缀缓存

vLLM 在 PagedAttention 基础上进一步实现了自动前缀缓存（Automatic Prefix Caching）。

每个 KV block 可通过块内 token + 块前缀 token唯一标识：
```
Block 1: [A gentle breeze stirred]
Block 2: [the leaves as children]  ← 前缀包含 Block 1
Block 3: [laughed in the distance] ← 前缀包含 Block 1 + Block 2
```

因此可建立映射：hash(prefix tokens + block tokens) ↔ KV Block。

vLLM 维护一个全局哈希表，所有物理 block 存入其中。当多个请求共享相同前缀时，它们映射到相同的物理 block，共享内存空间，无需重复计算和存储。

当缓存空间不足时，vLLM 采用三级驱逐策略：
1. 驱逐引用计数为 0 的 block（当前无请求使用）
2. 若多个，优先驱逐最近最少使用（LRU） 的 block
3. 若访问时间相同，优先驱逐位于最长前缀末尾的 block
该策略在 Full Attention 模型上等价于 RadixAttention 的驱逐策略，即优先驱逐前缀树中引用计数为零且最近最少使用的叶节点



**性能对比** 
vLLM 团队将 vLLM 与 HuggingFace Transformers（HF）和 HuggingFace Text Generation Inference（TGI）对比：

| 对比对象                      | 测试配置                | 吞吐量提升       |
| :--------------------------- | :--------------------- | :-------------- |
| **vLLM vs HuggingFace (HF)** | LLaMA-7B, NVIDIA A10G  | **最高 24 倍**  |
| **vLLM vs TGI**              | LLaMA-13B, NVIDIA A100 | **最高 3.5 倍** |
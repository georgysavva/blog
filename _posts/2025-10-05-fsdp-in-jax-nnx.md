---
title: FSDP tutorial for JAX NNX
date: 2025-10-05 14:10:00 -0500
render_with_liquid: true
---

If you find yourself with the daunting task of implementing production-level [FSDP](https://engineering.fb.com/2021/07/15/open-source/fsdp/) in JAX NNX, then this tutorial is for you. This notebook will guide you step by step through the process.

You will learn how to implement a fully working FSDP on TPU — with all critical operations JIT compiled — that evenly shards all weights across the devices together with DDP. Additionally, you will see how to use distributed checkpointing to save to/restore from disk or GCP bucket via Orbax, set up reproducible nnx.Rngs for noise generation and dropout, and maintain an EMA model that is also sharded. You can find the full codebase and executable notebook [here](https://github.com/georgysavva/fsdp-in-jax-nnx).

Let's begin.

{::nomarkdown}
{% assign jupyter_path = 'assets/jupyter/fsdp_in_jax_nnx.ipynb' | relative_url %}
{% jupyter_notebook jupyter_path %}
{:/nomarkdown}


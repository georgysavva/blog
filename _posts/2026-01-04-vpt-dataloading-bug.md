---
title: VPT actions data loading bug
date: 2026-01-04 14:10:00 -0500
render_with_liquid: true
---




At some point during my work on Solaris, a multiplayer world model for Minecraft, we decided to cover our data loading code with end-to-end tests. Our training pipeline consisted of two stages: single-player model pretraining on the [VPT](https://github.com/openai/Video-Pre-Training) dataset and main multiplayer model training on a custom multiplayer dataset. So, after covering the main multiplayer data loading code with tests, we proceeded to cover the VPT data loading code.

## Spotting the bug with tests

Surprised, we saw that the VPT data loading tests failed for camera action values. The camera actions are a numpy array consisting of two numbers for `X` and `Y` degrees of change. When writing our tests, we expected them to be float numbers due to the way they get converted from raw pixels [here](https://github.com/openai/Video-Pre-Training/blob/095519fbd4ee0e9281d19f19601e45629de9ac3f/run_inverse_dynamics_model.py#L103-L104), and no explicit rounding present in the code. However, our dataloading code produced integers, dropping the part after the floating point. For example, it output `[5, 5]` instead of `[5.625, 5.625]`. This rounding behavior was the only issue with the dataloading code, and it affected any number in the `-180.0` to `+180.0` range. To confirm it wasn’t on our side, we added a [test](https://github.com/georgysavva/Video-Pre-Training/blob/18ad2fd39a326d4a028e66ed61cfd562713bd027/tests/test_json_action_to_env_action.py) to the original VPT codebase, and it failed there just the same.

## Finding root cause

Surprised that the original dataloading code would do rounding for no apparent reason, we asked ChatGPT to investigate. Turned out, the evasive rounding behavior stemmed from the way the empty camera action array was initialized [here](https://github.com/openai/Video-Pre-Training/blob/095519fbd4ee0e9281d19f19601e45629de9ac3f/run_inverse_dynamics_model.py) and [here](https://github.com/openai/Video-Pre-Training/blob/095519fbd4ee0e9281d19f19601e45629de9ac3f/run_inverse_dynamics_model.py). The code initialized it as an integer numpy array, `np.array([0, 0])`, so that, even though later the [code](https://github.com/openai/Video-Pre-Training/blob/095519fbd4ee0e9281d19f19601e45629de9ac3f/run_inverse_dynamics_model.py#L103-L104) assigned a float value there, it was implicitly converted to an integer.

## Analyzing impact

So the dataloading code had — from the way it’s written — a most likely unintended rounding behavior. It was a bug, but was it a problem? Logically, you wouldn’t want to lose any precision in the camera actions. If the absolute value is big enough, for example, `175.9`, then `175` vs `175.9` doesn’t make much difference: the relative error size is only 0.5%. However, at low values, the relative error is quite large: `2.9` vs `2.0`, which is a `45%` error. Here is a breakdown of how the relative error grows as the absolute value decreases:

| actual | rounded |  error |
| -----: | ------: | -----: |
|   22.9 |    22.0 |  0.00% |
|   21.9 |    21.0 |  0.00% |
|   20.9 |    20.0 |  0.00% |
|   19.9 |    19.0 |  2.56% |
|   18.9 |    18.0 |  2.63% |
|   17.9 |    17.0 |  5.56% |
|   16.9 |    16.0 |  2.86% |
|   15.9 |    15.0 |  2.94% |
|   14.9 |    14.0 |  6.25% |
|   13.9 |    13.0 |  3.23% |
|   12.9 |    12.0 |  6.90% |
|   11.9 |    11.0 |  3.57% |
|   10.9 |    10.0 |  7.69% |
|    9.9 |     9.0 |  8.33% |
|    8.9 |     8.0 |  9.09% |
|    7.9 |     7.0 | 10.00% |
|    6.9 |     6.0 | 11.11% |
|    5.9 |     5.0 | 12.50% |
|    4.9 |     4.0 | 23.08% |
|    3.9 |     3.0 | 30.00% |
|    2.9 |     2.0 | 42.86% |
|    1.9 |     1.0 | 75.00% |

Okay, so we know that the relative error in camera actions is big when the value is small. But was it really a problem? A popular world model, [Oasis](https://oasis-model.github.io/), trained on the VPT dataset, intentionally clipped all camera action degree values above `20.0`, so that `29.0` became `20.0`, resulting in the same `45%` relative error.

To answer this question, we ran statistics on the VPT dataset and got the following camera action distribution diagram:

![VPT Camera Actions Distribution](assets/img/2026-01-04-vpt-dataloading-bug/camera_act_histogram.png)
_Camera actions distribution of the VPT dataset_

It shows that low-range values, `0.0` — `3.0`, have most of the probability mass, whereas `20.0+` values are negligibly infrequent.

The above distribution, combined with large relative errors at low values, makes most of the data the world model sees during training quite noisy. For example, there could be two frames where the agent spins with a `2.9` camera speed and two frames where it spins at a `2.0` camera speed. There will be a visual difference in rotation between the two pairs of frames because the underlying ground truth camera speed was different, but the model will see the same `2.0` in both cases, which leads to suboptimal training.

## Fix

The fix was to change `np.array([0, 0])` to `np.array([0.0, 0.0], dtype=np.float32)` in the two camera array initialization places: [commit](https://github.com/openai/Video-Pre-Training/commit/4ac7eb0cf092f19b55ee76c0bbade73f45a5131e). With it, the test I mentioned earlier passes.

The VPT codebase authors confirmed the bug: [comment](https://github.com/openai/Video-Pre-Training/issues/54#issuecomment-3740785896). However, they didn’t add the fix because their codebase isn’t world model specific and advised world model projects to adjust accordingly in a fork. I believe that all world model projects training on VPT should use the fixed code. A forked repo with the fix is available [here](https://github.com/georgysavva/Video-Pre-Training).
